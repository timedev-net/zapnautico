import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/supabase_providers.dart';
import '../../user_profiles/providers.dart';
import '../domain/listing.dart';
import 'listing_actions.dart';
import 'listing_form_page.dart';

class ListingDetailPage extends ConsumerStatefulWidget {
  const ListingDetailPage({super.key, required this.listing});

  final Listing listing;

  @override
  ConsumerState<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends ConsumerState<ListingDetailPage> {
  YoutubePlayerController? _youtubeController;
  late Listing _listing;

  @override
  void initState() {
    super.initState();
    _listing = widget.listing;
    final videoId = _extractYoutubeId(_listing.videoUrl);
    if (videoId != null) {
      _youtubeController = YoutubePlayerController(
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
        ),
      )..loadVideoById(videoId: videoId);
    }
  }

  @override
  void dispose() {
    _youtubeController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isOwner = _listing.ownerId == user?.id;
    final canEdit = isAdmin || (isOwner && _listing.canEdit);
    final canPublish = isAdmin || isOwner;
    final canDelete = isAdmin || (isOwner && !_listing.isSold);
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final mediaItems = <Widget>[];
    if (_youtubeController != null) {
      mediaItems.add(
        YoutubePlayer(
          controller: _youtubeController!,
          aspectRatio: 16 / 9,
        ),
      );
    }
    for (final photo in _listing.photos) {
      mediaItems.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            photo.publicUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
      );
    }

    final paymentChips = _listing.paymentOptions.isEmpty
        ? const ['Pix']
        : _listing.paymentOptions
            .map((option) => paymentOptionLabels[option] ?? option)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_listing.title),
        actions: [
          if (canEdit || canPublish || canDelete)
            PopupMenuButton<_ListingAction>(
              onSelected: (action) => _handleAction(
                context,
                ref,
                action,
                canEdit: canEdit,
                canPublish: canPublish,
                canDelete: canDelete,
              ),
              itemBuilder: (context) => [
                if (canEdit)
                  const PopupMenuItem(
                    value: _ListingAction.edit,
                    child: Text('Editar'),
                  ),
                if (canPublish && _listing.status == ListingStatus.pending)
                  const PopupMenuItem(
                    value: _ListingAction.publish,
                    child: Text('Publicar'),
                  ),
                if (canPublish && _listing.status == ListingStatus.published)
                  const PopupMenuItem(
                    value: _ListingAction.unpublish,
                    child: Text('Retirar da lista'),
                  ),
                if (canPublish && !_listing.isSold)
                  const PopupMenuItem(
                    value: _ListingAction.markSold,
                    child: Text('Informar venda'),
                  ),
                if (canDelete)
                  const PopupMenuItem(
                    value: _ListingAction.delete,
                    child: Text('Remover'),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (mediaItems.isNotEmpty)
            SizedBox(
              height: 240,
              child: PageView(
                children: mediaItems,
              ),
            )
          else
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.image_not_supported),
            ),
          const SizedBox(height: 16),
          Text(
            _listing.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _listing.price != null
                ? currencyFormat.format(_listing.price)
                : 'Sob consulta',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(_listing.category)),
              Chip(label: Text(_conditionLabel(_listing.condition))),
              for (final option in paymentChips) Chip(label: Text(option)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _listing.description ?? 'Sem descrição detalhada.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          if (_listing.latitude != null && _listing.longitude != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Localização',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(
                          _listing.latitude!,
                          _listing.longitude!,
                        ),
                        initialZoom: 13,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'br.frota.zapnautico',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(
                                _listing.latitude!,
                                _listing.longitude!,
                              ),
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_listing.city ?? ''} / ${_listing.state ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _openMaps(
                    _listing.latitude!,
                    _listing.longitude!,
                  ),
                  icon: const Icon(Icons.map),
                  label: const Text('Abrir no mapa'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          Text(
            'Contatos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final contact in _listing.whatsappContacts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(contact.name),
                subtitle: Text(contact.formattedNumber),
                trailing: IconButton(
                  icon: const Icon(Icons.chat),
                  onPressed: () => _launchUrl(contact.whatsappDeepLink),
                ),
              ),
            ),
          if (_listing.showEmail && _listing.ownerEmail != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('E-mail'),
                subtitle: Text(_listing.ownerEmail!),
                trailing: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _launchUrl(
                    'mailto:${_listing.ownerEmail}',
                  ),
                ),
              ),
            ),
          if (_listing.instagramHandle != null &&
              _listing.instagramHandle!.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Instagram'),
                subtitle: Text('@${_listing.instagramHandle}'),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _launchUrl(
                    'https://instagram.com/${_listing.instagramHandle}',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Informações do anúncio',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Anunciante'),
            subtitle: Text(
              _listing.advertiserName ?? _listing.ownerName ?? 'Não informado',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Criado em'),
            subtitle: Text(
              DateFormat('dd/MM/yyyy').format(_listing.createdAt),
            ),
          ),
          if (_listing.isPublished && _listing.publishedAt != null)
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Publicado em'),
              subtitle: Text(
                DateFormat('dd/MM/yyyy').format(_listing.publishedAt!),
              ),
            ),
          if (_listing.isSold && _listing.soldAt != null)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Vendido em'),
              subtitle: Text(
                DateFormat('dd/MM/yyyy').format(_listing.soldAt!),
              ),
            ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ListingFormPage(listing: _listing),
                  ),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('Editar anúncio'),
            )
          : null,
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _ListingAction action, {
    required bool canEdit,
    required bool canPublish,
    required bool canDelete,
  }) async {
    final navigator = Navigator.of(context);
    switch (action) {
      case _ListingAction.edit:
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => ListingFormPage(listing: _listing),
          ),
        );
        break;
      case _ListingAction.publish:
        if (canPublish) {
          await publishListing(context, ref, _listing);
        }
        break;
      case _ListingAction.unpublish:
        if (canPublish) {
          await unpublishListing(context, ref, _listing);
        }
        break;
      case _ListingAction.markSold:
        if (canPublish && !_listing.isSold) {
          await markListingAsSold(context, ref, _listing);
        }
        break;
      case _ListingAction.delete:
        if (canDelete) {
          await deleteListing(context, ref, _listing);
          if (mounted) navigator.pop();
        }
        break;
    }
  }

  Future<void> _openMaps(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

enum _ListingAction { edit, publish, unpublish, markSold, delete }

String _conditionLabel(String condition) {
  switch (condition) {
    case ListingCondition.newItem:
      return 'Novo';
    case ListingCondition.used:
    default:
      return 'Usado';
  }
}

String? _extractYoutubeId(String? url) {
  if (url == null || url.isEmpty) return null;
  final regExp = RegExp(
    r'(?:v=|\/)([0-9A-Za-z_-]{11}).*',
  );
  final match = regExp.firstMatch(url);
  if (match != null && match.groupCount >= 1) {
    return match.group(1);
  }
  if (url.length == 11) {
    return url;
  }
  return null;
}
