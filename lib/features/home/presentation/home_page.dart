import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';
import '../../queue/presentation/queue_crud_page.dart';
import '../../queue/providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queueStateAsync = ref.watch(queueStateProvider);
    final queueState = queueStateAsync.asData?.value;
    final isLoadingQueueState = queueStateAsync.isLoading;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 96,
            ),
            const SizedBox(height: 24),
            Text(
              'Bem-vindo ao ZapNáutico',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Navegue com confiança: organize embarcações, equipes e experiências náuticas em um só lugar.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _handleSeeQueue(
                        context,
                        ref,
                        queueStateAsync,
                      ),
              icon: isLoadingQueueState
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.directions_boat_filled),
              label: const Text('Ver fila'),
            ),
            const SizedBox(height: 12),
            if (!isLoadingQueueState && queueStateAsync.hasError)
              Text(
                'Não foi possível carregar suas filas no momento.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              )
            else if (!isLoadingQueueState &&
                queueState != null &&
                queueState.audience == QueueAudience.none)
              Text(
                'Você ainda não possui acesso às filas. Solicite a um administrador para seguir.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              )
            else if (!isLoadingQueueState &&
                queueState != null &&
                queueState.options.isEmpty)
              Text(
                'Nenhuma marina vinculada foi encontrada para exibir a fila.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSeeQueue(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<QueueState> queueStateAsync,
  ) async {
    var queueState = queueStateAsync.asData?.value;
    if (queueState == null) {
      if (queueStateAsync.isLoading) {
        try {
          queueState = await ref.read(queueStateProvider.future);
        } catch (_) {
          _showSnackBar(
            context,
            'Não foi possível carregar as informações da fila. Tente novamente.',
          );
          return;
        }
      } else {
        _showSnackBar(
          context,
          'Não foi possível carregar as informações da fila. Tente novamente.',
        );
        return;
      }
    }

    if (queueState == null) {
      _showSnackBar(
        context,
        'Não foi possível carregar as informações da fila. Tente novamente.',
      );
      return;
    }

    final resolvedQueueState = queueState;

    if (resolvedQueueState.audience == QueueAudience.none) {
      _showSnackBar(
        context,
        'Você não possui permissão para acessar as filas.',
      );
      return;
    }

    if (resolvedQueueState.options.isEmpty) {
      _showSnackBar(
        context,
        'Nenhuma marina disponível para exibir a fila.',
      );
      return;
    }

    final selectedMarinaId = resolvedQueueState.options.length == 1
        ? resolvedQueueState.options.first.id
        : await _showMarinaSelector(context, resolvedQueueState);

    if (selectedMarinaId == null || selectedMarinaId.isEmpty) {
      return;
    }

    final user = ref.read(userProvider);
    final config = QueueSelectionConfig(
      userId: user?.id,
      audience: resolvedQueueState.audience,
    );

    await ref
        .read(queueSelectionControllerProvider(config).notifier)
        .setSelection(selectedMarinaId);

    ref.invalidate(queueStateProvider);
    ref.invalidate(launchQueueProvider(selectedMarinaId));

    await ref.read(queueStateProvider.future);

    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const QueueCrudPage(),
      ),
    );
  }

  Future<String?> _showMarinaSelector(
    BuildContext context,
    QueueState state,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  'Selecione a marina para visualizar a fila',
                  style: TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              for (final option in state.options)
                ListTile(
                  leading: const Icon(Icons.sailing),
                  title: Text(option.name),
                  onTap: () => Navigator.of(context).pop(option.id),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
