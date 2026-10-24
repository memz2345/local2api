import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';

/// 顶栏折叠状态从 FrostedPageBar 的入参读，避免依赖像素。
bool _collapsed(WidgetTester tester) =>
    tester.widget<FrostedPageBar>(find.byType(FrostedPageBar)).titleCollapsed;

Future<void> _pumpList(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FrostedBarPage(
        title: '标题',
        child: ListView.builder(
          itemCount: 80,
          itemBuilder: (context, i) => SizedBox(height: 80, child: Text('$i')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('顶栏悬浮在内容之上，内容自己垫首屏占位', (tester) async {
    await _pumpList(tester);

    expect(find.byType(FrostedPageBar), findsOneWidget);
    // 顶栏是悬浮层：内容铺满整页，滚动时才能从毛玻璃下面穿过
    expect(
      tester.getRect(find.byType(ListView)).top,
      lessThan(tester.getRect(find.byType(FrostedPageBar)).bottom),
    );
  });

  testWidgets('默认常驻：滚动时标题行不收起', (tester) async {
    await _pumpList(tester);
    expect(_collapsed(tester), isFalse);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_collapsed(tester), isFalse);
  });

  testWidgets('显式打开 collapseOnScroll 才会收起，往上滚放回', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FrostedBarPage(
          title: '标题',
          collapseOnScroll: true,
          child: ListView.builder(
            itemCount: 80,
            itemBuilder: (context, i) =>
                SizedBox(height: 80, child: Text('$i')),
          ),
        ),
      ),
    );
    expect(_collapsed(tester), isFalse);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_collapsed(tester), isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(_collapsed(tester), isFalse);
  });

  testWidgets('关掉 collapseOnScroll 就退化成常驻单行顶栏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FrostedBarPage(
          title: '标题',
          collapseOnScroll: false,
          child: ListView.builder(
            itemCount: 80,
            itemBuilder: (context, i) =>
                SizedBox(height: 80, child: Text('$i')),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_collapsed(tester), isFalse);
  });
}
