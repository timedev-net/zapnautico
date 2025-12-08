import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/launch_queue_entry.dart';
import '../providers.dart';

class MarinaQueueDashboardPage extends ConsumerWidget {
  const MarinaQueueDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(marinaQueueDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard da marina')),
      body: dashboardAsync.when(
        data: (data) {
          final entries = data.entries;
          final today = DateTime.now();
          final rangeEnd = DateTime(today.year, today.month, today.day);

          if (entries.isEmpty) {
            return _DashboardEmptyState(
              onRefresh: () async {
                ref.invalidate(marinaQueueDashboardProvider);
                await ref.read(marinaQueueDashboardProvider.future);
              },
            );
          }

          final statusTotals = _statusTotals(entries);
          final dailyRequests = _dailyCounts(
            entries,
            (entry) => entry.requestedAt,
            start: data.rangeStart,
            end: rangeEnd,
          );
          final dailyOutcomes = _dailyOutcomeCounts(
            entries,
            start: data.rangeStart,
            end: rangeEnd,
          );
          final averageDuration = _averageProcessingTime(entries);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(marinaQueueDashboardProvider);
              await ref.read(marinaQueueDashboardProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryHeader(
                  marinaName: data.marinaName,
                  total: entries.length,
                  pending:
                      (statusTotals['pending'] ?? 0) + (statusTotals['in_progress'] ?? 0),
                  inWater: statusTotals['in_water'] ?? 0,
                  completed: statusTotals['completed'] ?? 0,
                  cancelled: statusTotals['cancelled'] ?? 0,
                  averageDuration: averageDuration,
                ),
                const SizedBox(height: 16),
                _ChartCard(
                  title: 'Entradas diárias (últimos 14 dias)',
                  child: _DailyLineChart(data: dailyRequests),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  title: 'Andamentos concluídos x cancelados',
                  child: _OutcomeBarChart(data: dailyOutcomes),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  title: 'Distribuição por status',
                  child: _StatusPieChart(statusTotals: statusTotals),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _DashboardErrorState(
          error: error,
          onRetry: () => ref.invalidate(marinaQueueDashboardProvider),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.marinaName,
    required this.total,
    required this.pending,
    required this.inWater,
    required this.completed,
    required this.cancelled,
    required this.averageDuration,
  });

  final String marinaName;
  final int total;
  final int pending;
  final int inWater;
  final int completed;
  final int cancelled;
  final Duration? averageDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationText = averageDuration == null
        ? '—'
        : _formatDuration(averageDuration!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              marinaName.isNotEmpty ? marinaName : 'Minha marina',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryChip(
                  label: 'Registros',
                  value: total.toString(),
                  icon: Icons.layers_outlined,
                ),
                _SummaryChip(
                  label: 'Pendentes/Em andamento',
                  value: pending.toString(),
                  icon: Icons.pending_actions_outlined,
                ),
                _SummaryChip(
                  label: 'Na água',
                  value: inWater.toString(),
                  icon: Icons.water_drop_outlined,
                ),
                _SummaryChip(
                  label: 'Concluídos',
                  value: completed.toString(),
                  icon: Icons.check_circle_outline,
                ),
                _SummaryChip(
                  label: 'Cancelados',
                  value: cancelled.toString(),
                  icon: Icons.cancel_outlined,
                ),
                _SummaryChip(
                  label: 'Tempo médio',
                  value: durationText,
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, color: colorScheme.primary),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      backgroundColor: colorScheme.surfaceContainerHighest,
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DailyLineChart extends StatelessWidget {
  const _DailyLineChart({required this.data});

  final List<_DailyCount> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _NoDataPlaceholder();
    }
    final theme = Theme.of(context);
    final spots = [
      for (var i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), data[i].count.toDouble()),
    ];

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: _resolveMaxY(data),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      data[index].label,
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: theme.colorScheme.primary,
              isCurved: true,
              dotData: const FlDotData(show: false),
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeBarChart extends StatelessWidget {
  const _OutcomeBarChart({required this.data});

  final List<_DailyOutcome> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _NoDataPlaceholder();
    }

    final theme = Theme.of(context);
    final completedColor = theme.colorScheme.primary;
    final cancelledColor = theme.colorScheme.error;
    final inWaterColor = theme.colorScheme.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              maxY: _resolveOutcomeMaxY(data),
              barGroups: [
                for (var i = 0; i < data.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 6,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].completed.toDouble(),
                        color: completedColor,
                        borderRadius: BorderRadius.circular(6),
                        width: 12,
                      ),
                      BarChartRodData(
                        toY: data[i].inWater.toDouble(),
                        color: inWaterColor,
                        borderRadius: BorderRadius.circular(6),
                        width: 12,
                      ),
                      BarChartRodData(
                        toY: data[i].cancelled.toDouble(),
                        color: cancelledColor,
                        borderRadius: BorderRadius.circular(6),
                        width: 12,
                      ),
                    ],
                  ),
              ],
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          data[index].label,
                          style: theme.textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _LegendEntry(label: 'Concluídos', color: completedColor),
            _LegendEntry(label: 'Na água', color: inWaterColor),
            _LegendEntry(label: 'Cancelados', color: cancelledColor),
          ],
        ),
      ],
    );
  }
}

class _StatusPieChart extends StatelessWidget {
  const _StatusPieChart({required this.statusTotals});

  final Map<String, int> statusTotals;

  @override
  Widget build(BuildContext context) {
    final entries = statusTotals.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const _NoDataPlaceholder();
    }

    final theme = Theme.of(context);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 32,
              sections: [
                for (final entry in entries)
                  PieChartSectionData(
                    value: entry.value.toDouble(),
                    title: '${entry.value}',
                    color: _statusColor(theme, entry.key),
                    radius: 110,
                    titleStyle: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              _StatusLegend(
                label: _translateStatus(entry.key),
                value: entry.value,
                percentage: total == 0 ? 0 : (entry.value / total) * 100,
                color: _statusColor(theme, entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend({
    required this.label,
    required this.value,
    required this.percentage,
    required this.color,
  });

  final String label;
  final int value;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: $value (${percentage.toStringAsFixed(1)}%)',
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

class _DashboardErrorState extends StatelessWidget {
  const _DashboardErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              '$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(
            Icons.insights_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          const Text(
            'Nenhum dado encontrado para o período.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NoDataPlaceholder extends StatelessWidget {
  const _NoDataPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          'Sem dados suficientes para exibir o gráfico.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DailyCount {
  _DailyCount({required this.label, required this.count});

  final String label;
  final int count;
}

class _DailyOutcome {
  _DailyOutcome({
    required this.label,
    required this.completed,
    required this.inWater,
    required this.cancelled,
  });

  final String label;
  final int completed;
  final int inWater;
  final int cancelled;
}

double _resolveMaxY(List<_DailyCount> data) {
  final maxValue = data.fold<int>(0, (max, item) => item.count > max ? item.count : max);
  return (maxValue + 1).toDouble();
}

double _resolveOutcomeMaxY(List<_DailyOutcome> data) {
  int maxValue = 0;
  for (final item in data) {
    maxValue = [
      maxValue,
      item.completed,
      item.inWater,
      item.cancelled,
    ].reduce((a, b) => a > b ? a : b);
  }
  return (maxValue + 1).toDouble();
}

List<_DailyCount> _dailyCounts(
  List<LaunchQueueEntry> entries,
  DateTime Function(LaunchQueueEntry entry) dateSelector, {
  required DateTime start,
  required DateTime end,
}) {
  final formatter = DateFormat('dd/MM');
  final today = DateTime(end.year, end.month, end.day);
  final startDay = DateTime(start.year, start.month, start.day);
  final buckets = <DateTime, int>{};

  for (var i = 0; i <= today.difference(startDay).inDays; i++) {
    final day = startDay.add(Duration(days: i));
    buckets[day] = 0;
  }

  for (final entry in entries) {
    final localDate = dateSelector(entry).toLocal();
    final bucket = DateTime(localDate.year, localDate.month, localDate.day);
    if (bucket.isBefore(startDay) || bucket.isAfter(today)) continue;
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;
  }

  final sortedKeys = buckets.keys.toList()..sort();
  return sortedKeys
      .map(
        (day) => _DailyCount(
          label: formatter.format(day),
          count: buckets[day] ?? 0,
        ),
      )
      .toList();
}

List<_DailyOutcome> _dailyOutcomeCounts(
  List<LaunchQueueEntry> entries, {
  required DateTime start,
  required DateTime end,
}) {
  final formatter = DateFormat('dd/MM');
  final today = DateTime(end.year, end.month, end.day);
  final startDay = DateTime(start.year, start.month, start.day);
  final buckets = <DateTime, _DailyOutcome>{};

  for (var i = 0; i <= today.difference(startDay).inDays; i++) {
    final day = startDay.add(Duration(days: i));
    buckets[day] = _DailyOutcome(
      label: formatter.format(day),
      completed: 0,
      inWater: 0,
      cancelled: 0,
    );
  }

  for (final entry in entries) {
    final processed = entry.processedAt;
    if (processed == null) continue;

    final localDate = processed.toLocal();
    final bucket = DateTime(localDate.year, localDate.month, localDate.day);
    if (bucket.isBefore(startDay) || bucket.isAfter(today)) continue;

    final outcome = buckets[bucket];
    if (outcome == null) continue;

    switch (entry.status) {
      case 'completed':
        buckets[bucket] = _DailyOutcome(
          label: outcome.label,
          completed: outcome.completed + 1,
          inWater: outcome.inWater,
          cancelled: outcome.cancelled,
        );
        break;
      case 'cancelled':
        buckets[bucket] = _DailyOutcome(
          label: outcome.label,
          completed: outcome.completed,
          inWater: outcome.inWater,
          cancelled: outcome.cancelled + 1,
        );
        break;
      case 'in_water':
        buckets[bucket] = _DailyOutcome(
          label: outcome.label,
          completed: outcome.completed,
          inWater: outcome.inWater + 1,
          cancelled: outcome.cancelled,
        );
        break;
      default:
        break;
    }
  }

  final sortedKeys = buckets.keys.toList()..sort();
  return sortedKeys.map((day) => buckets[day]!).toList();
}

Map<String, int> _statusTotals(List<LaunchQueueEntry> entries) {
  final totals = <String, int>{};
  for (final entry in entries) {
    totals.update(entry.status, (value) => value + 1, ifAbsent: () => 1);
  }
  return totals;
}

Duration? _averageProcessingTime(List<LaunchQueueEntry> entries) {
  final durations = <Duration>[];
  for (final entry in entries) {
    if (entry.processedAt == null) continue;
    durations.add(entry.processedAt!.difference(entry.requestedAt));
  }
  if (durations.isEmpty) return null;
  final totalMillis = durations.fold<int>(0, (sum, item) => sum + item.inMilliseconds);
  return Duration(milliseconds: (totalMillis / durations.length).round());
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) {
    return '${minutes}min';
  }
  return '${hours}h ${minutes}min';
}

Color _statusColor(ThemeData theme, String status) {
  switch (status) {
    case 'pending':
      return theme.colorScheme.primary;
    case 'in_progress':
      return theme.colorScheme.secondary;
    case 'in_water':
      return theme.colorScheme.tertiary;
    case 'completed':
      return Colors.green.shade600;
    case 'cancelled':
      return theme.colorScheme.error;
    default:
      return theme.colorScheme.outline;
  }
}

String _translateStatus(String status) {
  switch (status) {
    case 'pending':
      return 'Pendente';
    case 'in_progress':
      return 'Em andamento';
    case 'in_water':
      return 'Na água';
    case 'completed':
      return 'Concluído';
    case 'cancelled':
      return 'Cancelado';
    default:
      return status;
  }
}
