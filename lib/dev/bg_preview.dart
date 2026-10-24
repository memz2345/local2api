// 开发/验证用预览入口：只铺一层 BgEffectBackground 全屏，用来在 AVD 上
// 排查效果背景的横纹 / 动画断层。
//
//   flutter build apk --debug -t lib/dev/bg_preview.dart
//   adb install -r build/app/outputs/flutter-apk/app-debug.apk
//   adb shell am start -n com.memz2345.local2api/.MainActivity
//
// 点一下切换明暗预设（对应关于页 light/dark 两套），再点切换 OS2/OS3。
import 'package:flutter/material.dart';
import 'package:local2api/widgets/effect/bg_effect_background.dart';

void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: _PreviewPage(),
    );
  }
}

class _PreviewPage extends StatefulWidget {
  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage> {
  bool _dark = false;
  int _variant = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => setState(() {
          if (_variant == 0) {
            _dark = !_dark;
          } else {
            _variant = (_variant + 1) % 3;
          }
        }),
        onLongPress: () => setState(() => _variant = (_variant + 1) % 3),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: BgEffectBackground(
                  variant: _variant == 1
                      ? BgEffectVariant.os2
                      : BgEffectVariant.os3,
                  dark: _variant == 2 ? !_dark : _dark,
                  isFullSize: true,
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Text(
                'os3 light/dark: tap · variant+dark: long-press '
                '(variant=$_variant dark=$_dark)',
                style: TextStyle(
                  color: _dark ? Colors.white70 : Colors.black54,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
