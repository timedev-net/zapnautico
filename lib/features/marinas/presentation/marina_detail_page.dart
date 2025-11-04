import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../user_profiles/providers.dart';
import '../data/marina_repository.dart';
import '../domain/marina.dart';
import '../providers.dart';
import 'marina_form_page.dart';

class MarinaDetailPage extends ConsumerWidget {
  const MarinaDetailPage({super.key, required this.marinaId});

  final String marinaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marinaAsync = ref.watch(marinaFutureProvider(marinaId));
    final isAdmin = ref.watch(isAdminProvider);

    return marinaAsync.when(
      data: (marina) {
        if (marina == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Marina')),
            body: const Center(child: Text('Marina não encontrada.')),
          );
        }
        return _MarinaDetailView(marina: marina, isAdmin: isAdmin);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Marina')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erro ao carregar marina: $error'),
          ),
        ),
      ),
    );
  }
}

class _MarinaDetailView extends ConsumerWidget {
  const _MarinaDetailView({
    required this.marina,
    required this.isAdmin,
  });

  final Marina marina;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(marina.name),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MarinaFormPage(marina: marina),
                  ),
                );
                ref.invalidate(marinasProvider);
                ref.invalidate(marinaFutureProvider(marina.id));
              },
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildPhoto(context),
          const SizedBox(height: 24),
          Text(
            marina.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (marina.address != null && marina.address!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    marina.address!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (marina.whatsapp != null && marina.whatsapp!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _openWhatsapp(marina.whatsapp!),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
              if (marina.instagram != null && marina.instagram!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _openInstagram(marina.instagram!),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Instagram'),
                ),
              OutlinedButton.icon(
                onPressed: () => _openNavigation(marina.latitude, marina.longitude),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Navegar'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildMap(context),
        ],
      ),
    );
  }

  Widget _buildPhoto(BuildContext context) {
    if (marina.photoUrl == null || marina.photoUrl!.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(Icons.sailing_outlined, size: 64),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        marina.photoUrl!,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 220,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final location = LatLng(marina.latitude, marina.longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: location,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.zapnautico',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: location,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    size: 36,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsapp(String number) async {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInstagram(String handle) async {
    var username = handle.trim();
    if (username.startsWith('@')) {
      username = username.substring(1);
    }
    final hasScheme = username.startsWith('http://') || username.startsWith('https://');
    final uri = Uri.parse(hasScheme ? username : 'https://instagram.com/$username');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openNavigation(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover marina'),
        content: const Text('Tem certeza que deseja remover esta marina?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(marinaRepositoryProvider).deleteMarina(marina);
      ref.invalidate(marinasProvider);
      ref.invalidate(marinaFutureProvider(marina.id));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover: $error')),
        );
      }
    }
  }
}
