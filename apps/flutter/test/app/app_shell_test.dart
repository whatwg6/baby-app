import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows three destinations and empty timeline', (tester) async {
    await tester.pumpWidget(
      BabyTimelineApp(router: createRouter(hasBaby: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('时间轴'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
    expect(find.text('宝宝'), findsOneWidget);
    expect(find.text('还没有成长记录'), findsOneWidget);
    expect(find.text('记录第一个瞬间'), findsOneWidget);
  });

  testWidgets('redirects the legacy root route to the timeline', (
    tester,
  ) async {
    final router = createRouter(hasBaby: true);
    addTearDown(router.dispose);
    await tester.pumpWidget(BabyTimelineApp(router: router));
    await tester.pumpAndSettle();

    router.go('/');
    await tester.pumpAndSettle();

    expect(find.text('还没有成长记录'), findsOneWidget);
  });
}
