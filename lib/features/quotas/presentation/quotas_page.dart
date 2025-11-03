import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';
import '../data/quotas_repository.dart';
import '../domain/quota.dart';

final quotasRepositoryProvider = Provider<QuotasRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return QuotasRepository(client);
});

final quotasProvider = FutureProvider<List<Quota>>((ref) {
  return ref.watch(quotasRepositoryProvider).fetchQuotas();
});

class QuotasPage extends ConsumerWidget {
  const QuotasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotasAsync = ref.watch(quotasProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(quotasProvider.future),
      child: quotasAsync.when(
        data: (quotas) {
          if (quotas.isEmpty) {
            return const _EmptyState(
              message:
                  'Nenhuma cota cadastrada. Cadastre cotistas no Supabase.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final quota = quotas[index];
              return _QuotaCard(quota: quota);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: quotas.length,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorState(
          message: 'Falha ao carregar cotas.',
          error: error,
          onRetry: () => ref.invalidate(quotasProvider),
        ),
      ),
    );
  }
}

class _QuotaCard extends ConsumerWidget {
  const _QuotaCard({required this.quota});

  final Quota quota;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(quotasRepositoryProvider);

    Future<void> handleAction(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        ref.invalidate(quotasProvider);
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Operação não concluída: $error')),
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quota.boatName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  label: Text('${quota.availableSlots} vagas'),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.place, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(quota.marina)),
              ],
            ),
            if (quota.nextDeparture != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Próxima saída: '
                    '${MaterialLocalizations.of(context).formatShortDate(quota.nextDeparture!)} '
                    '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(quota.nextDeparture!))}',
                  ),
                ],
              ),
            ],
            if (quota.notes != null && quota.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                quota.notes!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: quota.availableSlots > 0
                      ? () => handleAction(
                          () => repository.reserveSlot(quota.id),
                        )
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Reservar'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => handleAction(
                    () => repository.releaseSlot(quota.id),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Liberar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
          child: Column(
            children: [
              Icon(Icons.directions_boat, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.error,
    required this.onRetry,
  });

  final String message;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
          child: Column(
            children: [
              Icon(
                Icons.warning_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
