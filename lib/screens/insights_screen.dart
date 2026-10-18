import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/database_helper.dart';

// Stable color per category so the pie chart and its legend always agree,
// and colors stay consistent across app launches. Categories not listed
// here (shouldn't happen given Category.all, but just in case) fall back
// to grey.
const Map<String, Color> _categoryColors = {
  'Food & Dining': Color(0xFFEF5350),
  'Groceries': Color(0xFF66BB6A),
  'Shopping': Color(0xFF42A5F5),
  'Transport': Color(0xFFFFA726),
  'Bills & Utilities': Color(0xFFAB47BC),
  'Entertainment': Color(0xFFEC407A),
  'Health': Color(0xFF26A69A),
  'Investment': Color(0xFF7E57C2),
  'Other': Color(0xFF78909C),
  'Transfer': Color(0xFFBDBDBD),
};

Color _colorFor(String category) => _categoryColors[category] ?? Colors.grey;

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool loading = true;

  List<Map<String, dynamic>> categoryBreakdown = [];
  List<Map<String, dynamic>> monthlyTotals = [];
  double currentMonthTotal = 0;
  double? projectedMonthTotal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final breakdown = await DatabaseHelper().getCategoryBreakdown(
      start: monthStart,
      end: monthEnd,
    );
    final monthly = await DatabaseHelper().getMonthlyTotals(monthsBack: 6);

    double total = 0;
    for (final row in breakdown) {
      total += (row['total'] as num).toDouble();
    }

    // --- Run-rate projection for the rest of this month ---
    //
    // Blends "pace so far this month" with "historical monthly average",
    // weighted by how far through the month we are. Early in the month,
    // one big purchase shouldn't make the pace projection swing wildly --
    // lean on history. Late in the month, this month's actual pace is the
    // more informative signal. This is a heuristic, not a trained model --
    // there isn't enough history yet (see conversation) for Prophet/LSTM
    // to be trustworthy. Revisit once 6+ months of real data exist.
    final currentMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final historicalMonths = monthly
        .where((row) => row['month'] != currentMonthKey)
        .map((row) => (row['total'] as num).toDouble())
        .toList();

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = now.day.clamp(1, daysInMonth);
    final fractionOfMonth = daysElapsed / daysInMonth;

    final paceProjection = total / daysElapsed * daysInMonth;
    final historicalAvg = historicalMonths.isNotEmpty
        ? historicalMonths.reduce((a, b) => a + b) / historicalMonths.length
        : null;

    final projection = historicalAvg == null
        ? paceProjection
        : (fractionOfMonth * paceProjection) +
            ((1 - fractionOfMonth) * historicalAvg);

    if (!mounted) return;

    setState(() {
      categoryBreakdown = breakdown;
      monthlyTotals = monthly;
      currentMonthTotal = total;
      projectedMonthTotal = projection;
      loading = false;
    });
  }

  String _monthLabel(String yyyyMm) {
    // yyyyMm like "2026-09" -> "Sep"
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = int.tryParse(yyyyMm.split('-').last) ?? 1;
    return names[(month - 1).clamp(0, 11)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'This Month',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Spent', style: TextStyle(fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(
                            '₹${currentMonthTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (projectedMonthTotal != null)
                    Card(
                      color: Colors.deepPurple.withValues(alpha: 0.06),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.trending_up, size: 18, color: Colors.deepPurple),
                                SizedBox(width: 6),
                                Text(
                                  'Projected by month end',
                                  style: TextStyle(fontSize: 14, color: Colors.deepPurple),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${projectedMonthTotal!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Based on spending pace this month blended with past months. '
                              'Gets more accurate with more months of data.',
                              style: TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  if (categoryBreakdown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('No spending recorded this month yet.')),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 220,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 40,
                                  sections: categoryBreakdown.map((row) {
                                    final category = row['category'] as String;
                                    final total = (row['total'] as num).toDouble();
                                    final pct = currentMonthTotal > 0
                                        ? (total / currentMonthTotal * 100)
                                        : 0.0;

                                    return PieChartSectionData(
                                      value: total,
                                      color: _colorFor(category),
                                      title: '${pct.toStringAsFixed(0)}%',
                                      radius: 60,
                                      titleStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Legend -- PieChart doesn't ship one built in.
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: categoryBreakdown.map((row) {
                                final category = row['category'] as String;
                                final total = (row['total'] as num).toDouble();
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: _colorFor(category),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$category (₹${total.toStringAsFixed(0)})',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 28),

                  const Text(
                    'Last 6 Months',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (monthlyTotals.length < 2)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text('Need at least 2 months of data to show a trend.'),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
                        child: SizedBox(
                          height: 220,
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: true),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx < 0 || idx >= monthlyTotals.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          _monthLabel(monthlyTotals[idx]['month'] as String),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: [
                                    for (int i = 0; i < monthlyTotals.length; i++)
                                      FlSpot(
                                        i.toDouble(),
                                        (monthlyTotals[i]['total'] as num).toDouble(),
                                      ),
                                  ],
                                  isCurved: true,
                                  color: Colors.deepPurple,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.deepPurple.withValues(alpha: 0.1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}