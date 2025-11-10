import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_providers.dart';
import '../../boats/domain/boat.dart';
import '../domain/boat_expense.dart';
import '../domain/boat_expense_category.dart';
import '../domain/boat_expense_share.dart';

class BoatFinancialRepository {
  BoatFinancialRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'boat_expense_files';
  static final _uuid = Uuid();
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  Future<List<BoatExpense>> fetchExpenses({String? boatId}) async {
    var query = _client.from('boat_expenses_detailed').select();
    if (boatId != null) {
      query = query.eq('boat_id', boatId);
    }

    final response = await query
        .order('incurred_on', ascending: false)
        .order('created_at', ascending: false);

    final expenses = (response as List)
        .cast<Map<String, dynamic>>()
        .map(BoatExpense.fromMap)
        .toList();

    return Future.wait(
      expenses.map((expense) async {
        final photoUrl = await _createSignedUrl(expense.receiptPhotoPath);
        final fileUrl = await _createSignedUrl(expense.receiptFilePath);
        return expense.copyWith(
          receiptPhotoUrl: photoUrl,
          receiptFileUrl: fileUrl,
        );
      }),
    );
  }

  Future<String> createExpense({
    required Boat boat,
    required BoatExpenseCategory category,
    required double amount,
    required DateTime incurredOn,
    String? description,
    bool divisionEnabled = false,
    bool divisionCompleted = false,
    List<BoatExpenseShare> shares = const [],
    XFile? photo,
    PlatformFile? attachment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado.');
    }

    final hasShares = divisionEnabled && shares.isNotEmpty;
    final payload = {
      'boat_id': boat.id,
      'category': category.value,
      'amount': amount,
      'incurred_on': _dateFormat.format(incurredOn),
      'description': description,
      'division_configured': hasShares,
      'division_completed': hasShares && divisionCompleted,
      'created_by': userId,
    };

    final insertResponse = await _client
        .from('boat_expenses')
        .insert(payload)
        .select('id, receipt_photo_path, receipt_file_path')
        .single();

    final expenseId = insertResponse['id']?.toString();
    if (expenseId == null || expenseId.isEmpty) {
      throw StateError('Não foi possível salvar a despesa.');
    }

    await _syncShares(expenseId: expenseId, shares: hasShares ? shares : []);

    final updatedFields = <String, dynamic>{};
    if (photo != null) {
      final uploaded = await _uploadXFile(
        boatId: boat.id,
        expenseId: expenseId,
        file: photo,
      );
      updatedFields.addAll({'receipt_photo_path': uploaded.path});
    }

    if (attachment != null) {
      final uploaded = await _uploadPlatformFile(
        boatId: boat.id,
        expenseId: expenseId,
        file: attachment,
      );
      updatedFields.addAll({
        'receipt_file_path': uploaded.path,
        'receipt_file_name': attachment.name,
        'receipt_file_type': uploaded.contentType,
      });
    }

    if (updatedFields.isNotEmpty) {
      await _client
          .from('boat_expenses')
          .update(updatedFields)
          .eq('id', expenseId);
    }

    return expenseId;
  }

  Future<void> updateExpense({
    required Boat boat,
    required BoatExpense expense,
    required BoatExpenseCategory category,
    required double amount,
    required DateTime incurredOn,
    String? description,
    bool divisionEnabled = false,
    bool divisionCompleted = false,
    List<BoatExpenseShare> shares = const [],
    XFile? newPhoto,
    PlatformFile? newAttachment,
    bool removePhoto = false,
    bool removeAttachment = false,
  }) async {
    final hasShares = divisionEnabled && shares.isNotEmpty;
    final payload = {
      'category': category.value,
      'amount': amount,
      'incurred_on': _dateFormat.format(incurredOn),
      'description': description,
      'division_configured': hasShares,
      'division_completed': hasShares && divisionCompleted,
    };

    await _client.from('boat_expenses').update(payload).eq('id', expense.id);
    await _syncShares(
      expenseId: expense.id,
      shares: hasShares ? shares : const [],
    );

    final updatedFields = <String, dynamic>{};
    if ((removePhoto || newPhoto != null) && expense.receiptPhotoPath != null) {
      await _deleteStorageObject(expense.receiptPhotoPath!);
      updatedFields['receipt_photo_path'] = null;
    }
    if ((removeAttachment || newAttachment != null) &&
        expense.receiptFilePath != null) {
      await _deleteStorageObject(expense.receiptFilePath!);
      updatedFields['receipt_file_path'] = null;
      updatedFields['receipt_file_name'] = null;
      updatedFields['receipt_file_type'] = null;
    }

    if (newPhoto != null) {
      final uploaded = await _uploadXFile(
        boatId: boat.id,
        expenseId: expense.id,
        file: newPhoto,
      );
      updatedFields['receipt_photo_path'] = uploaded.path;
    }

    if (newAttachment != null) {
      final uploaded = await _uploadPlatformFile(
        boatId: boat.id,
        expenseId: expense.id,
        file: newAttachment,
      );
      updatedFields['receipt_file_path'] = uploaded.path;
      updatedFields['receipt_file_name'] = newAttachment.name;
      updatedFields['receipt_file_type'] = uploaded.contentType;
    }

    if (updatedFields.isNotEmpty) {
      await _client
          .from('boat_expenses')
          .update(updatedFields)
          .eq('id', expense.id);
    }
  }

  Future<void> deleteExpense(BoatExpense expense) async {
    if (expense.receiptPhotoPath != null) {
      await _deleteStorageObject(expense.receiptPhotoPath!);
    }
    if (expense.receiptFilePath != null) {
      await _deleteStorageObject(expense.receiptFilePath!);
    }
    await _client.from('boat_expenses').delete().eq('id', expense.id);
  }

  Future<void> _syncShares({
    required String expenseId,
    required List<BoatExpenseShare> shares,
  }) async {
    await _client
        .from('boat_expense_shares')
        .delete()
        .eq('expense_id', expenseId);
    if (shares.isEmpty) {
      return;
    }

    final payload = shares
        .map((share) => share.toInsertPayload(expenseId))
        .toList(growable: false);
    await _client.from('boat_expense_shares').insert(payload);
  }

  Future<_UploadedStorageFile> _uploadXFile({
    required String boatId,
    required String expenseId,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file.name);
    final contentType = _resolveContentType(extension);
    final path = _buildStoragePath(
      boatId: boatId,
      expenseId: expenseId,
      extension: extension,
    );

    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return _UploadedStorageFile(path: path, contentType: contentType);
  }

  Future<_UploadedStorageFile> _uploadPlatformFile({
    required String boatId,
    required String expenseId,
    required PlatformFile file,
  }) async {
    final bytes = await _readPlatformFile(file);
    final extension = file.extension != null && file.extension!.isNotEmpty
        ? '.${file.extension!.replaceAll('.', '')}'
        : p.extension(file.name);
    final normalizedExtension = extension.isEmpty ? '.dat' : extension;
    final contentType = _resolveMimeType(normalizedExtension);
    final path = _buildStoragePath(
      boatId: boatId,
      expenseId: expenseId,
      extension: normalizedExtension,
    );

    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return _UploadedStorageFile(path: path, contentType: contentType);
  }

  Future<void> _deleteStorageObject(String path) async {
    try {
      await _client.storage.from(_bucket).remove([path]);
    } catch (_) {
      // Ignora remoção silenciosamente para evitar bloquear fluxo do usuário.
    }
  }

  Future<String?> _createSignedUrl(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final response = await _client.storage
          .from(_bucket)
          .createSignedUrl(path, 60 * 60 * 6); // 6 horas
      return response;
    } catch (_) {
      return null;
    }
  }

  String _buildStoragePath({
    required String boatId,
    required String expenseId,
    required String extension,
  }) {
    final normalizedExtension = extension.startsWith('.')
        ? extension
        : '.$extension';
    return 'boats/$boatId/expenses/$expenseId/${_uuid.v4()}$normalizedExtension';
  }

  String _resolveExtension(String filename) {
    final extension = p.extension(filename);
    if (extension.isNotEmpty) {
      return extension.toLowerCase();
    }
    return '.jpg';
  }

  String _resolveContentType(String extension) {
    switch (extension.replaceAll('.', '').toLowerCase()) {
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

  String _resolveMimeType(String extension) {
    final normalized = extension.replaceAll('.', '').toLowerCase();
    switch (normalized) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }

  Future<Uint8List> _readPlatformFile(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes!;
    }
    if (!kIsWeb && file.path != null) {
      final crossFile = XFile(file.path!);
      return crossFile.readAsBytes();
    }
    throw StateError('Não foi possível ler o arquivo selecionado.');
  }
}

class _UploadedStorageFile {
  _UploadedStorageFile({required this.path, required this.contentType});

  final String path;
  final String contentType;
}

final boatFinancialRepositoryProvider = Provider<BoatFinancialRepository>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return BoatFinancialRepository(client);
});
