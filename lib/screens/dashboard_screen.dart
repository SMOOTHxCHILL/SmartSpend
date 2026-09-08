import 'package:flutter/material.dart';
import '../db/database_helper.dart';

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

    final rows = await DatabaseHelper().getAllParsedTransactions();

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
      transactions = rows.take(20).toList();
      loading = false;
    });
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

                  const Text(
                    'Recent Transactions',
                    style: TextStyle(
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
                            transaction['raw_merchant'] as String? ?? 'Unknown';

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
                            subtitle: Text(
                              _formatDate(
                                transaction['transaction_date'],
                              ),
                            ),
                            trailing: Text(
                              '${isCredit ? '+' : '-'}'
                              '₹${amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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