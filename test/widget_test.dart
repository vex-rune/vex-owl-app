// vex owl 的最小冒烟测试。
//
// 验证 HomePage 能渲染并显示 'vex owl' 标题。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:owl/presentation/pages/home_page.dart';

void main() {
  testWidgets('home page renders with app bar title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomePage())),
    );

    // AppBar 标题
    expect(find.text('vex owl'), findsOneWidget);
  });
}
