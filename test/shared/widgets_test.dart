import 'package:e_labay/core/theme/app_colors.dart';
import 'package:e_labay/core/theme/app_theme.dart';
import 'package:e_labay/core/utils/formatters.dart';
import 'package:e_labay/models/enums.dart';
import 'package:e_labay/shared/widgets/initials_avatar.dart';
import 'package:e_labay/shared/widgets/state_views.dart';
import 'package:e_labay/shared/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  testWidgets('StatusChip shows the status label, or Overdue', (tester) async {
    await tester.pumpWidget(wrap(const StatusChip(status: ScheduleStatus.rescheduled)));
    expect(find.text('Rescheduled'), findsOneWidget);
    await tester.pumpWidget(wrap(const StatusChip(status: ScheduleStatus.scheduled, overdue: true)));
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('EmptyState renders title, message and action', (tester) async {
    await tester.pumpWidget(wrap(EmptyState(
      icon: Icons.inbox,
      title: 'Nothing here',
      message: 'Try again later',
      action: TextButton(onPressed: () {}, child: const Text('Retry')),
    )));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Try again later'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  test('RateChip colours by performance band', () {
    expect(RateChip.colorFor(0.9), AppColors.success);
    expect(RateChip.colorFor(0.6), AppColors.warning);
    expect(RateChip.colorFor(0.2), AppColors.danger);
    expect(RateChip.colorFor(null), AppColors.textMuted);
  });

  test('initials and formatters', () {
    expect(InitialsAvatar.initialsOf('College of Engineering'), 'CE');
    expect(InitialsAvatar.initialsOf('registrar'), 'R');
    expect(InitialsAvatar.initialsOf('  '), '?');
    expect(Fmt.ordinal(1), '1st');
    expect(Fmt.ordinal(12), '12th');
    expect(Fmt.ordinal(23), '23rd');
    expect(Fmt.percent(0.756), '76%');
    expect(Fmt.percent(null), '—');
    expect(Fmt.points(30, signed: true), '+30 pts');
    expect(Fmt.timeOfDayToStorage(const TimeOfDay(hour: 7, minute: 5)), '07:05');
  });
}
