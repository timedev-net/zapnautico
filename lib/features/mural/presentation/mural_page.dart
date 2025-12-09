import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/marina_wall_post.dart';
import '../providers.dart';
import 'marina_wall_post_detail_page.dart';
import 'mural_form_page.dart';

class MuralPage extends ConsumerStatefulWidget {
  const MuralPage({super.key});

  @override
  ConsumerState<MuralPage> createState() => _MuralPageState();
}

class _MuralPageState extends ConsumerState<MuralPage> {
  String _filter = 'todos';

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(muralPostsProvider);
    final marinaProfile = ref.watch(currentMarinaProfileProvider);
    final canCreate = marinaProfile != null && marinaProfile.marinaId != null;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(muralPostsProvider);
        await ref.read(muralPostsProvider.future);
      },
      child: postsAsync.when(
        data: (posts) {
          final filtered = _filter == 'todos'
              ? posts
              : posts.where((post) => post.type == _filter).toList();

          return ListView(
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _HeaderSection(
                canCreate: canCreate,
                onCreate: () {
                  final marinaId = marinaProfile?.marinaId;
                  if (marinaId == null || marinaId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Apenas usuarios com perfil de marina podem publicar.',
                        ),
                      ),
                    );
                    return;
                  }
                  _openForm(
                    marinaId: marinaId,
                    marinaName: marinaProfile?.marinaName,
                  );
                },
              ),
              const SizedBox(height: 16),
              _FilterChips(
                selected: _filter,
                onSelected: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Nenhuma publicacao encontrada para este filtro.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else ...[
                for (final post in filtered) ...[
                  _MuralCard(post: post),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          );
        },
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 200),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 8),
                Text(
                  'Erro ao carregar o mural',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.invalidate(muralPostsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm({required String marinaId, String? marinaName}) async {
    final created = await Navigator.of(context).push<MarinaWallPost>(
      MaterialPageRoute(
        builder: (_) =>
            MuralFormPage(marinaId: marinaId, marinaName: marinaName),
      ),
    );

    if (created != null) {
      ref.invalidate(muralPostsProvider);
    }
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.canCreate, required this.onCreate});

  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mural de informações',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Acompanhe avisos, eventos e campanhas publicados por cada marina.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (canCreate)
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.post_add),
            label: const Text('Nova publicacao'),
          ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const options = <String, String>{
      'todos': 'Todos',
      'evento': 'Eventos',
      'aviso': 'Avisos',
      'publicidade': 'Publicidade',
    };

    return Wrap(
      spacing: 8,
      children: [
        for (final entry in options.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: selected == entry.key,
            onSelected: (_) => onSelected(entry.key),
          ),
      ],
    );
  }
}

class _MuralCard extends StatelessWidget {
  const _MuralCard({required this.post});

  final MarinaWallPost post;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final dateLabel = post.isSingleDay
        ? dateFormat.format(post.startDate)
        : '${dateFormat.format(post.startDate)} - ${dateFormat.format(post.endDate)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarinaWallPostDetailPage(postId: post.id),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.hasImage)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  post.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(
                        label: Text(muralPostTypeLabels[post.type] ?? post.type),
                        backgroundColor: _typeColor(context, post.type),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.description ?? 'Sem descricao informada.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.sailing, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        post.marinaName ?? 'Marina',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy')
                            .format(post.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
