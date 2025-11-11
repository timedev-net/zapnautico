import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../domain/listing.dart';

class ListingsRepository {
  ListingsRepository(this._client);

  final SupabaseClient _client;

  static const _bucket = 'marketplace_photos';
  static const _uuid = Uuid();

  Stream<List<Listing>> watchListings() {
    return _client
        .from('marketplace_listings_view')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Listing.fromMap).toList());
  }

  Future<String> createListing({
    required String title,
    required String category,
    required String condition,
    required List<String> paymentOptions,
    required List<ListingWhatsappContact> whatsappContacts,
    required List<ListingPhoto> retainedPhotos,
    required List<XFile> newPhotos,
    String? advertiserName,
    double? price,
    String? description,
    String? city,
    String? state,
    double? latitude,
    double? longitude,
    String? instagramHandle,
    bool showEmail = false,
    String? videoUrl,
    String? boatId,
  }) async {
    final userId = _requireUserId();
    if (whatsappContacts.isEmpty) {
      throw StateError('Inclua ao menos um contato do WhatsApp.');
    }

    final normalizedPayments = _normalizePaymentOptions(paymentOptions);
    final insertPayload = {
      'title': title,
      'category': category,
      'condition': condition,
      'payment_options': normalizedPayments,
      'whatsapp_contacts': whatsappContacts.map((c) => c.toJson()).toList(),
      'advertiser_name': advertiserName,
      'price': price,
      'description': description,
      'city': city,
      'state': state,
      'latitude': latitude,
      'longitude': longitude,
      'instagram_handle': instagramHandle,
      'show_email': showEmail,
      'video_url': videoUrl,
      'boat_id': boatId,
      'owner_id': userId,
      'status': ListingStatus.pending,
    };

    final response = await _client
        .from('marketplace_listings')
        .insert(insertPayload)
        .select('id')
        .single();

    final listingId = response['id']?.toString();
    if (listingId == null || listingId.isEmpty) {
      throw StateError('Não foi possível criar o anúncio.');
    }

    await _syncPhotos(
      listingId: listingId,
      retainedPhotos: retainedPhotos,
      newPhotos: newPhotos,
    );

    return listingId;
  }

  Future<void> updateListing({
    required Listing listing,
    required String title,
    required String category,
    required String condition,
    required List<String> paymentOptions,
    required List<ListingWhatsappContact> whatsappContacts,
    required List<ListingPhoto> retainedPhotos,
    required List<XFile> newPhotos,
    String? advertiserName,
    double? price,
    String? description,
    String? city,
    String? state,
    double? latitude,
    double? longitude,
    String? instagramHandle,
    bool showEmail = false,
    String? videoUrl,
  }) async {
    if (whatsappContacts.isEmpty) {
      throw StateError('Inclua ao menos um contato do WhatsApp.');
    }

    final normalizedPayments = _normalizePaymentOptions(paymentOptions);
    final payload = {
      'title': title,
      'category': category,
      'condition': condition,
      'payment_options': normalizedPayments,
      'whatsapp_contacts': whatsappContacts.map((c) => c.toJson()).toList(),
      'advertiser_name': advertiserName,
      'price': price,
      'description': description,
      'city': city,
      'state': state,
      'latitude': latitude,
      'longitude': longitude,
      'instagram_handle': instagramHandle,
      'show_email': showEmail,
      'video_url': videoUrl,
    };

    await _client
        .from('marketplace_listings')
        .update(payload)
        .eq('id', listing.id);

    await _syncPhotos(
      listingId: listing.id,
      retainedPhotos: retainedPhotos,
      newPhotos: newPhotos,
      previousPhotos: listing.photos,
    );
  }

  List<String> _normalizePaymentOptions(List<String> options) {
    final sanitized = <String>[];
    for (final option in options) {
      if (marketplacePaymentOptions.contains(option) &&
          !sanitized.contains(option)) {
        sanitized.add(option);
      }
    }
    if (sanitized.isEmpty) {
      sanitized.add('pix');
    }
    return sanitized;
  }

  Future<void> deleteListing(Listing listing) async {
    await _deletePhotos(listing.photos);
    await _client.from('marketplace_listings').delete().eq('id', listing.id);
  }

  Future<void> updateListingStatus({
    required String id,
    required String status,
  }) async {
    await _client
        .from('marketplace_listings')
        .update({'status': status}).eq('id', id);
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado.');
    }
    return userId;
  }

  Future<void> _syncPhotos({
    required String listingId,
    required List<ListingPhoto> retainedPhotos,
    required List<XFile> newPhotos,
    List<ListingPhoto> previousPhotos = const [],
  }) async {
    final uploaded = await _uploadNewPhotos(
      listingId: listingId,
      files: newPhotos,
      startingPosition: retainedPhotos.length,
    );

    final gallery = [
      ..._reindexPhotos(retainedPhotos),
      ..._reindexPhotos(uploaded, offset: retainedPhotos.length),
    ];

    await _client
        .from('marketplace_listings')
        .update({'photos': gallery.map((photo) => photo.toJson()).toList()})
        .eq('id', listingId);

    if (previousPhotos.isNotEmpty) {
      final removed = previousPhotos
          .where(
            (existing) =>
                !gallery.any((photo) => photo.id == existing.id) &&
                existing.isMarketplaceFile,
          )
          .where((photo) => photo.storagePath != null)
          .map((photo) => photo.storagePath!)
          .toList();

      if (removed.isNotEmpty) {
        await _client.storage.from(_bucket).remove(removed);
      }
    }
  }

  List<ListingPhoto> _reindexPhotos(
    List<ListingPhoto> photos, {
    int offset = 0,
  }) {
    final updated = <ListingPhoto>[];
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      updated.add(photo.copyWith(position: offset + index));
    }
    return updated;
  }

  Future<List<ListingPhoto>> _uploadNewPhotos({
    required String listingId,
    required List<XFile> files,
    required int startingPosition,
  }) async {
    if (files.isEmpty) return const [];

    final uploads = <ListingPhoto>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final uploaded = await _uploadPhoto(listingId: listingId, file: file);
      uploads.add(
        ListingPhoto(
          id: uploaded.id,
          publicUrl: uploaded.publicUrl,
          position: startingPosition + index,
          bucket: _bucket,
          storagePath: uploaded.path,
          source: 'upload',
        ),
      );
    }
    return uploads;
  }

  Future<_UploadedPhoto> _uploadPhoto({
    required String listingId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file);
    final fileName = '${_uuid.v4()}$extension';
    final storagePath = 'listings/$listingId/$fileName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _resolveContentType(extension),
          ),
        );

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(storagePath);
    return _UploadedPhoto(
      id: _uuid.v4(),
      path: storagePath,
      publicUrl: publicUrl,
    );
  }

  Future<void> _deletePhotos(List<ListingPhoto> photos) async {
    final removable = photos
        .where((photo) => photo.isMarketplaceFile)
        .map((photo) => photo.storagePath)
        .whereType<String>()
        .toList();

    if (removable.isEmpty) return;

    await _client.storage.from(_bucket).remove(removable);
  }

  String _resolveExtension(XFile file) {
    final original = p.extension(file.path);
    if (original.isNotEmpty) {
      return original.toLowerCase();
    }
    return '.jpg';
  }

  String _resolveContentType(String extension) {
    switch (extension.replaceFirst('.', '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

class _UploadedPhoto {
  _UploadedPhoto({
    required this.id,
    required this.path,
    required this.publicUrl,
  });

  final String id;
  final String path;
  final String publicUrl;
}

final listingsRepositoryProvider = Provider<ListingsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ListingsRepository(client);
});
