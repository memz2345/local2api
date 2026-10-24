import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_token_stats_page.dart';
import 'package:local2api/ui/token_stats_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

TokenUsage _rec({
  required DateTime at,
  required String model,
  required int input,
  required int output,
  int hit = 0,
  String keyId = '',
  String keyName = '',
  String keyLabel = '',
}) => TokenUsage(
  timeMs: at.millisecondsSinceEpoch,
  model: model,
  upstream: 'OpenCode Zen',
  lane: 'space-bunny-free',
  input: input,
  output: output,
  cacheHit: hit,
  cacheMiss: input - hit,
  apiKeyId: keyId,
  apiKeyName: keyName,
  apiKeyLabel: keyLabel,
);

/// 内容变长了（多了「各模型用量」表），滚到底再断言。
Future<void> _scrollDown(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    if (find.text('最近记录').evaluate().isNotEmpty) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await usageStats.load();
    usageStats.clear();
  });

  tearDown(() => usageStats.clear());

  void seed({bool withKeys = false}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final kid = withKeys ? 'key-a' : '';
    final kname = withKeys ? '主力' : '';
    final klabel = withKeys ? 'sk-aaaa**1111' : '';
    usageStats
      ..add(
        _rec(
          at: today,
          model: 'zen-free',
          input: 1000,
          output: 200,
          hit: 800,
          keyId: kid,
          keyName: kname,
          keyLabel: klabel,
        ),
      )
      ..add(
        _rec(
          at: today,
          model: 'local',
          input: 40,
          output: 10,
          keyId: kid,
          keyName: kname,
          keyLabel: klabel,
        ),
      )
      ..add(
        _rec(
          at: today.subtract(const Duration(days: 1)),
          model: 'zen-free',
          input: 500,
          output: 100,
          keyId: kid,
          keyName: kname,
          keyLabel: klabel,
        ),
      );
  }

  testWidgets('Material 版：汇总、按天与明细都渲染出来', (tester) async {
    seed();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const TokenStatsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Token 统计'), findsWidgets);
    // 输入 1540 / 输出 310 / 合计 1850，命中 800 → 命中率 51.9%
    final summary = usageStats.summarize();
    expect(summary.total, 1850);
    expect(find.text('1.5k'), findsWidgets);
    expect(find.text('1.9k'), findsWidgets);
    // 「缓存命中」既是汇总卡的一项，也是模型表的列名
    expect(find.text('缓存命中'), findsWidgets);
    expect(find.text('命中率'), findsOneWidget);
    expect(find.text(formatHitRate(summary.hitRate)), findsWidgets);

    // 汇总之后往下翻：模型表、按天图、明细依次排下来
    await _scrollDown(tester);
    expect(find.text('按天'), findsOneWidget);
    expect(find.text('最近记录'), findsOneWidget);
  });

  testWidgets('miuix 版：同样渲染汇总与明细', (tester) async {
    seed();
    await tester.pumpWidget(
      MiuixThemeController(
        colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
        keyColor: const Color(0xFF386A20),
        child: Builder(
          builder: (context) {
            final miuix = MiuixTheme.of(context);
            return MaterialApp(
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light().copyWith(
                colorScheme: materialSchemeFromMiuix(
                  miuix.colors,
                  miuix.brightness,
                ),
              ),
              home: const MiuixTokenStatsPage(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('近 7 天'), findsOneWidget);
    // 「合计」在汇总卡里一项、在模型表里一行
    expect(find.text('合计'), findsWidgets);
    expect(find.text('缓存未命中'), findsWidgets);

    await _scrollDown(tester);
    expect(find.text('最近记录'), findsOneWidget);
  });

  testWidgets('没有记录时给空态提示（两套都不炸）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const TokenStatsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('这段时间还没有记录，跑一轮模型后这里就有数了。'),
      findsOneWidget,
    );
  });

  group('各模型用量表', () {
    Future<void> pumpMiuix(WidgetTester tester) async {
      await tester.pumpWidget(
        MiuixThemeController(
          colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
          keyColor: const Color(0xFF386A20),
          child: Builder(
            builder: (context) {
              final miuix = MiuixTheme.of(context);
              return MaterialApp(
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(
                  colorScheme: materialSchemeFromMiuix(
                    miuix.colors,
                    miuix.brightness,
                  ),
                ),
                home: const MiuixTokenStatsPage(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('只列这段时间里真打过的模型', (tester) async {
      seed();
      // 40 天前的一条：默认「近 7 天」看不到它
      usageStats.add(
        _rec(
          at: DateTime.now().subtract(const Duration(days: 40)),
          model: 'old-ghost',
          input: 9,
          output: 9,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpMiuix(tester);
      await _scrollDown(tester);

      expect(find.text('各模型用量'), findsOneWidget);
      expect(find.text('zen-free'), findsWidgets);
      expect(find.text('local'), findsWidgets);
      expect(find.text('old-ghost'), findsNothing);
    });

    testWidgets('挑了一把 key 后，只有它打过的模型进表', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      usageStats
        ..add(
          _rec(
            at: today,
            model: 'zen-free',
            input: 100,
            output: 20,
            keyId: 'key-a',
            keyName: '主力',
            keyLabel: 'sk-aaaa**1111',
          ),
        )
        ..add(
          _rec(
            at: today,
            model: 'local',
            input: 40,
            output: 10,
            keyId: 'key-b',
            keyName: '备用',
            keyLabel: 'sk-bbbb**2222',
          ),
        );

      // 服务层先把口径定死：两把 key 各自的账
      final rowsA = usageStats.byModel(apiKeyId: 'key-a');
      expect(rowsA.map((r) => r.model), ['zen-free']);
      expect(rowsA.first.summary.total, 120);
      expect(
        usageStats.summarize(apiKeyId: 'key-b').total,
        50,
      );

      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpMiuix(tester);
      await _scrollDown(tester);
      // 没挑 key 时两个模型都在
      expect(find.text('zen-free'), findsWidgets);
      expect(find.text('local'), findsWidgets);
    });
  });
}
