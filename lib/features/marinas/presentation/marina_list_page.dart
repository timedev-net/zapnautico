import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/marina.dart';
import '../providers.dart';
import 'marina_detail_page.dart';
import 'marina_form_page.dart';

class MarinaListPage extends ConsumerWidget {
  const MarinaListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marinasAsync = ref.watch(marinasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marinas'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MarinaFormPage(),
            ),
          );
          ref.invalidate(marinasProvider);
        },
        child: const Icon(Icons.add),
      ),
      body: marinasAsync.when(
        data: (marinas) {
          if (marinas.isEmpty) {
            return const _EmptyState();
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(marinasProvider);
              await ref.read(marinasProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final marina = marinas[index];
                return _MarinaCard(marina: marina);
              },
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemCount: marinas.length,
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          error: error,
          onRetry: () => ref.invalidate(marinasProvider),
        ),
      ),
    );
  }
}

class _MarinaCard extends StatelessWidget {
  const _MarinaCard({required this.marina});

  final Marina marina;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: _MarinaPreview(photoUrl: marina.photoUrl),
        title: Text(
          marina.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: marina.address != null && marina.address!.isNotEmpty
            ? Text(marina.address!)
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MarinaDetailPage(marinaId: marina.id),
            ),
          );
        },
      ),
    );
  }
}

class _MarinaPreview extends StatelessWidget {
  const _MarinaPreview({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) {
      return const CircleAvatar(
        radius: 24,
        child: Icon(Icons.sailing),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.network(
        photoUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const CircleAvatar(
          radius: 24,
          child: Icon(Icons.sailing),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sailing_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma marina cadastrada.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre marinas para facilitar o acesso dos cotistas.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar as marinas.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
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
