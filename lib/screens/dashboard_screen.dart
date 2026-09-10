import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'category_picker_sheet.dart';
import 'insights_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool loading = true;

  double totalSpent = 0;
  int transactionCount = 0;
  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      loading = true;
    });

    final rows = await DatabaseHelper().getAllParsedTransactionsWithMerchant();

    double spent = 0;

    for (final transaction in rows) {
      final type = transaction['type'] as String?;

      if (type == 'debit') {
        spent += (transaction['amount'] as num).toDouble();
      }
    }

    if (!mounted) return;

    setState(() {
      totalSpent = spent;
      transactionCount = rows.length;
      transactions = rows;
      loading = false;
    });
  }

  Future<void> _correctCategory(Map<String, dynamic> transaction) async {
    final merchantId = transaction['merchant_id'] as int?;

    if (merchantId == null) {
      // Merchant hasn't been resolved yet for this transaction — nothing
      // to attach a category correction to.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merchant not resolved yet for this transaction.')),
      );
      return;
    }

    final currentCategory = transaction['category'] as String? ?? 'Other';

    final selected = await showCategoryPicker(
      context,
      currentCategory: currentCategory,
    );

    if (selected == null || selected == currentCategory) {
      return;
    }

    await DatabaseHelper().updateMerchantCategory(merchantId, selected);
    await _loadDashboard();
  }

  String _formatAmount(dynamic amount) {
    return '₹${(amount as num).toStringAsFixed(2)}';
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) {
      return 'Unknown date';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp as int);

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSpend'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: 'Insights',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const InsightsScreen()),
              );
            },
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Overview',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Spent',
                            style: TextStyle(
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatAmount(totalSpent),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Transactions',
                                style: TextStyle(fontSize: 14),
                              ),
                              Text(
                                '$transactionCount',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'All Transactions ($transactionCount)',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (transactions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No transactions yet.',
                        ),
                      ),
                    )
                  else
                    ...transactions.map(
                      (transaction) {
                        final type =
                            transaction['type'] as String? ?? 'debit';

                        final amount =
                            (transaction['amount'] as num).toDouble();

                        final merchant =
                            transaction['merchant_name'] as String? ??
                                transaction['raw_merchant'] as String? ??
                                'Unknown';

                        final category =
                            transaction['category'] as String? ?? 'Other';

                        final categorySource =
                            transaction['category_source'] as String? ?? 'default';

                        final isCredit = type == 'credit';

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                isCredit
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                              ),
                            ),
                            title: Text(
                              merchant,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                Text(_formatDate(transaction['transaction_date'])),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: categorySource == 'user_corrected'
                                        ? Colors.deepPurple.withValues(alpha: 0.15)
                                        : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: categorySource == 'user_corrected'
                                          ? Colors.deepPurple
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(
                              '${isCredit ? '+' : '-'}'
                              '₹${amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () => _correctCategory(transaction),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}