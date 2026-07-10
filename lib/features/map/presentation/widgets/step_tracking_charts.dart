import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/map_models.dart';
import '../providers/map_provider.dart';

enum _Period { week, month, year }

extension on _Period {
  int get days => this == _Period.week ? 7 : (this == _Period.month ? 30 : 365);
  String get label => this == _Period.week ? 'Hafta' : (this == _Period.month ? 'Oy' : 'Yil');
}

class StepTrackingCharts extends ConsumerStatefulWidget {
  final int stepsToday;
  final int dailyGoal;
  const StepTrackingCharts({super.key, required this.stepsToday, this.dailyGoal = 10000});

  @override
  ConsumerState<StepTrackingCharts> createState() => _StepTrackingChartsState();
}

class _StepTrackingChartsState extends ConsumerState<StepTrackingCharts> {
  _Period _period = _Period.week;

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final stepProgress = (widget.stepsToday / widget.dailyGoal).clamp(0.0, 1.0);
    final caloriesBurned = (widget.stepsToday * 0.04).round();
    final distanceKm = (widget.stepsToday * 0.762 / 1000).toStringAsFixed(2);

    final asyncSteps = ref.watch(stepHistoryProvider(_period.days));
    final chartData = asyncSteps.value ?? const <StepDataPoint>[];
    final streak = _calcStreak(chartData, widget.dailyGoal);

    return Column(
      children: [
        // Today's stats card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary.withValues(alpha: 0.10), primary.withValues(alpha: 0.04)]),
            border: Border.all(color: primary.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: primary.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: Icon(LucideIcons.footprints, size: 20, color: primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bugungi qadamlar', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
                        Text(_fmt(widget.stepsToday), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.foreground)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: stepProgress >= 1 ? primary : c.muted, borderRadius: BorderRadius.circular(6)),
                        child: Text(stepProgress >= 1 ? 'Maqsadga yetildi!' : '${(stepProgress * 100).round()}%',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: stepProgress >= 1 ? Colors.white : c.foreground)),
                      ),
                      const SizedBox(height: 4),
                      Text('${_fmt(widget.dailyGoal)} maqsad', style: TextStyle(fontSize: 11, color: c.mutedForeground)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: stepProgress, minHeight: 10, backgroundColor: c.muted, valueColor: AlwaysStoppedAnimation(primary)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _MiniStat(icon: LucideIcons.flame, color: const Color(0xFFF97316), label: 'Kaloriya', value: '$caloriesBurned')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat(icon: LucideIcons.target, color: const Color(0xFF22C55E), label: 'Masofa', value: '$distanceKm km')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat(icon: LucideIcons.award, color: const Color(0xFFEAB308), label: 'Streak', value: '$streak kun')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Period chart card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.card, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.trendingUp, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Text('Statistika', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in _Period.values)
                          GestureDetector(
                            onTap: () => setState(() => _period = p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _period == p ? c.background : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                              child: Text(p.label, style: TextStyle(fontSize: 11, color: c.foreground)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: chartData.isEmpty
                    ? Center(child: Text('Maʼlumot yoʻq', style: TextStyle(color: c.mutedForeground, fontSize: 12)))
                    : (_period == _Period.week ? _buildBarChart(chartData, primary, c) : _buildAreaChart(chartData, primary, c)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart(List<StepDataPoint> data, Color primary, AlsamosColors c) {
    final maxV = data.map((d) => d.steps).fold<int>(0, (a, b) => a > b ? a : b).toDouble();
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxV * 1.2 + 1,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxV / 4 + 1, getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 1, dashArray: const [3, 3])),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, _) => Text(_compactNumber(value.toInt()), style: TextStyle(fontSize: 9, color: c.mutedForeground)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_dayLabel(data[i].date), style: TextStyle(fontSize: 9, color: c.mutedForeground)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: data[i].steps.toDouble(), color: primary, width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ]),
        ],
      ),
    );
  }

  Widget _buildAreaChart(List<StepDataPoint> data, Color primary, AlsamosColors c) {
    final spots = <FlSpot>[for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].steps.toDouble())];
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 1, dashArray: const [3, 3])),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, _) => Text(_compactNumber(value.toInt()), style: TextStyle(fontSize: 9, color: c.mutedForeground)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (data.length / 6).clamp(1, 60).toDouble(),
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_monthDayLabel(data[i].date), style: TextStyle(fontSize: 9, color: c.mutedForeground)));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: primary.withValues(alpha: 0.2)),
          ),
        ],
      ),
    );
  }

  int _calcStreak(List<StepDataPoint> data, int goal) {
    var s = 0;
    for (var i = data.length - 1; i >= 0; i--) {
      if (data[i].steps >= goal) {
        s++;
      } else {
        break;
      }
    }
    return s;
  }

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _compactNumber(int v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    return '$v';
  }

  String _dayLabel(String iso) {
    try {
      final d = DateTime.parse(iso);
      const days = ['Du', 'Se', 'Cho', 'Pa', 'Ju', 'Sha', 'Yak'];
      return days[(d.weekday - 1) % 7];
    } catch (_) {
      return '';
    }
  }

  String _monthDayLabel(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}';
    } catch (_) {
      return '';
    }
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _MiniStat({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: c.background.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: c.mutedForeground)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.foreground)),
        ],
      ),
    );
  }
}
