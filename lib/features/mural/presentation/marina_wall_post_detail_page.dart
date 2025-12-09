import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/marina_wall_post.dart';
import '../providers.dart';

class MarinaWallPostDetailPage extends ConsumerWidget {
  const MarinaWallPostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(marinaWallPostProvider(postId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes da publicação')),
      body: postAsync.when(
        data: (post) {
          if (post == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Publicação não encontrada.'),
              ),
            );
          }
          return _PostDetailBody(post: post);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(error: error),
      ),
    );
  }
}

class _PostDetailBody extends StatelessWidget {
  const _PostDetailBody({required this.post});

  final MarinaWallPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = _dateRangeLabel(post);
    final createdLabel =
        DateFormat('dd/MM/yyyy HH:mm').format(post.createdAt.toLocal());
    final updatedLabel =
        DateFormat('dd/MM/yyyy HH:mm').format(post.updatedAt.toLocal());
    final hasUpdates = post.updatedAt.isAfter(
      post.createdAt.add(const Duration(minutes: 1)),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (post.hasImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(muralPostTypeLabels[post.type] ?? post.type),
              backgroundColor: _typeColor(context, post.type),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_outlined, size: 18),
                const SizedBox(width: 6),
                Text(dateLabel, style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          post.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              post.description ?? 'Sem descrição informada.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoTile(
                icon: Icons.sailing,
                label: 'Marina',
                value: post.marinaName ?? 'Marina',
              ),
              _InfoTile(
                icon: Icons.event,
                label: 'Período',
                value: dateLabel,
              ),
              _InfoTile(
                icon: Icons.access_time,
                label: 'Publicado em',
                value: createdLabel,
              ),
              if (hasUpdates)
                _InfoTile(
                  icon: Icons.update,
                  label: 'Atualizado em',
                  value: updatedLabel,
                ),
              if (post.createdByName != null &&
                  post.createdByName!.trim().isNotEmpty)
                _InfoTile(
                  icon: Icons.person,
                  label: 'Publicado por',
                  value: post.createdByName!,
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _dateRangeLabel(MarinaWallPost post) {
    final format = DateFormat('dd/MM/yyyy');
    if (post.isSingleDay) {
      return format.format(post.startDate);
    }
    return '${format.format(post.startDate)} - ${format.format(post.endDate)}';
  }

  Color? _typeColor(BuildContext context, String type) {
    final colors = Theme.of(context).colorScheme;
    switch (type) {
      case 'evento':
        return colors.primaryContainer;
      case 'aviso':
        return colors.tertiaryContainer;
      case 'publicidade':
        return colors.secondaryContainer;
      default:
        return colors.surfaceContainerHighest;
    }
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: theme.textTheme.titleSmall),
      subtitle: Text(value, style: theme.textTheme.bodyMedium),
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

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
              'Não foi possível carregar a publicação.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
