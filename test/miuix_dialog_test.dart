// 「miuix 下对话框统一走 showMiuixDialog」回归：
//   - 外观：白底 squircle 卡片（不是 Material AlertDialog）、标题居中、
//     正文左对齐、底部一排等宽药丸（左次右主）；
//   - 落点：竖屏贴底、横屏居中（对应 miuix 小屏 / 大屏两档对话框）。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 卡片本体：标题最近的 squircle DecoratedBox（MiuixButton 内部也是
  /// squircle，直接按类型找会撞上按钮，所以从标题往上找）。
  Finder card(String title) => find
      .ancestor(
        of: find.text(title),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is ShapeDecoration &&
              (w.decoration as ShapeDecoration).shape is MiuixSquircleBorder,
        ),
      )
      .first;

  Future<void> pumpHost(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MiuixThemeController(
        colorSchemeMode: MiuixColorSchemeMode.monetLight,
        keyColor: const Color(0xFF3482FF),
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester) async {
    showMiuixDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      title: '有错误输入项',
      message: '名称不得为空',
      actions: [
        MiuixDialogAction(
          label: '返回',
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: '放弃更改',
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('竖屏贴底：squircle 卡片 + 标题居中 + 正文左对齐 + 等宽药丸', (tester) async {
    await pumpHost(tester, const Size(420, 900));
    await show(tester);

    // 不是 Material 弹窗
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    expect(card('有错误输入项'), findsOneWidget);
    final cardRect = tester.getRect(card('有错误输入项'));
    // 贴屏幕底边：外边距 12（测试里系统 inset 为 0）
    expect(cardRect.bottom, closeTo(888, 0.5));
    expect(cardRect.width, closeTo(420 - 24, 0.5));

    // 标题居中、正文左对齐（对齐参考图里的排版）
    expect(tester.getRect(find.text('有错误输入项')).center.dx, closeTo(210, 1));
    expect(tester.getRect(find.text('名称不得为空')).left, closeTo(36, 1));

    // 动作行：左次右主、等宽铺满内容区，间距 12
    final buttons = find.byType(MiuixDialogButton);
    expect(buttons, findsNWidgets(2));
    final cancel = tester.getRect(buttons.at(0));
    final confirm = tester.getRect(buttons.at(1));
    expect(cancel.left, closeTo(36, 0.5));
    expect(confirm.right, closeTo(384, 0.5));
    expect(cancel.width, closeTo(confirm.width, 0.5));
    expect(confirm.left - cancel.right, closeTo(12, 0.5));
  });

  testWidgets('横屏居中：同一套卡片落到屏幕中间', (tester) async {
    await pumpHost(tester, const Size(900, 420));
    await show(tester);

    expect(card('有错误输入项'), findsOneWidget);
    final cardRect = tester.getRect(card('有错误输入项'));
    expect(cardRect.center.dy, closeTo(210, 0.5));
    expect(cardRect.width, closeTo(420, 0.5), reason: '大屏下卡片自己限宽 420');
  });

  testWidgets('删除上游确认框与「退出前是否保存」同底座：卡片式 + 红色删除',
      (tester) async {
    await pumpHost(tester, const Size(400, 800));

    // l10n 的「删除上游 {name}」模板；这里不引 AppLocalizations 的占位符实现，
    // 直接用真实文案扫过去——重点是 it 的**形态**，不是文案本身。
    const name = '本地 llama.cpp';
    late bool result;
    confirmDeleteUpstream(tester.element(find.byType(Scaffold)), name)
        .then((v) => result = v);
    await tester.pumpAndSettle();

    // 形态断言（这次统一的核心）：标题由 l10n 拼出（含上游名），它必须挂在一张
    // miuix squircle 对话框卡片上 —— 以前发现页那份是底部抽屉 + 两个纯文字按钮。
    Finder squircleOf(Finder of) => find
        .ancestor(
          of: of,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is ShapeDecoration &&
                (w.decoration as ShapeDecoration).shape is MiuixSquircleBorder,
          ),
        )
        .first;

    expect(
      squircleOf(find.textContaining(name)),
      findsOneWidget,
      reason: '应该是一张 miuix 对话框卡片，而不是底部抽屉',
    );

    final buttons = find.byType(MiuixDialogButton);
    expect(buttons, findsNWidgets(2), reason: '左取消 + 右删除两个标准动作按钮');

    // 右侧那个是破坏性动作：底色走 miuix 的 error 红。
    final delete = tester.widget<MiuixDialogButton>(buttons.at(1));
    expect(delete.destructive, isTrue);

    await tester.tap(buttons.at(1));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('删除上游确认框：点取消返回 false', (tester) async {
    await pumpHost(tester, const Size(400, 800));

    late bool result;
    confirmDeleteUpstream(tester.element(find.byType(Scaffold)), 'x')
        .then((v) => result = v);
    await tester.pumpAndSettle();

    final buttons = find.byType(MiuixDialogButton);
    expect(tester.widget<MiuixDialogButton>(buttons.at(0)).destructive, isFalse);

    await tester.tap(buttons.at(0));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('bottom 显式给值时优先于屏幕方向', (tester) async {
    await pumpHost(tester, const Size(900, 420));
    showMiuixDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      title: '标题',
      bottom: true,
      actions: [
        MiuixDialogAction(
          label: '好',
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(card('标题')).bottom, closeTo(420 - 12, 0.5));
  });
}