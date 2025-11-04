import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../domain/marina.dart';

class MarinaRepository {
  MarinaRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'marina_photos';
  static final _uuid = Uuid();

  Stream<List<Marina>> watchMarinas() {
    return _client
        .from('marinas')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((rows) => rows.map(Marina.fromMap).toList());
  }

  Future<List<Marina>> fetchMarinas() async {
    final data = await _client
        .from('marinas')
        .select()
        .order('name');
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(Marina.fromMap).toList();
  }

  Future<Marina?> fetchById(String id) async {
    final data = await _client
        .from('marinas')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Marina.fromMap(data);
  }

  Future<void> createMarina({
    required String name,
    String? whatsapp,
    String? instagram,
    String? address,
    required double latitude,
    required double longitude,
    XFile? photo,
  }) async {
    final userId = _client.auth.currentUser?.id;

    String? photoPath;
    String? photoUrl;
    if (photo != null) {
      final uploaded = await _uploadPhoto(photo);
      photoPath = uploaded.path;
      photoUrl = uploaded.publicUrl;
    }

    await _client.from('marinas').insert({
      'name': name,
      'whatsapp': whatsapp,
      'instagram': instagram,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': photoPath,
      'photo_url': photoUrl,
      'created_by': userId,
    });
  }

  Future<void> updateMarina({
    required String id,
    required String name,
    String? whatsapp,
    String? instagram,
    String? address,
    required double latitude,
    required double longitude,
    XFile? photo,
    String? currentPhotoPath,
    String? currentPhotoUrl,
  }) async {
    String? photoPath = currentPhotoPath;
    String? photoUrl = currentPhotoUrl;

    if (photo != null) {
      final uploaded = await _uploadPhoto(photo);
      photoPath = uploaded.path;
      photoUrl = uploaded.publicUrl;
      if (currentPhotoPath != null) {
        await _client.storage.from(_bucket).remove([currentPhotoPath]);
      }
    }

    await _client.from('marinas').update({
      'name': name,
      'whatsapp': whatsapp,
      'instagram': instagram,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': photoPath,
      'photo_url': photoUrl,
    }).eq('id', id);
  }

  Future<void> deleteMarina(Marina marina) async {
    await _client.from('marinas').delete().eq('id', marina.id);
    if (marina.photoPath != null && marina.photoPath!.isNotEmpty) {
      await _client.storage.from(_bucket).remove([marina.photoPath!]);
    }
  }

  Future<_UploadedPhoto> _uploadPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file);
    final fileName = '${_uuid.v4()}$extension';
    final storagePath = 'marinas/$fileName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _resolveContentType(extension),
          ),
        );

    final publicUrl =
        _client.storage.from(_bucket).getPublicUrl(storagePath);
    return _UploadedPhoto(path: storagePath, publicUrl: publicUrl);
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
  _UploadedPhoto({
    required this.path,
    required this.publicUrl,
  });

  final String path;
  final String publicUrl;
}

final marinaRepositoryProvider = Provider<MarinaRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MarinaRepository(client);
});
