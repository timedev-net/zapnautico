import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_providers.dart';
import '../../user_profiles/providers.dart';
import '../data/boat_repository.dart';
import '../domain/boat.dart';
import '../domain/boat_photo.dart';
import '../providers.dart';
import 'boat_form_page.dart';
import 'boat_gallery_page.dart';

class BoatDetailPage extends ConsumerWidget {
  const BoatDetailPage({super.key, required this.boatId});

  final String boatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boatAsync = ref.watch(boatFutureProvider(boatId));
    final user = ref.watch(userProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return boatAsync.when(
      data: (boat) {
        if (boat == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Embarcação')),
            body: const Center(
              child: Text('Embarcação não encontrada ou sem acesso.'),
            ),
          );
        }

        final canEdit = isAdmin || boat.canEdit(user?.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(boat.name),
            actions: [
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Editar',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BoatFormPage(boat: boat),
                      ),
                    );
                    ref.invalidate(boatsProvider);
                    ref.invalidate(boatFutureProvider(boatId));
                  },
                ),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Excluir embarcação',
                  onPressed: () => _confirmDelete(context, ref, boat),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(boatFutureProvider(boatId));
              await ref.read(boatFutureProvider(boatId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _PhotoGallery(photos: boat.photos),
                const SizedBox(height: 24),
                _SectionTitle('Informações gerais'),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Tipo de embarcação',
                  value: boat.boatType.label,
                ),
                _InfoRow(
                  label: 'Número de inscrição',
                  value: boat.registrationNumber ?? 'Não informado',
                ),
                _InfoRow(
                  label: 'Ano de fabricação',
                  value: boat.fabricationYear.toString(),
                ),
                _InfoRow(label: 'Propulsão', value: boat.propulsionType.label),
                _InfoRow(label: 'Finalidade', value: boat.usageType.label),
                _InfoRow(label: 'Porte', value: boat.size.label),
                _InfoRow(
                  label: 'Marina vinculada',
                  value: boat.marinaName ?? 'Sem marina',
                ),
                if (boat.trailerPlate != null && boat.trailerPlate!.isNotEmpty)
                  _InfoRow(
                    label: 'Placa da carretinha',
                    value: boat.trailerPlate!,
                  ),
                const SizedBox(height: 24),
                if (boat.hasEngineDetails) ...[
                  _SectionTitle('Detalhes do motor'),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'Quantidade de motores',
                    value: '${boat.engineCount ?? 0}',
                  ),
                  _InfoRow(
                    label: 'Marca',
                    value: boat.engineBrand ?? 'Não informado',
                  ),
                  _InfoRow(
                    label: 'Modelo',
                    value: boat.engineModel ?? 'Não informado',
                  ),
                  _InfoRow(
                    label: 'Ano do motor',
                    value: boat.engineYear?.toString() ?? 'Não informado',
                  ),
                  _InfoRow(
                    label: 'Potência',
                    value: boat.enginePower ?? 'Não informado',
                  ),
                  const SizedBox(height: 24),
                ],
                _SectionTitle('Proprietários'),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Principal',
                  value: boat.primaryOwnerName?.isNotEmpty == true
                      ? '${boat.primaryOwnerName} (${boat.primaryOwnerEmail ?? 'sem e-mail'})'
                      : boat.primaryOwnerEmail ?? boat.primaryOwnerId,
                ),
                if (boat.coOwners.isEmpty)
                  _InfoRow(label: 'Coproprietários', value: 'Nenhum')
                else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Coproprietários',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final owner in boat.coOwners)
                        Chip(label: Text(owner.displayName)),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                if (boat.description != null && boat.description!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle('Descrição'),
                      const SizedBox(height: 8),
                      Text(
                        boat.description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                _SectionTitle('Registro'),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Cadastrado em',
                  value: _formatDateTime(context, boat.createdAt),
                ),
                _InfoRow(
                  label: 'Atualizado em',
                  value: _formatDateTime(context, boat.updatedAt),
                ),
              ],
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Embarcação')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_boat_filled_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar embarcação.',
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
                  onPressed: () => ref.invalidate(boatFutureProvider(boatId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Boat boat,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remover embarcação'),
          content: Text(
            'Tem certeza de que deseja remover "${boat.name}"? '
            'Esta ação não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(boatRepositoryProvider).deleteBoat(boat);
      ref.invalidate(boatsProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir embarcação: $error')),
      );
    }
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final formatter = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    return formatter.format(value.toLocal());
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.photos});

  final List<BoatPhoto> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: const Center(
          child: Icon(Icons.directions_boat_outlined, size: 64),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BoatGalleryPage(photos: photos, initialIndex: index),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                photo.publicUrl,
                width: 280,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 280,
                  height: 200,
                  color: Theme.of(context).colorScheme.surface,
                  child: const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
