import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../domain/launch_queue_entry.dart';

class LaunchQueueRepository {
  LaunchQueueRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'boat_launch_queue_photos';
  static const _uuid = Uuid();

  Future<List<LaunchQueueEntry>> fetchEntries() async {
    final response = await _client
        .from('boat_launch_queue_view')
        .select()
        .order('queue_position', ascending: true);

    final data = (response as List).cast<Map<String, dynamic>>();
    final entries = data.map(LaunchQueueEntry.fromMap).toList();

    entries.sort((a, b) {
      final aInWater = a.status == 'in_water';
      final bInWater = b.status == 'in_water';
      if (aInWater != bInWater) return aInWater ? 1 : -1;

      final positionComparison = a.queuePosition.compareTo(b.queuePosition);
      if (positionComparison != 0) return positionComparison;

      return a.requestedAt.compareTo(b.requestedAt);
    });

    return entries;
  }

  Future<String> createEntry({
    String? marinaId,
    String? boatId,
    String? genericBoatName,
    String status = 'pending',
    List<XFile> photos = const [],
  }) async {
    final normalizedGenericName = genericBoatName?.trim();

    final hasBoat = boatId != null && boatId.isNotEmpty;
    final hasGenericName = normalizedGenericName != null &&
        normalizedGenericName.isNotEmpty;
    if (!hasBoat && !hasGenericName) {
      throw ArgumentError(
        'Informe uma embarcação ou uma descrição para a fila.',
      );
    }

    final payload = <String, dynamic>{
      'status': status,
    };

    if (marinaId != null && marinaId.isNotEmpty) {
      payload['marina_id'] = marinaId;
    }

    if (status != 'pending') {
      payload['processed_at'] = DateTime.now().toUtc().toIso8601String();
    }

    if (hasBoat) {
      payload['boat_id'] = boatId;
    }

    if (hasGenericName) {
      payload['generic_boat_name'] = normalizedGenericName;
    }

    final response = await _client
        .from('boat_launch_queue')
        .insert(payload)
        .select('id')
        .single();

    final entryId = response['id']?.toString();
    if (entryId == null || entryId.isEmpty) {
      throw StateError('NÇœo foi possÇðvel criar a entrada na fila.');
    }

    if (photos.isNotEmpty) {
      await _syncPhotos(entryId: entryId, newPhotos: photos);
    }

    return entryId;
  }

  Future<void> cancelRequest(String entryId) async {
    await _client.from('boat_launch_queue').delete().eq('id', entryId);
  }

  Future<void> updateEntry({
    required String entryId,
    String? marinaId,
    String? boatId,
    String? status,
    DateTime? processedAt,
    bool clearProcessedAt = false,
    String? genericBoatName,
    List<XFile> newPhotos = const [],
  }) async {
    final updatePayload = <String, dynamic>{};

    if (marinaId != null && marinaId.isNotEmpty) {
      updatePayload['marina_id'] = marinaId;
    } else if (marinaId != null && marinaId.isEmpty) {
      updatePayload['marina_id'] = null;
    }

    if (boatId != null) {
      updatePayload['boat_id'] = boatId.isEmpty ? null : boatId;
    }

    if (status != null) {
      updatePayload['status'] = status;
    }

    if (processedAt != null) {
      updatePayload['processed_at'] = processedAt.toUtc().toIso8601String();
    } else if (clearProcessedAt) {
      updatePayload['processed_at'] = null;
    }

    if (genericBoatName != null) {
      final normalized = genericBoatName.trim();
      updatePayload['generic_boat_name'] =
          normalized.isEmpty ? null : normalized;
    }

    if (updatePayload.isEmpty) {
      return;
    }

    await _client
        .from('boat_launch_queue')
        .update(updatePayload)
        .eq('id', entryId);

    if (newPhotos.isNotEmpty) {
      await _syncPhotos(entryId: entryId, newPhotos: newPhotos);
    }
  }

  Future<void> _syncPhotos({
    required String entryId,
    required List<XFile> newPhotos,
  }) async {
    if (newPhotos.isEmpty) return;

    final uploads = <Map<String, String>>[];
    for (final photo in newPhotos.take(5)) {
      final uploaded = await _uploadPhoto(entryId: entryId, file: photo);
      uploads.add(uploaded);
    }

    if (uploads.isEmpty) return;

    await _client.from('boat_launch_queue_photos').insert(
          uploads
              .map(
                (photo) => {
                  'queue_entry_id': entryId,
                  'storage_path': photo['path'],
                  'public_url': photo['publicUrl'],
                },
              )
              .toList(),
        );
  }

  Future<Map<String, String>> _uploadPhoto({
    required String entryId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file);
    final storagePath =
        'queue_entries/$entryId/${_uuid.v4()}$extension';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _resolveContentType(extension),
          ),
        );

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(storagePath);
    return {
      'path': storagePath,
      'publicUrl': publicUrl,
    };
  }

  String _resolveExtension(XFile file) {
    final extension = p.extension(file.name);
    if (extension.isEmpty) return '.jpg';
    return extension;
  }

  String _resolveContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

final launchQueueRepositoryProvider = Provider<LaunchQueueRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return LaunchQueueRepository(client);
});
