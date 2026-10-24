// 编辑角色页「未保存退出确认」（与上游编辑页同一套交互）的回归测试。
//
// 只测 miuix 版：Material 版复用同一套状态逻辑（_isDirty / _handleBack），
// 且上游编辑页的确认弹窗已有页面级覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_character_card_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CharacterStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = CharacterStore();
    await store.load();
  });

  const kTestCard = CharacterCard(
    id: 'user.1',
    name: '测试卡',
    prompt: '旧人设',
    presets: [ChatPresetPair(user: '旧问', assistant: '旧答')],
  );

  Future<void> pumpEditPage(WidgetTester tester) async {
    // 编辑页拿到的是「existing」引用，但落盘断言走 store —— 先放进去。
    store.upsert(kTestCard);
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
              home: MiuixCharacterEditPage(store: store, existing: kTestCard),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没改过东西：系统返回直接退出，不弹确认', (tester) async {
    await pumpEditPage(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(MiuixCharacterEditPage), findsNothing);
  });

  testWidgets('改了内容再返回：弹「未保存的更改」，不保存直接退出', (tester) async {
    await pumpEditPage(tester);

    // 预制问答卡上的输入框是页面上唯一直接可编辑的
    // （名称 / 人设走编辑器弹层）。
    await tester.enterText(find.byType(MiuixTextField).first, '随手一句');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('未保存的更改'), findsOneWidget);

    await tester.tap(find.text('不保存'));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixCharacterEditPage), findsNothing);
    expect(
      store.cardOf('user.1')!.presets.single.user,
      '旧问',
      reason: '不保存 = 改动不落盘',
    );
  });

  testWidgets('改了内容再返回选保存：存卡并退出', (tester) async {
    await pumpEditPage(tester);

    await tester.enterText(find.byType(MiuixTextField).first, '随手一句');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixCharacterEditPage), findsNothing);
    expect(store.cardOf('user.1')!.presets.single.user, '随手一句');
  });
}
