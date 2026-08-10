// Ported 1:1 from web src/components/marketplace/SellerDashboard.tsx.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../providers/marketplace_provider.dart';
import 'create_product_dialog.dart';
import 'orders_view.dart';

class SellerDashboardView extends ConsumerWidget {
  const SellerDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final dash = ref.watch(sellerDashboardProvider);
    final range = ref.watch(dashboardDateRangeProvider);
    final me = ref.watch(mySellerProvider).asData?.value;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sellerDashboardProvider);
        ref.invalidate(sellerProductsProvider);
        await ref.read(sellerDashboardProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                brand.withValues(alpha: 0.18),
                brand.withValues(alpha: 0.05),
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: brand.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brand, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.store,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me?.businessName ?? 'Mening doʼkonim',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text(
                        '${(me?.businessType ?? "business").toUpperCase()} · ${me?.totalSales ?? 0} sotuv',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brand,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final ok = await CreateProductSheet.show(context);
                  if (ok == true) ref.invalidate(sellerProductsProvider);
                },
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Qoʼshish',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // Range chips
          Row(children: [
            for (final r in [7, 30, 90])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$r kun'),
                  selected: range == r,
                  selectedColor: brand,
                  labelStyle: TextStyle(
                      color: range == r ? Colors.white : c.foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  backgroundColor: c.card,
                  side: BorderSide(color: c.border.withValues(alpha: 0.4)),
                  onSelected: (_) =>
                      ref.read(dashboardDateRangeProvider.notifier).state = r,
                ),
              ),
          ]),
          const SizedBox(height: 12),
          dash.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text('$e', style: TextStyle(color: c.mutedForeground)),
            ),
            data: (data) {
              final s = data.stats;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    _kpi(c, brand, LucideIcons.dollarSign, 'Daromad',
                        '\$${s.totalRevenue.toStringAsFixed(0)}',
                        const Color(0xFF22C55E)),
                    _kpi(c, brand, LucideIcons.shoppingBag, 'Buyurtmalar',
                        '${s.totalOrders}', brand),
                    _kpi(c, brand, LucideIcons.package, 'Mahsulotlar',
                        '${s.totalProducts}', const Color(0xFF3B82F6)),
                    _kpi(c, brand, LucideIcons.eye, 'Koʼrishlar',
                        _short(s.totalViews), const Color(0xFF8B5CF6)),
                  ],
                ),
                const SizedBox(height: 16),
                _chartCard(
                  c,
                  brand,
                  title: 'Daromad',
                  subtitle: '\$${s.totalRevenue.toStringAsFixed(0)} jami',
                  height: 220,
                  child: _revenueChart(c, brand, data.revenue),
                ),
                const SizedBox(height: 12),
                _chartCard(
                  c,
                  brand,
                  title: 'Buyurtmalar trend',
                  subtitle: '${s.totalOrders} jami',
                  height: 220,
                  child: _ordersChart(c, brand, data.revenue),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _miniStat(c, 'Oʼrtacha buyurtma',
                          '\$${s.averageOrderValue.toStringAsFixed(0)}')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _miniStat(c, 'Konversiya',
                          '${s.conversionRate.toStringAsFixed(1)}%')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _miniStat(c, 'Kutilmoqda', '${s.pendingOrders}',
                          color: const Color(0xFFF59E0B))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _miniStat(c, 'Yakunlangan', '${s.completedOrders}',
                          color: const Color(0xFF22C55E))),
                ]),
                const SizedBox(height: 18),
                Text('Soʼnggi buyurtmalar',
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (data.orders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text('Buyurtmalar yoʼq',
                          style: TextStyle(color: c.mutedForeground)),
                    ),
                  )
                else
                  ...data.orders.take(5).map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: c.border.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('#${o.orderNumber}',
                                      style: TextStyle(
                                          color: c.foreground,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  Text(o.status,
                                      style: TextStyle(
                                          color: c.mutedForeground, fontSize: 11)),
                                ],
                              ),
                            ),
                            Text('\$${o.total.toStringAsFixed(2)}',
                                style: TextStyle(
                                    color: brand,
                                    fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      )),
              ]);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kpi(AlsamosColors c, Color brand, IconData icon, String label,
      String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accent, size: 16),
          ),
          const Spacer(), // Natural spacing instead of spaceBetween
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.mutedForeground, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.foreground,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _chartCard(AlsamosColors c, Color brand,
      {required String title,
      required String subtitle,
      required Widget child,
      double height = 200}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.mutedForeground, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }

  Widget _revenueChart(AlsamosColors c, Color brand, List<dynamic> series) {
    if (series.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.trendingUp, color: brand, size: 24),
            ),
            const SizedBox(height: 12),
            Text('Hali savdo yoʼq',
                style: TextStyle(
                    color: c.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Mahsulotlaringizni ulashing va birinchi buyurtmani oling',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mutedForeground, fontSize: 12)),
          ],
        ),
      );
    }
    final spots = <FlSpot>[
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), (series[i].revenue as double))
    ];
    final maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.border.withValues(alpha: 0.3), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (series.length / 4).clamp(1, 999).toDouble(),
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= series.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(series[i].dateLabel as String,
                      style:
                          TextStyle(color: c.mutedForeground, fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.15,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: brand,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  brand.withValues(alpha: 0.35),
                  brand.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersChart(AlsamosColors c, Color brand, List<dynamic> series) {
    if (series.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.shoppingBag, color: brand, size: 24),
            ),
            const SizedBox(height: 12),
            Text('Hali buyurtma yoʼq',
                style: TextStyle(
                    color: c.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Buyurtmalar kelishi bilan bu yerda koʼrinadi',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mutedForeground, fontSize: 12)),
          ],
        ),
      );
    }
    final maxY = series.fold<int>(0, (m, e) => (e.orders as int) > m ? e.orders as int : m);
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.border.withValues(alpha: 0.3), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (series.length / 4).clamp(1, 999).toDouble(),
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= series.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(series[i].dateLabel as String,
                      style:
                          TextStyle(color: c.mutedForeground, fontSize: 10)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        maxY: maxY <= 0 ? 1 : (maxY * 1.2).toDouble(),
        barGroups: [
          for (var i = 0; i < series.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: (series[i].orders as int).toDouble(),
                color: brand,
                width: 7,
                borderRadius: BorderRadius.circular(2),
              ),
            ])
        ],
      ),
    );
  }

  Widget _miniStat(AlsamosColors c, String label, String value,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.mutedForeground, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color ?? c.foreground,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

String _short(int v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '$v';
}

// Allow re-using OrdersView from other files importing this widget.
typedef SellerOrdersTabBuilder = OrdersView;
