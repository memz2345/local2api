// Node 运行时（Android）的纯逻辑回归：
//   · apt Packages 索引解析（包名 -> URL/大小）；
//   · deb 解包（ar 切片 -> XZ -> Tar -> 只抽 usr/bin、usr/lib，剥 termux
//     前缀，跳过 include/share 与 symlink）。
// 测试用例手工构造一个 mini deb（tar -> xz -> ar），全链路本地验证，
// 不打网络。
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/node_runtime_service.dart';

void main() {
  group('parsePackagesIndex', () {
    test('解析包名 / 版本 / Filename / Size / Depends', () {
      const text = '''
Package: nodejs
Version: 26.4.0-1
Architecture: aarch64
Depends: libc++, openssl, c-ares, libicu, libsqlite, zlib, libffi
Filename: pool/main/n/nodejs/nodejs_26.4.0-1_aarch64.deb
Size: 10349280

Package: npm
Version: 11.21.1
Filename: pool/main/n/npm/npm_11.21.1_all.deb
Size: 2032505

Package: zlib
Version: 1.3.2
Filename: pool/main/z/zlib/zlib_1.3.2_aarch64.deb
Size: 62862
''';
      final index = parsePackagesIndex(text);
      expect(index.keys, containsAll(['nodejs', 'npm', 'zlib']));
      expect(index['nodejs']!['Version'], '26.4.0-1');
      expect(
        index['nodejs']!['Filename'],
        'pool/main/n/nodejs/nodejs_26.4.0-1_aarch64.deb',
      );
      expect(index['nodejs']!['Size'], '10349280');
      expect(index['nodejs']!['Depends'], contains('libicu'));
      expect(index['npm']!['Version'], '11.21.1');
      expect(index.length, 3);
    });

    test('空索引 / 空块不炸', () {
      expect(parsePackagesIndex(''), isEmpty);
      expect(parsePackagesIndex('\n\n\n'), isEmpty);
    });
  });

  group('extractArMembers / extractDebSync', () {
    /// 从 [Archive] 打 deb（支持 symlink 条目）。
    Uint8List buildDebFromArchive(Archive archive) {
      final tarBytes = TarEncoder().encode(archive);
      final xzBytes = XZEncoder().encode(tarBytes);
      final deb = BytesBuilder();
      deb.add('!<arch>\n'.codeUnits);
      void addMember(String name, List<int> content) {
        final nameField = List<int>.filled(16, 0x20);
        final nameBytes = '$name/'.codeUnits;
        nameField.setRange(0, nameBytes.length.clamp(0, 16), nameBytes);
        deb.add(nameField);
        deb.add('0           '.codeUnits); // mtime
        deb.add('0     '.codeUnits); // uid
        deb.add('0     '.codeUnits); // gid
        deb.add('100644  '.codeUnits); // mode
        deb.add('${content.length}'.toString().padLeft(10).codeUnits);
        deb.add('`\n'.codeUnits);
        deb.add(content);
        if (content.length.isOdd) deb.add([0x0a]);
      }

      addMember('debian-binary', '2.0\n'.codeUnits);
      addMember('control.tar.xz', [1, 2, 3]);
      addMember('data.tar.xz', xzBytes);
      return deb.toBytes();
    }

    /// 构造一个 mini deb：data.tar.xz 里放 termux 布局的几个文件。
    Uint8List buildMiniDeb(Map<String, List<int>> files) {
      final archive = Archive();
      files.forEach((path, bytes) {
        archive.add(
          ArchiveFile(path, bytes.length, bytes)
            ..mode = path.contains('/bin/') ? 493 : 420, // 755 / 644
        );
      });
      return buildDebFromArchive(archive);
    }

    test('ar 切片：按成员名取 data.tar.xz', () {
      final deb = buildMiniDeb({
        'data/data/com.termux/files/usr/bin/node': [0x7f, 0x45, 0x4c, 0x46],
      });
      final members = extractArMembers(deb);
      expect(members.keys, containsAll(['debian-binary', 'data.tar.xz']));
      expect(members['data.tar.xz'], isNotNull);
    });

    test('解包：剥 termux 前缀、重建 symlink、跳过 include/share', () {
      final deb = buildMiniDeb({
        'data/data/com.termux/files/usr/bin/node': [1, 2, 3, 4],
        'data/data/com.termux/files/usr/lib/libz.so.1.3.2': [5, 6],
        'data/data/com.termux/files/usr/lib/node_modules/npm/bin/'
                'npm-cli.js':
            'console.log(1)'.codeUnits,
        'data/data/com.termux/files/usr/include/node/node.h': [7],
        'data/data/com.termux/files/usr/share/doc/node/README': [8],
        'etc/should-not-be-extracted': [9],
      });
      final tempDir = Directory.systemTemp.createTempSync('l2a_node_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final debFile = File(
        '${tempDir.path}${Platform.pathSeparator}nodejs.deb',
      )..writeAsBytesSync(deb);
      final dest = Directory(
        '${tempDir.path}${Platform.pathSeparator}node',
      )..createSync();

      final stats = extractDebSync(debFile.path, dest.path);
      expect(stats.files, 3); // bin/node + lib/libz.so.1.3.2 + npm-cli.js

      final join = dest.path;
      expect(File('$join/bin/node').readAsBytesSync(), [1, 2, 3, 4]);
      expect(File('$join/lib/libz.so.1.3.2').readAsBytesSync(), [5, 6]);
      expect(
        File(
          '$join/lib/node_modules/npm/bin/npm-cli.js',
        ).readAsStringSync(),
        'console.log(1)',
      );
      // include / share / 非 usr 路径一律不落地。
      expect(File('$join/include/node/node.h').existsSync(), isFalse);
      expect(File('$join/share/doc/node/README').existsSync(), isFalse);

      // 单独验证 symlink 重建（zlib 的 libz.so.1 就是这种形态）。
      final linkArchive = Archive()
        ..add(ArchiveFile.symlink(
          'data/data/com.termux/files/usr/lib/libz.so.1',
          'libz.so.1.3.2',
        ));
      final linkDebFile = File(
        '${tempDir.path}${Platform.pathSeparator}links.deb',
      )..writeAsBytesSync(buildDebFromArchive(linkArchive));
      final linkDest = Directory(
        '${tempDir.path}${Platform.pathSeparator}links',
      )..createSync();
      extractDebSync(linkDebFile.path, linkDest.path);
      final link = Link('${linkDest.path}/lib/libz.so.1');
      expect(link.existsSync(), isTrue);
      expect(link.targetSync(), 'libz.so.1.3.2');
    });

    test('symlink 排在目标实体文件之前也要落地（soname 不能丢）', () {
      // Termux 的 zlib deb 就是这个顺序：libz.so.1 -> libz.so.1.3.2 在前，
      // 实体文件在后。以前当场复制会找不到源、整个 soname 丢掉，
      // bionic linker 报 "library libz.so.1 not found"。
      final archive = Archive()
        ..add(ArchiveFile.symlink(
          'data/data/com.termux/files/usr/lib/libz.so.1',
          'libz.so.1.3.2',
        ))
        ..add(
          ArchiveFile(
            'data/data/com.termux/files/usr/lib/libz.so.1.3.2',
            2,
            [5, 6],
          )..mode = 420,
        );
      final tempDir = Directory.systemTemp.createTempSync('l2a_node_order');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final debFile = File(
        '${tempDir.path}${Platform.pathSeparator}zlib.deb',
      )..writeAsBytesSync(buildDebFromArchive(archive));
      final dest = Directory(
        '${tempDir.path}${Platform.pathSeparator}node',
      )..createSync();

      extractDebSync(debFile.path, dest.path);

      final soname = File('${dest.path}/lib/libz.so.1');
      expect(soname.existsSync(), isTrue);
      // 宿主支持 symlink 就是软链，不支持（外部存储 / Windows 无权限）就是实体副本；
      // 两种都必须能按名字读到目标内容。
      expect(soname.readAsBytesSync(), [5, 6]);
    });

    test('非 deb 文件抛 FormatException', () {
      final tempDir = Directory.systemTemp.createTempSync('l2a_node_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final bad = File(
        '${tempDir.path}${Platform.pathSeparator}bad.deb',
      )..writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(
        () => extractDebSync(bad.path, tempDir.path),
        throwsFormatException,
      );
    });
  });

  group('下载镜像', () {
    test('默认官方源，切到 cn 后 apt 源与 Packages 地址一起换', () async {
      final node = NodeRuntimeService.instance;
      // 用例共享单例，跑完还原成官方源，别影响同进程里的其它断言。
      addTearDown(() async => node.setMirror(NodeDownloadMirror.official));

      expect(node.mirror, NodeDownloadMirror.official);
      expect(node.repoBase, contains('packages.termux.dev'));
      expect(await node.packagesUrl(), contains('packages.termux.dev'));

      await node.setMirror(NodeDownloadMirror.cn);

      expect(node.mirror, NodeDownloadMirror.cn);
      expect(node.repoBase, contains('mirrors.tuna.tsinghua.edu.cn'));
      expect(await node.packagesUrl(), contains('mirrors.tuna.tsinghua.edu.cn'));
      // 架构后缀不能掉。
      expect(
        await node.packagesUrl(),
        contains('/dists/stable/main/binary-aarch64/Packages'),
      );
      // npm 走 npmmirror（子进程靠 npm_config_registry 认）。
      expect(NodeRuntimeService.npmRegistryCn, 'https://registry.npmmirror.com');
    });
  });
}
