import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../domain/marina_wall_post.dart';

class MarinaWallRepository {
  MarinaWallRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'mural_photos';
  static final _uuid = Uuid();

  Stream<List<MarinaWallPost>> watchPosts({String? marinaId}) {
    final query =
        _client.from('marina_wall_posts_view').stream(primaryKey: ['id'])
          ..order('start_date', ascending: false)
          ..order('created_at', ascending: false);

    if (marinaId != null && marinaId.isNotEmpty) {
      query.eq('marina_id', marinaId);
    }

    return query.map(
      (rows) => rows.map((row) => MarinaWallPost.fromMap(row)).toList(),
    );
  }

  Future<MarinaWallPost?> fetchPostById(String id) async {
    if (id.isEmpty) return null;

    final response = await _client
        .from('marina_wall_posts_view')
        .select(
          'id,marina_id,marina_name,title,description,type,start_date,end_date,image_url,image_path,created_by,created_by_name,created_at,updated_at',
        )
        .eq('id', id)
        .maybeSingle();

    final Map<String, dynamic>? data = response;
    if (data == null) return null;
    return MarinaWallPost.fromMap(data);
  }

  Future<MuralPostCreationResult> createPost({
    required String marinaId,
    required String title,
    required String description,
    required String type,
    required DateTime startDate,
    required DateTime endDate,
    XFile? image,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedDescription = description.trim();

    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Informe o titulo da publicacao.');
    }

    if (!muralPostTypes.contains(type)) {
      throw ArgumentError('Tipo de publicacao invalido.');
    }

    if (endDate.isBefore(startDate)) {
      throw ArgumentError('Data final nao pode ser anterior a data inicial.');
    }

    String? imagePath;
    String? imageUrl;
    if (image != null) {
      final uploaded = await _uploadImage(marinaId, image);
      imagePath = uploaded.path;
      imageUrl = uploaded.publicUrl;
    }

    final payload = <String, dynamic>{
      'marina_id': marinaId,
      'title': trimmedTitle,
      'description': trimmedDescription.isEmpty ? null : trimmedDescription,
      'type': type,
      'start_date': _asDateValue(startDate),
      'end_date': _asDateValue(endDate),
      'image_path': imagePath,
      'image_url': imageUrl,
    };

    final Map<String, dynamic> inserted = await _client
        .from('marina_wall_posts')
        .insert(payload)
        .select(
          'id,marina_id,title,description,type,start_date,end_date,image_url,image_path,created_by,created_at,updated_at',
        )
        .single();

    final post = MarinaWallPost.fromMap(inserted);

    Map<String, dynamic>? pushResult;
    String? pushError;

    try {
      final response = await _client.functions.invoke(
        'notify_mural_publication',
        body: {
          'marina_id': marinaId,
          'post_id': post.id,
          'title': post.title,
          'type': post.type,
          'start_date': post.startDate.toIso8601String(),
          'end_date': post.endDate.toIso8601String(),
        },
      );
      if (response.data is Map<String, dynamic>) {
        pushResult = response.data as Map<String, dynamic>;
      }
    } catch (error, stackTrace) {
      debugPrint('Falha ao enviar push do mural: $error');
      debugPrint('$stackTrace');
      pushError = '$error';
    }

    return MuralPostCreationResult(
      post: post,
      pushResult: pushResult,
      pushError: pushError,
    );
  }

  Future<_UploadedImage> _uploadImage(String marinaId, XFile file) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file);
    final fileName = '${_uuid.v4()}$extension';
    final storagePath = 'marinas/$marinaId/$fileName';

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
    return _UploadedImage(path: storagePath, publicUrl: publicUrl);
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

  String _asDateValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _UploadedImage {
  _UploadedImage({required this.path, required this.publicUrl});

  final String path;
  final String publicUrl;
}

class MuralPostCreationResult {
  MuralPostCreationResult({
    required this.post,
    this.pushResult,
    this.pushError,
  });

  final MarinaWallPost post;
  final Map<String, dynamic>? pushResult;
  final String? pushError;

  bool get pushFailed => pushError != null && pushError!.isNotEmpty;
}

final marinaWallRepositoryProvider = Provider<MarinaWallRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MarinaWallRepository(client);
});
