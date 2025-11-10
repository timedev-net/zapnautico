import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../domain/boat.dart';
import '../domain/boat_enums.dart';
import '../domain/boat_photo.dart';
import '../domain/owner_summary.dart';

class BoatRepository {
  BoatRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'boat_photos';
  static final _uuid = Uuid();

  Future<List<Boat>> fetchBoats({String? marinaId, String? ownerId}) async {
    var query = _client.from('boats_detailed').select();

    if (marinaId != null && marinaId.isNotEmpty) {
      query = query.eq('marina_id', marinaId);
    }

    if (ownerId != null && ownerId.isNotEmpty) {
      query = query.or(
        'primary_owner_id.eq.$ownerId,co_owner_ids.cs.{$ownerId}',
      );
    }

    final response = await query.order('name', ascending: true);
    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(Boat.fromMap).toList();
  }

  Future<Boat?> fetchBoatById(String id) async {
    final response = await _client
        .from('boats_detailed')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return Boat.fromMap(response);
  }

  Future<OwnerSummary?> findOwnerByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    final response = await _client.rpc(
      'find_proprietario_by_email',
      params: {'search_email': normalized},
    );

    if (response == null) {
      return null;
    }

    if (response is List && response.isEmpty) {
      return null;
    }

    if (response is List) {
      final item = response.first as Map<String, dynamic>;
      return OwnerSummary.fromMap(item);
    }

    if (response is Map<String, dynamic>) {
      return OwnerSummary.fromMap(response);
    }

    return null;
  }

  Future<String> createBoat({
    required String name,
    required BoatType boatType,
    String? registrationNumber,
    required int fabricationYear,
    required BoatPropulsionType propulsionType,
    int? engineCount,
    String? engineBrand,
    String? engineModel,
    int? engineYear,
    String? enginePower,
    required BoatUsageType usageType,
    required BoatSize boatSize,
    String? description,
    String? trailerPlate,
    String? marinaId,
    List<String> coOwnerIds = const [],
    List<XFile> newPhotos = const [],
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado.');
    }

    if (newPhotos.length > 5) {
      throw StateError('É permitido anexar no máximo 5 fotos.');
    }

    final payload = _serializeBoatPayload(
      name: name,
      boatType: boatType,
      registrationNumber: registrationNumber,
      fabricationYear: fabricationYear,
      propulsionType: propulsionType,
      engineCount: engineCount,
      engineBrand: engineBrand,
      engineModel: engineModel,
      engineYear: engineYear,
      enginePower: enginePower,
      usageType: usageType,
      boatSize: boatSize,
      description: description,
      trailerPlate: trailerPlate,
      marinaId: marinaId,
      primaryOwnerId: userId,
      createdBy: userId,
    );

    final insertResponse = await _client
        .from('boats')
        .insert(payload)
        .select('id')
        .single();

    final boatId = insertResponse['id']?.toString();
    if (boatId == null || boatId.isEmpty) {
      throw StateError('Falha ao criar embarcação.');
    }

    await _syncNewPhotos(
      boatId: boatId,
      startingPosition: 0,
      photos: newPhotos,
    );

    await _syncCoOwners(boatId: boatId, desiredCoOwners: coOwnerIds);

    return boatId;
  }

  Future<void> updateBoat({
    required String boatId,
    required String name,
    required BoatType boatType,
    String? registrationNumber,
    required int fabricationYear,
    required BoatPropulsionType propulsionType,
    int? engineCount,
    String? engineBrand,
    String? engineModel,
    int? engineYear,
    String? enginePower,
    required BoatUsageType usageType,
    required BoatSize boatSize,
    String? description,
    String? trailerPlate,
    String? marinaId,
    List<String> coOwnerIds = const [],
    required List<BoatPhoto> retainedPhotos,
    required List<BoatPhoto> removedPhotos,
    List<XFile> newPhotos = const [],
  }) async {
    if (retainedPhotos.length + newPhotos.length > 5) {
      throw StateError('É permitido manter no máximo 5 fotos.');
    }

    final payload = _serializeBoatPayload(
      name: name,
      boatType: boatType,
      registrationNumber: registrationNumber,
      fabricationYear: fabricationYear,
      propulsionType: propulsionType,
      engineCount: engineCount,
      engineBrand: engineBrand,
      engineModel: engineModel,
      engineYear: engineYear,
      enginePower: enginePower,
      usageType: usageType,
      boatSize: boatSize,
      description: description,
      trailerPlate: trailerPlate,
      marinaId: marinaId,
    );

    await _client.from('boats').update(payload).eq('id', boatId);

    if (removedPhotos.isNotEmpty) {
      await _removePhotos(removedPhotos);
    }

    await _reorderExistingPhotos(boatId: boatId, photos: retainedPhotos);

    if (newPhotos.isNotEmpty) {
      await _syncNewPhotos(
        boatId: boatId,
        startingPosition: retainedPhotos.length,
        photos: newPhotos,
      );
    }

    await _syncCoOwners(boatId: boatId, desiredCoOwners: coOwnerIds);
  }

  Future<void> deleteBoat(Boat boat) async {
    if (boat.photos.isNotEmpty) {
      await _client.storage
          .from(_bucket)
          .remove(boat.photos.map((photo) => photo.storagePath).toList());
    }
    await _client.from('boats').delete().eq('id', boat.id);
  }

  Map<String, dynamic> _serializeBoatPayload({
    required String name,
    required BoatType boatType,
    String? registrationNumber,
    required int fabricationYear,
    required BoatPropulsionType propulsionType,
    int? engineCount,
    String? engineBrand,
    String? engineModel,
    int? engineYear,
    String? enginePower,
    required BoatUsageType usageType,
    required BoatSize boatSize,
    String? description,
    String? trailerPlate,
    String? marinaId,
    String? primaryOwnerId,
    String? createdBy,
  }) {
    return {
      'name': name,
      'boat_type': boatType.value,
      'registration_number': registrationNumber?.isEmpty == true
          ? null
          : registrationNumber,
      'fabrication_year': fabricationYear,
      'propulsion_type': propulsionType.value,
      'engine_count': propulsionType.requiresEngineDetails ? engineCount : null,
      'engine_brand': propulsionType.requiresEngineDetails ? engineBrand : null,
      'engine_model': propulsionType.requiresEngineDetails ? engineModel : null,
      'engine_year': propulsionType.requiresEngineDetails ? engineYear : null,
      'engine_power': propulsionType.requiresEngineDetails ? enginePower : null,
      'usage_type': usageType.value,
      'boat_size': boatSize.value,
      'description': description?.isEmpty == true ? null : description,
      'trailer_plate': trailerPlate?.isEmpty == true ? null : trailerPlate,
      'marina_id': marinaId?.isEmpty == true ? null : marinaId,
      if (primaryOwnerId != null) 'primary_owner_id': primaryOwnerId,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  Future<void> _syncNewPhotos({
    required String boatId,
    required int startingPosition,
    required List<XFile> photos,
  }) async {
    if (photos.isEmpty) return;

    final uploads = <Future<void>>[];
    for (var i = 0; i < photos.length; i++) {
      final position = startingPosition + i;
      final file = photos[i];
      uploads.add(
        _uploadAndRegisterPhoto(boatId: boatId, file: file, position: position),
      );
    }
    await Future.wait(uploads);
  }

  Future<void> _uploadAndRegisterPhoto({
    required String boatId,
    required XFile file,
    required int position,
  }) async {
    final uploaded = await _uploadPhoto(boatId: boatId, file: file);
    await _client.from('boat_photos').insert({
      'boat_id': boatId,
      'storage_path': uploaded.path,
      'public_url': uploaded.publicUrl,
      'position': position,
    });
  }

  Future<_UploadedPhoto> _uploadPhoto({
    required String boatId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file);
    final fileName = '${_uuid.v4()}$extension';
    final storagePath = 'boats/$boatId/$fileName';

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
    return _UploadedPhoto(path: storagePath, publicUrl: publicUrl);
  }

  Future<void> _removePhotos(List<BoatPhoto> photos) async {
    if (photos.isEmpty) return;
    for (final photo in photos) {
      await _client.from('boat_photos').delete().eq('id', photo.id);
    }

    final paths = photos.map((photo) => photo.storagePath).toList();
    await _client.storage.from(_bucket).remove(paths);
  }

  Future<void> _reorderExistingPhotos({
    required String boatId,
    required List<BoatPhoto> photos,
  }) async {
    if (photos.isEmpty) return;

    final updates = <Future<void>>[];
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      if (photo.position == index) continue;
      updates.add(
        _client
            .from('boat_photos')
            .update({'position': index})
            .eq('id', photo.id)
            .eq('boat_id', boatId),
      );
    }
    if (updates.isNotEmpty) {
      await Future.wait(updates);
    }
  }

  Future<void> _syncCoOwners({
    required String boatId,
    required List<String> desiredCoOwners,
  }) async {
    final cleaned = desiredCoOwners
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final existingResponse = await _client
        .from('boat_coowners')
        .select('id,user_id')
        .eq('boat_id', boatId) as List<dynamic>?;

    final existing = (existingResponse ?? const <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(
          (row) =>
              (row['user_id']?.toString() ?? '', row['id']?.toString() ?? ''),
        )
        .toList();

    final existingMap = <String, String>{
      for (final entry in existing)
        if (entry.$1.isNotEmpty && entry.$2.isNotEmpty) entry.$1: entry.$2,
    };

    final toAdd = cleaned.difference(existingMap.keys.toSet());
    final toRemove = existingMap.keys
        .where((userId) => !cleaned.contains(userId))
        .map((userId) => existingMap[userId]!)
        .toList();

    final currentUserId = _client.auth.currentUser?.id;

    if (toAdd.isNotEmpty) {
      await _client.from('boat_coowners').insert([
        for (final userId in toAdd)
          {
            'boat_id': boatId,
            'user_id': userId,
            if (currentUserId != null) 'created_by': currentUserId,
          },
      ]);
    }

    for (final id in toRemove) {
      await _client.from('boat_coowners').delete().eq('id', id);
    }
  }

  String _resolveExtension(XFile file) {
    final original = p.extension(file.path);
    if (original.isNotEmpty) {
      return original.toLowerCase();
    }
    return '.jpg';
  }

  String _resolveContentType(String extension) {
    switch (extension.replaceFirst('.', '')) {
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
  _UploadedPhoto({required this.path, required this.publicUrl});

  final String path;
  final String publicUrl;
}

final boatRepositoryProvider = Provider<BoatRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return BoatRepository(client);
});
