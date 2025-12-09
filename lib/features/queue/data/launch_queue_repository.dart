import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../domain/launch_queue_entry.dart';
import '../domain/launch_queue_photo.dart';

class LaunchQueueRepository {
  LaunchQueueRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'boat_launch_queue_photos';
  static const _uuid = Uuid();
  static const _activeStatuses = ['pending', 'in_progress', 'in_water'];

  Future<Map<String, LaunchQueueEntry>> fetchLatestEntriesForBoats({
    required List<String> boatIds,
  }) async {
    if (boatIds.isEmpty) return {};

    final response = await _client
        .from('boat_launch_queue_view')
        .select()
        .inFilter('boat_id', boatIds)
        .order('requested_at', ascending: false);

    final entries = (response as List).cast<Map<String, dynamic>>().map(
      LaunchQueueEntry.fromMap,
    );

    final latestByBoat = <String, LaunchQueueEntry>{};
    for (final entry in entries) {
      if (entry.boatId.isEmpty) continue;
      latestByBoat.putIfAbsent(entry.boatId, () => entry);
      if (latestByBoat.length == boatIds.length) break;
    }

    return latestByBoat;
  }

  Future<LaunchQueueEntry?> fetchLatestEntryForBoat(String boatId) async {
    if (boatId.isEmpty) return null;

    final entries = await fetchLatestEntriesForBoats(boatIds: [boatId]);
    return entries[boatId];
  }

  Future<List<LaunchQueueEntry>> fetchEntries({
    String? marinaId,
    DateTime? fromDate,
  }) async {
    var query = _client.from('boat_launch_queue_view').select();

    if (marinaId != null && marinaId.isNotEmpty) {
      query = query.eq('marina_id', marinaId);
    }

    if (fromDate != null) {
      query = query.gte('requested_at', fromDate.toUtc().toIso8601String());
    }

    final response = await query.order('requested_at', ascending: true);

    final data = (response as List).cast<Map<String, dynamic>>();
    final baseEntries = data.map(LaunchQueueEntry.fromMap).toList();
    final photosByEntry = await _fetchQueuePhotos(baseEntries);
    final entries = baseEntries
        .map(
          (entry) => photosByEntry[entry.id] == null
              ? entry
              : entry.withQueuePhotos(photosByEntry[entry.id]!),
        )
        .toList();

    entries.sort((a, b) {
      int statusOrder(String status) {
        switch (status) {
          case 'in_progress':
            return 0;
          case 'pending':
            return 1;
          case 'in_water':
            return 2;
          case 'completed':
            return 3;
          case 'cancelled':
            return 4;
          default:
            return 5;
        }
      }

      final statusComparison = statusOrder(
        a.status,
      ).compareTo(statusOrder(b.status));
      if (statusComparison != 0) return statusComparison;

      final positionComparison = a.queuePosition.compareTo(b.queuePosition);
      if (positionComparison != 0) return positionComparison;

      final aReferenceTime = a.processedAt ?? a.requestedAt;
      final bReferenceTime = b.processedAt ?? b.requestedAt;
      return aReferenceTime.compareTo(bReferenceTime);
    });

    return entries;
  }

  Future<bool> hasActiveEntryForBoatOnDate({
    required String boatId,
    required DateTime referenceDate,
  }) async {
    if (boatId.isEmpty) return false;

    final dayStart = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final response = await _client
        .from('boat_launch_queue')
        .select('id')
        .eq('boat_id', boatId)
        .inFilter('status', _activeStatuses)
        .gte('requested_at', dayStart.toUtc().toIso8601String())
        .lt('requested_at', dayEnd.toUtc().toIso8601String())
        .limit(1);

    return (response as List).isNotEmpty;
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
    final hasGenericName =
        normalizedGenericName != null && normalizedGenericName.isNotEmpty;
    if (!hasBoat && !hasGenericName) {
      throw ArgumentError(
        'Informe uma embarcação ou uma descrição para a fila.',
      );
    }

    final payload = <String, dynamic>{'status': status};

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
    bool clearScheduledTransition = false,
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

    final shouldClearScheduled =
        clearScheduledTransition || (status != null && status != 'in_progress');

    if (shouldClearScheduled) {
      updatePayload['auto_transition_to'] = null;
      updatePayload['auto_transition_at'] = null;
      updatePayload['auto_transition_requested_by'] = null;
    }

    if (genericBoatName != null) {
      final normalized = genericBoatName.trim();
      updatePayload['generic_boat_name'] = normalized.isEmpty
          ? null
          : normalized;
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

    await _client
        .from('boat_launch_queue_photos')
        .insert(
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

  Future<void> scheduleTransition({
    required String entryId,
    required String targetStatus,
    required int delayMinutes,
  }) async {
    if (entryId.isEmpty) {
      throw ArgumentError('Informe o registro da fila.');
    }

    if (targetStatus != 'in_water' && targetStatus != 'completed') {
      throw ArgumentError('Status invalido para agendamento.');
    }

    if (delayMinutes <= 0) {
      throw ArgumentError('Informe um tempo valido em minutos.');
    }

    await _client.rpc('schedule_launch_queue_transition', params: {
      'entry_id': entryId,
      'target_status': targetStatus,
      'delay_minutes': delayMinutes,
    });
  }

  Future<Map<String, String>> _uploadPhoto({
    required String entryId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file);
    final storagePath = 'queue_entries/$entryId/${_uuid.v4()}$extension';

    await _client.storage
        .from(_bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _resolveContentType(extension),
          ),
        );

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(storagePath);
    return {'path': storagePath, 'publicUrl': publicUrl};
  }

  Future<Map<String, List<LaunchQueuePhoto>>> _fetchQueuePhotos(
    List<LaunchQueueEntry> entries,
  ) async {
    final entryIds = entries
        .map((entry) => entry.id)
        .where((id) => id.isNotEmpty)
        .toList();

    if (entryIds.isEmpty) return {};

    try {
      final response = await _client
          .from('boat_launch_queue_photos')
          .select()
          .inFilter('queue_entry_id', entryIds)
          .order('created_at', ascending: true);

      return _groupPhotosByEntry(response);
    } catch (_) {
      try {
        final response = await _client
            .from('boat_launch_queue_photos')
            .select()
            .inFilter('queue_entry_id', entryIds);
        return _groupPhotosByEntry(response);
      } catch (_) {
        return {};
      }
    }
  }

  Map<String, List<LaunchQueuePhoto>> _groupPhotosByEntry(dynamic response) {
    final data = (response as List).cast<Map<String, dynamic>>();
    final photosByEntry = <String, List<LaunchQueuePhoto>>{};

    for (final item in data) {
      final photo = LaunchQueuePhoto.fromMap(item);
      if (photo.queueEntryId.isEmpty) continue;
      photosByEntry.putIfAbsent(photo.queueEntryId, () => []).add(photo);
    }

    return photosByEntry.map(
      (key, value) => MapEntry(key, List<LaunchQueuePhoto>.unmodifiable(value)),
    );
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
