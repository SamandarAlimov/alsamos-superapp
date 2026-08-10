// Location Timeline View - Calendar + Daily summaries + Statistics
// NOTE: Requires 'table_calendar: ^3.1.2' package - run 'flutter pub get'
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:table_calendar/table_calendar.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/location_history_service.dart';

final _historyServiceProvider = Provider((ref) => LocationHistoryService());

final _selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final _timeRangeProvider =
    StateProvider<HistoryTimeRange>((ref) => HistoryTimeRange.last30Days);

final _dailySummariesProvider = FutureProvider.family<
    Map<DateTime, DayMovementSummary>,
    (DateTime start, DateTime end)>((ref, range) async {
  final service = ref.read(_historyServiceProvider);
  return await service.fetchDailySummaries(
    startDate: range.$1,
    endDate: range.$2,
  );
});

final _statisticsProvider =
    FutureProvider.family<TravelStatistics, HistoryTimeRange>((ref, range) async {
  final service = ref.read(_historyServiceProvider);
  return await service.getStatistics(range: range);
});

/// Location Timeline View with Calendar and Statistics
class LocationTimelineView extends ConsumerStatefulWidget {
  final Function(DateTime date)? onDateSelected;
  final Function(DayMovementSummary summary)? onDayTapped;

  const LocationTimelineView({
    super.key,
    this.onDateSelected,
    this.onDayTapped,
  });

  @override
  ConsumerState<LocationTimelineView> createState() =>
      _LocationTimelineViewState();
}

class _LocationTimelineViewState extends ConsumerState<LocationTimelineView> {
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final selectedDate = ref.watch(_selectedDateProvider);
    final timeRange = ref.watch(_timeRangeProvider);

    // Get calendar range for current view
    final firstDay = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDay =
        DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);

    final summariesAsync =
        ref.watch(_dailySummariesProvider((firstDay, lastDay)));
    final statsAsync = ref.watch(_statisticsProvider(timeRange));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Time Range Selector
        _TimeRangeSelector(
          currentRange: timeRange,
          onRangeChanged: (range) {
            ref.read(_timeRangeProvider.notifier).state = range;
          },
          c: c,
        ),

        const SizedBox(height: 20),

        // Statistics Cards
        statsAsync.when(
          data: (stats) => _StatisticsSection(stats: stats, c: c),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Text('Error: $e'),
        ),

        const SizedBox(height: 24),

        // Calendar
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(16),
          child: summariesAsync.when(
            data: (summaries) => TableCalendar(
              firstDay: DateTime(2020),
              lastDay: DateTime.now(),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(selectedDate, day),
              calendarFormat: _calendarFormat,
              onDaySelected: (selected, focused) {
                ref.read(_selectedDateProvider.notifier).state = selected;
                setState(() => _focusedDay = focused);
                widget.onDateSelected?.call(selected);

                // Show day summary if available
                final normalizedDate = DateTime(selected.year, selected.month, selected.day);
                if (summaries.containsKey(normalizedDate)) {
                  widget.onDayTapped?.call(summaries[normalizedDate]!);
                }
              },
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              onPageChanged: (focused) {
                setState(() => _focusedDay = focused);
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  final normalizedDay = DateTime(day.year, day.month, day.day);
                  final summary = summaries[normalizedDay];
                  if (summary == null || summary.locationCount == 0) {
                    return null;
                  }

                  // Show indicator with distance
                  return Positioned(
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        summary.totalDistanceKm.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: TextStyle(color: c.mutedForeground),
                outsideDaysVisible: false,
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: true,
                titleTextStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.foreground,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: c.foreground),
                weekendStyle: TextStyle(color: c.mutedForeground),
              ),
            ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          ),
        ),

        const SizedBox(height: 20),

        // Selected Day Details
        summariesAsync.when(
          data: (summaries) {
            final normalizedDate = DateTime(
                selectedDate.year, selectedDate.month, selectedDate.day);
            final summary = summaries[normalizedDate];

            if (summary == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(LucideIcons.calendar,
                          size: 48, color: c.mutedForeground),
                      const SizedBox(height: 12),
                      Text(
                        'Bu kun uchun ma\'lumot yo\'q',
                        style: TextStyle(color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              );
            }

            return _DaySummaryCard(summary: summary, c: c);
          },
          loading: () => const SizedBox.shrink(),
          error: (e, s) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _TimeRangeSelector extends StatelessWidget {
  final HistoryTimeRange currentRange;
  final Function(HistoryTimeRange) onRangeChanged;
  final AlsamosColors c;

  const _TimeRangeSelector({
    required this.currentRange,
    required this.onRangeChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _RangeChip(
            label: '7 kun',
            range: HistoryTimeRange.last7Days,
            currentRange: currentRange,
            onTap: () => onRangeChanged(HistoryTimeRange.last7Days),
            c: c,
          ),
          _RangeChip(
            label: '30 kun',
            range: HistoryTimeRange.last30Days,
            currentRange: currentRange,
            onTap: () => onRangeChanged(HistoryTimeRange.last30Days),
            c: c,
          ),
          _RangeChip(
            label: '3 oy',
            range: HistoryTimeRange.last3Months,
            currentRange: currentRange,
            onTap: () => onRangeChanged(HistoryTimeRange.last3Months),
            c: c,
          ),
          _RangeChip(
            label: '1 yil',
            range: HistoryTimeRange.thisYear,
            currentRange: currentRange,
            onTap: () => onRangeChanged(HistoryTimeRange.thisYear),
            c: c,
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final HistoryTimeRange range;
  final HistoryTimeRange currentRange;
  final VoidCallback onTap;
  final AlsamosColors c;

  const _RangeChip({
    required this.label,
    required this.range,
    required this.currentRange,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = range == currentRange;
    final primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? c.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: primary) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? primary : c.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatisticsSection extends StatelessWidget {
  final TravelStatistics stats;
  final AlsamosColors c;

  const _StatisticsSection({required this.stats, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: LucideIcons.route,
                label: 'Jami masofa',
                value: '${stats.totalDistanceKm.toStringAsFixed(1)} km',
                color: const Color(0xFF3B82F6),
                c: c,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: LucideIcons.calendar,
                label: 'Faol kunlar',
                value: '${stats.activeDays}/${stats.totalDays}',
                color: const Color(0xFF10B981),
                c: c,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: LucideIcons.trendingUp,
                label: "O'rtacha/kun",
                value: '${stats.avgDailyDistanceKm.toStringAsFixed(1)} km',
                color: const Color(0xFFF59E0B),
                c: c,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: LucideIcons.mapPin,
                label: 'Joylar',
                value: '${stats.totalPlacesVisited}',
                color: const Color(0xFF8B5CF6),
                c: c,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final AlsamosColors c;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: c.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  final DayMovementSummary summary;
  final AlsamosColors c;

  const _DaySummaryCard({required this.summary, required this.c});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendar, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                _formatDate(summary.date),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailRow(
            icon: LucideIcons.route,
            label: 'Masofa',
            value: '${summary.totalDistanceKm.toStringAsFixed(2)} km',
            c: c,
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: LucideIcons.mapPin,
            label: 'Lokatsiyalar',
            value: '${summary.locationCount} ta',
            c: c,
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: LucideIcons.home,
            label: 'Tashrif buyurilgan joylar',
            value: '${summary.placesVisited} ta',
            c: c,
          ),
          if (summary.timeSpentMinutes > 0) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: LucideIcons.clock,
              label: 'Faollik vaqti',
              value: _formatDuration(summary.timeSpentMinutes),
              c: c,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final weekdays = [
      'Dushanba',
      'Seshanba',
      'Chorshanba',
      'Payshanba',
      'Juma',
      'Shanba',
      'Yakshanba'
    ];
    final months = [
      'Yanvar',
      'Fevral',
      'Mart',
      'Aprel',
      'May',
      'Iyun',
      'Iyul',
      'Avgust',
      'Sentabr',
      'Oktabr',
      'Noyabr',
      'Dekabr'
    ];

    return '${date.day} ${months[date.month - 1]}, ${weekdays[date.weekday - 1]}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes daqiqa';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours soat';
    return '$hours soat $mins daqiqa';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AlsamosColors c;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: c.mutedForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: c.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.foreground,
          ),
        ),
      ],
    );
  }
}
