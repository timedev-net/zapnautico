import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/boat_expense.dart';
import '../domain/boat_expense_category.dart';
import '../providers.dart';

class FinancialReportsPage extends ConsumerWidget {
  const FinancialReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(allBoatExpensesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios de gastos')),
      body: expensesAsync.when(
        data: (expenses) {
          if (expenses.isEmpty) {
            return const _EmptyReportState();
          }
          return _ReportsBody(
            expenses: expenses,
            onRefresh: () async {
              ref.invalidate(allBoatExpensesProvider);
              await ref.read(allBoatExpensesProvider.future);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorReportState(
          message: 'Não foi possível carregar os relatórios.',
          onRetry: () => ref.invalidate(allBoatExpensesProvider),
        ),
      ),
    );
  }
}

class _ReportsBody extends StatelessWidget {
  _ReportsBody({required this.expenses, required this.onRefresh});

  final List<BoatExpense> expenses;
  final Future<void> Function() onRefresh;
  final _currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

  List<_ChartPoint> get _monthlyPoints {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      6,
      (index) => DateTime(now.year, now.month - (5 - index), 1),
    );

    final grouped = <String, double>{};
    for (final month in months) {
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      grouped[key] = 0;
    }

    for (final expense in expenses) {
      final key =
          '${expense.incurredOn.year}-${expense.incurredOn.month.toString().padLeft(2, '0')}';
      if (grouped.containsKey(key)) {
        grouped[key] = grouped[key]! + expense.amount;
      }
    }

    final formatter = DateFormat('MMM/yy', 'pt_BR');
    return months
        .map(
          (month) => _ChartPoint(
            label: formatter.format(month),
            value:
                grouped['${month.year}-${month.month.toString().padLeft(2, '0')}'] ??
                0,
          ),
        )
        .toList();
  }

  List<_ChartPoint> get _annualPoints {
    final grouped = <int, double>{};
    for (final expense in expenses) {
      grouped.update(
        expense.incurredOn.year,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }

    final sortedYears = grouped.keys.toList()..sort();
    return sortedYears
        .map(
          (year) => _ChartPoint(label: year.toString(), value: grouped[year]!),
        )
        .toList();
  }

  List<_CategorySlice> get _categorySlices {
    final grouped = <BoatExpenseCategory, double>{};
    for (final expense in expenses) {
      grouped.update(
        expense.category,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    final total = grouped.values.fold<double>(0, (a, b) => a + b);
    return grouped.entries
        .map(
          (entry) => _CategorySlice(
            category: entry.key,
            value: entry.value,
            percentage: total == 0 ? 0 : (entry.value / total) * 100,
          ),
        )
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  double get _totalSpent =>
      expenses.fold<double>(0, (value, element) => value + element.amount);

  int get _boatCount =>
      expenses.map((expense) => expense.boatId).toSet().length;

  @override
  Widget build(BuildContext context) {
    final monthlyPoints = _monthlyPoints;
    final annualPoints = _annualPoints;
    final categorySlices = _categorySlices;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(
            total: _currency.format(_totalSpent),
            boats: _boatCount,
            records: expenses.length,
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Gastos nos últimos 6 meses',
            child: monthlyPoints.isEmpty
                ? const _NoDataPlaceholder()
                : SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        maxY: _resolveMax(monthlyPoints),
                        barGroups: [
                          for (var i = 0; i < monthlyPoints.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: monthlyPoints[i].value,
                                  borderRadius: BorderRadius.circular(8),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                        ],
                        gridData: FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          leftTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 ||
                                    index >= monthlyPoints.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    monthlyPoints[index].label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Visão anual',
            child: annualPoints.isEmpty
                ? const _NoDataPlaceholder()
                : SizedBox(
                    height: 220,
                    child: LineChart(
                      LineChartData(
                        maxY: _resolveMax(annualPoints),
                        minX: 0,
                        maxX: (annualPoints.length - 1).toDouble(),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= annualPoints.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    annualPoints[index].label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            isCurved: true,
                            dotData: const FlDotData(show: true),
                            barWidth: 4,
                            color: Theme.of(context).colorScheme.secondary,
                            spots: [
                              for (var i = 0; i < annualPoints.length; i++)
                                FlSpot(i.toDouble(), annualPoints[i].value),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Distribuição por categoria',
            child: categorySlices.isEmpty
                ? const _NoDataPlaceholder()
                : Column(
                    children: [
                      SizedBox(
                        height: 220,
                        child: PieChart(
                          PieChartData(
                            sections: [
                              for (final slice in categorySlices)
                                PieChartSectionData(
                                  title:
                                      '${slice.percentage.toStringAsFixed(1)}%',
                                  value: slice.value,
                                  color: _sliceColor(slice.category),
                                  radius: 70,
                                  titleStyle: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final slice in categorySlices)
                            _LegendItem(
                              color: _sliceColor(slice.category),
                              label:
                                  '${slice.category.label}: ${_currency.format(slice.value)}',
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  double _resolveMax(List<_ChartPoint> points) {
    if (points.isEmpty) return 0;
    final maxValue = points.fold<double>(
      0,
      (value, element) => element.value > value ? element.value : value,
    );
    if (maxValue == 0) return 10;
    return maxValue * 1.2;
  }

  Color _sliceColor(BoatExpenseCategory category) {
    switch (category) {
      case BoatExpenseCategory.maintenance:
        return Colors.blue.shade400;
      case BoatExpenseCategory.document:
        return Colors.orange.shade400;
      case BoatExpenseCategory.marina:
        return Colors.green.shade400;
      case BoatExpenseCategory.fuel:
        return Colors.red.shade400;
      case BoatExpenseCategory.accessories:
        return Colors.purple.shade400;
      case BoatExpenseCategory.other:
        return Colors.grey.shade500;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.boats,
    required this.records,
  });

  final String total;
  final int boats;
  final int records;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo geral',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(label: 'Total registrado', value: total),
                ),
                Expanded(
                  child: _SummaryTile(
                    label: 'Embarcações',
                    value: boats.toString(),
                  ),
                ),
                Expanded(
                  child: _SummaryTile(
                    label: 'Despesas',
                    value: records.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.query_stats,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Cadastre despesas para visualizar relatórios.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorReportState extends StatelessWidget {
  const _ErrorReportState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDataPlaceholder extends StatelessWidget {
  const _NoDataPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          'Sem dados suficientes para gerar este gráfico.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _ChartPoint {
  _ChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

class _CategorySlice {
  _CategorySlice({
    required this.category,
    required this.value,
    required this.percentage,
  });

  final BoatExpenseCategory category;
  final double value;
  final double percentage;
}
