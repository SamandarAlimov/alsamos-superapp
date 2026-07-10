import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import 'admin_online_users_map.dart';

/// Ported from src/components/admin/AdminAnalyticsDashboard.tsx.
class AdminAnalyticsDashboard extends StatefulWidget {
  const AdminAnalyticsDashboard({super.key});

  @override
  State<AdminAnalyticsDashboard> createState() =>
      _AdminAnalyticsDashboardState();
}

class _AdminAnalyticsDashboardState extends State<AdminAnalyticsDashboard> {
  final AdminRepository _repo = AdminRepository();
  AdminAnalyticsSnapshot _data = const AdminAnalyticsSnapshot();
  bool _loading = true;

  static const _dayNames = [
    'Yakshanba', 'Dushanba', 'Seshanba', 'Chorshanba',
    'Payshanba', 'Juma', 'Shanba',
  ];

  static const Map<String, String> _pageNames = {
    '/home': 'Bosh sahifa',
    '/messages': 'Xabarlar',
    '/profile': 'Profil',
    '/videos': 'Videolar',
    '/discovery': 'Kashfiyot',
    '/search': 'Qidiruv',
    '/marketplace': "Do'kon",
    '/map': 'Xarita',
    '/create': 'Yaratish',
    '/notifications': 'Bildirishnomalar',
    '/settings': 'Sozlamalar',
    '/activity': 'Faollik',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final snap = await _repo.fetchAnalytics();
      if (!mounted) return;
      setState(() {
        _data = snap;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final s = _data.stats;

    if (_loading && _data.dau.isEmpty) {
      return const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            Icon(LucideIcons.barChart3, color: primary, size: 22),
            const SizedBox(width: 8),
            const Text('Platform Analitikasi',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              tooltip: 'Yangilash',
              onPressed: _refresh,
              icon: Icon(LucideIcons.refreshCw,
                  size: 18, color: c.mutedForeground),
            ),
          ]),
          const SizedBox(height: 12),

          // Primary KPI row
          _kpiGrid(c, primary, [
            _Kpi(
              icon: LucideIcons.users,
              label: 'Jami foydalanuvchilar',
              value: _fmt(s.totalUsers),
              hint: '+${_fmt(s.newUsers7d)} (7 kun)',
              color: primary,
            ),
            _Kpi(
              icon: LucideIcons.userCheck,
              label: 'Hozir onlayn',
              value: _fmt(s.onlineUsers),
              hint: 'Real-time',
              color: const Color(0xFF22C55E),
              pulse: true,
            ),
            _Kpi(
              icon: LucideIcons.trendingUp,
              label: '24 soatda yangi',
              value: _fmt(s.newUsers24h),
              hint: '+${_fmt(s.newUsers30d)} (30 kun)',
              color: const Color(0xFF3B82F6),
            ),
            _Kpi(
              icon: LucideIcons.userCheck,
              label: 'Tasdiqlangan',
              value: _fmt(s.verifiedUsers),
              hint: s.totalUsers == 0
                  ? '0%'
                  : '${((s.verifiedUsers / s.totalUsers) * 100).toStringAsFixed(1)}%',
              color: const Color(0xFFF59E0B),
            ),
          ]),

          const SizedBox(height: 12),

          // Secondary KPI row
          _kpiGrid(c, primary, [
            _Kpi(
              icon: LucideIcons.fileText,
              label: 'Jami postlar',
              value: _fmt(s.totalPosts),
              hint: '+${_fmt(s.posts24h)} (24s)',
              color: const Color(0xFF8B5CF6),
              hintColor: const Color(0xFF22C55E),
            ),
            _Kpi(
              icon: LucideIcons.messageSquare,
              label: 'Jami xabarlar',
              value: _fmt(s.totalMessages),
              hint: '+${_fmt(s.messages24h)} (24s)',
              color: const Color(0xFF0EA5E9),
              hintColor: const Color(0xFF22C55E),
            ),
            _Kpi(
              icon: LucideIcons.users,
              label: '7 kunlik yangi',
              value: _fmt(s.newUsers7d),
              hint: 'Haftalik',
              color: const Color(0xFFEC4899),
            ),
            _Kpi(
              icon: LucideIcons.users,
              label: '30 kunlik yangi',
              value: _fmt(s.newUsers30d),
              hint: 'Oylik',
              color: const Color(0xFFA855F7),
            ),
          ]),

          const SizedBox(height: 18),
          const AdminOnlineUsersMap(),
          const SizedBox(height: 18),

          _chartCard(
            c: c,
            icon: LucideIcons.trendingUp,
            title: 'Kunlik faol foydalanuvchilar (30 kun)',
            child: SizedBox(height: 220, child: _dauChart(c, primary)),
          ),
          const SizedBox(height: 14),
          _chartCard(
            c: c,
            icon: LucideIcons.clock,
            title: 'Soatlik faollik (7 kun)',
            child: SizedBox(height: 200, child: _hourlyChart(c, primary)),
          ),
          const SizedBox(height: 14),
          _chartCard(
            c: c,
            icon: LucideIcons.calendar,
            title: 'Haftalik faollik namunasi',
            child: SizedBox(height: 200, child: _weeklyChart(c, primary)),
          ),
          const SizedBox(height: 14),
          _chartCard(
            c: c,
            icon: LucideIcons.fileText,
            title: "Eng ko'p foydalanilgan sahifalar",
            child: _pageProgressList(c, primary),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, box) {
            final wide = box.maxWidth >= 720;
            final country = _chartCard(
              c: c,
              icon: LucideIcons.globe,
              title: "Davlatlar bo'yicha",
              child:
                  SizedBox(height: 240, child: _pie(c, primary, _topCountries())),
            );
            final age = _chartCard(
              c: c,
              icon: LucideIcons.users,
              title: 'Yosh bo\'yicha taqsimot',
              child: SizedBox(height: 240, child: _pie(c, primary, _agesAsPie())),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: country),
                  const SizedBox(width: 12),
                  Expanded(child: age),
                ],
              );
            }
            return Column(children: [country, const SizedBox(height: 14), age]);
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // KPI grid
  // ─────────────────────────────────────────────────────────────
  Widget _kpiGrid(AlsamosColors c, Color primary, List<_Kpi> items) {
    return LayoutBuilder(builder: (ctx, box) {
      final cols = box.maxWidth >= 900
          ? 4
          : box.maxWidth >= 560
              ? 2
              : 2;
      const gap = 10.0;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: items
            .map((it) => SizedBox(
                  width: w,
                  child: _kpiCard(c, primary, it),
                ))
            .toList(),
      );
    });
  }

  Widget _kpiCard(AlsamosColors c, Color primary, _Kpi it) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(it.icon, size: 16, color: it.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: c.mutedForeground),
              ),
            ),
            if (it.pulse)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: it.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: it.color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(it.value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            it.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: it.hintColor ?? c.mutedForeground),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(
      {required AlsamosColors c,
      required IconData icon,
      required String title,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: c.foreground),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Charts
  // ─────────────────────────────────────────────────────────────

  Widget _dauChart(AlsamosColors c, Color primary) {
    final dau = _data.dau;
    if (dau.isEmpty) return _emptyChart(c);
    final spots = <FlSpot>[
      for (var i = 0; i < dau.length; i++)
        FlSpot(i.toDouble(), dau[i].dau.toDouble()),
    ];
    final maxY = (dau.map((e) => e.dau).fold<int>(0, (a, b) => a > b ? a : b))
        .toDouble();
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: c.border,
            strokeWidth: 0.5,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                _fmt(v.toInt()),
                style: TextStyle(
                    fontSize: 10, color: c.mutedForeground),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (dau.length / 6).clamp(1, 30).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= dau.length) return const SizedBox.shrink();
                final d = dau[i].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(DateFormat('d/M').format(d),
                      style: TextStyle(
                          fontSize: 10, color: c.mutedForeground)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.card,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${_fmt(s.y.toInt())} DAU',
                      TextStyle(
                          color: c.foreground,
                          fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: primary,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  primary.withValues(alpha: 0.30),
                  primary.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hourlyChart(AlsamosColors c, Color primary) {
    final list = _data.hourly;
    if (list.isEmpty) return _emptyChart(c);
    final maxY =
        list.map((e) => e.activityCount).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: (maxY == 0 ? 1 : maxY * 1.15).toDouble(),
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: c.border,
            strokeWidth: 0.5,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                _fmt(v.toInt()),
                style: TextStyle(
                    fontSize: 10, color: c.mutedForeground),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 2,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${v.toInt()}h',
                  style: TextStyle(
                      fontSize: 10, color: c.mutedForeground),
                ),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => c.card,
            getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
              '${list[gi].hour}h: ${_fmt(list[gi].activityCount)}',
              TextStyle(
                  color: c.foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < list.length; i++)
            BarChartGroupData(
              x: list[i].hour,
              barRods: [
                BarChartRodData(
                  toY: list[i].activityCount.toDouble(),
                  width: 6,
                  color: primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _weeklyChart(AlsamosColors c, Color primary) {
    final list = _data.weekly;
    if (list.isEmpty) return _emptyChart(c);
    final maxY =
        list.map((e) => e.activityCount).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: (maxY == 0 ? 1 : maxY * 1.15).toDouble(),
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: c.border,
            strokeWidth: 0.5,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(_fmt(v.toInt()),
                  style:
                      TextStyle(fontSize: 10, color: c.mutedForeground)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i > 6) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _dayNames[i].substring(0, 3),
                    style: TextStyle(
                        fontSize: 10, color: c.mutedForeground),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => c.card,
            getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
              '${_dayNames[list[gi].dayOfWeek]}: ${_fmt(list[gi].activityCount)}',
              TextStyle(
                  color: c.foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < list.length; i++)
            BarChartGroupData(
              x: list[i].dayOfWeek,
              barRods: [
                BarChartRodData(
                  toY: list[i].activityCount.toDouble(),
                  width: 18,
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pageProgressList(AlsamosColors c, Color primary) {
    final pages = [..._data.pages]
      ..sort((a, b) => b.visitCount.compareTo(a.visitCount));
    if (pages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text("Ma'lumotlar yo'q",
              style: TextStyle(color: c.mutedForeground)),
        ),
      );
    }
    final top = pages.take(10).toList();
    final maxV = top.first.visitCount.toDouble();
    return Column(
      children: [
        for (final p in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      _pageNames[p.page] ?? p.page,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('${_fmt(p.visitCount)} ko\'rishlar',
                      style: TextStyle(
                          fontSize: 11, color: c.mutedForeground)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:
                        maxV == 0 ? 0 : p.visitCount.toDouble() / maxV,
                    minHeight: 6,
                    backgroundColor: c.muted,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt(p.uniqueUsers)} unikal • o\'rt. ${_fmt(p.avgDuration)}s',
                  style: TextStyle(
                      fontSize: 10, color: c.mutedForeground),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<({String label, int value, Color color})> _topCountries() {
    final list = [..._data.countries]
      ..sort((a, b) => b.userCount.compareTo(a.userCount));
    final palette = _palette();
    return [
      for (var i = 0; i < list.take(8).length; i++)
        (
          label: list[i].country,
          value: list[i].userCount,
          color: palette[i % palette.length],
        ),
    ];
  }

  List<({String label, int value, Color color})> _agesAsPie() {
    final palette = _palette();
    return [
      for (var i = 0; i < _data.ages.length; i++)
        (
          label: _data.ages[i].ageGroup,
          value: _data.ages[i].userCount,
          color: palette[i % palette.length],
        ),
    ];
  }

  List<Color> _palette() {
    final primary = Theme.of(context).colorScheme.primary;
    return [
      primary,
      const Color(0xFF22C55E),
      const Color(0xFF3B82F6),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
      const Color(0xFF0EA5E9),
      const Color(0xFFEF4444),
    ];
  }

  Widget _pie(AlsamosColors c, Color primary,
      List<({String label, int value, Color color})> items) {
    if (items.isEmpty || items.every((e) => e.value == 0)) {
      return _emptyChart(c);
    }
    final total = items.fold<int>(0, (a, b) => a + b.value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                for (final it in items)
                  PieChartSectionData(
                    value: it.value.toDouble(),
                    color: it.color,
                    radius: 50,
                    title: total == 0
                        ? ''
                        : '${((it.value / total) * 100).toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: it.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        it.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Text(_fmt(it.value),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.mutedForeground)),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyChart(AlsamosColors c) {
    return Center(
      child: Text("Ma'lumotlar yo'q",
          style: TextStyle(color: c.mutedForeground, fontSize: 12)),
    );
  }

  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final left = s.length - i - 1;
      if (left > 0 && left % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }
}

class _Kpi {
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color color;
  final Color? hintColor;
  final bool pulse;
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    this.hintColor,
    this.pulse = false,
  });
}
