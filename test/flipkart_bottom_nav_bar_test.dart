import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riqma_pro/widgets/flipkart_bottom_nav_bar.dart';

void main() {
  testWidgets('FlipkartBottomNavBar displays items, taps, and drag interactions correctly', (WidgetTester tester) async {
    int selectedIndex = 0;

    final items = const [
      FlipkartNavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      FlipkartNavItem(
        icon: Icons.verified_user_outlined,
        activeIcon: Icons.verified_user_rounded,
        label: 'Audit',
      ),
      FlipkartNavItem(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart_rounded,
        label: 'Statistics',
      ),
      FlipkartNavItem(
        icon: Icons.calendar_month_outlined,
        activeIcon: Icons.calendar_month_rounded,
        label: 'Planning',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) {
              return FlipkartBottomNavBar(
                items: items,
                currentIndex: selectedIndex,
                onTap: (newIndex) {
                  setState(() {
                    selectedIndex = newIndex;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    // Verify all 4 tab labels are present
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Audit'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Planning'), findsOneWidget);

    // Tap on the 'Statistics' tab (index 2)
    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();

    // Verify selected index updated
    expect(selectedIndex, 2);

    // Test drag interaction from Statistics (index 2) to Planning (index 3)
    final statsCenter = tester.getCenter(find.text('Statistics'));
    await tester.dragFrom(statsCenter, const Offset(200, 0));
    await tester.pumpAndSettle();

    // Verify selected index updated to Planning (index 3)
    expect(selectedIndex, 3);

    // Drag to the left from Planning all the way to Dashboard (index 0)
    final planningCenter = tester.getCenter(find.text('Planning'));
    await tester.dragFrom(planningCenter, const Offset(-600, 0));
    await tester.pumpAndSettle();

    // Verify selected index updated to Dashboard (index 0)
    expect(selectedIndex, 0);
  });
}
