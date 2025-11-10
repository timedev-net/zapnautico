import 'boat_expense_category.dart';
import 'boat_expense_share.dart';

class BoatExpense {
  BoatExpense({
    required this.id,
    required this.boatId,
    required this.boatName,
    required this.category,
    required this.amount,
    required this.incurredOn,
    this.description,
    required this.divisionConfigured,
    required this.divisionCompleted,
    required this.createdBy,
    this.createdByName,
    this.createdByEmail,
    this.receiptPhotoPath,
    this.receiptPhotoUrl,
    this.receiptFilePath,
    this.receiptFileUrl,
    this.receiptFileName,
    this.receiptFileType,
    required this.createdAt,
    required this.updatedAt,
    required this.shares,
  });

  final String id;
  final String boatId;
  final String boatName;
  final BoatExpenseCategory category;
  final double amount;
  final DateTime incurredOn;
  final String? description;
  final bool divisionConfigured;
  final bool divisionCompleted;
  final String createdBy;
  final String? createdByName;
  final String? createdByEmail;
  final String? receiptPhotoPath;
  final String? receiptPhotoUrl;
  final String? receiptFilePath;
  final String? receiptFileUrl;
  final String? receiptFileName;
  final String? receiptFileType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<BoatExpenseShare> shares;

  bool get hasDivision => divisionConfigured && shares.isNotEmpty;

  bool canEdit(String? userId) {
    if (userId == null || userId.isEmpty) {
      return false;
    }
    return userId == createdBy;
  }

  BoatExpense copyWith({
    String? id,
    String? boatId,
    String? boatName,
    BoatExpenseCategory? category,
    double? amount,
    DateTime? incurredOn,
    String? description,
    bool? divisionConfigured,
    bool? divisionCompleted,
    String? createdBy,
    String? createdByName,
    String? createdByEmail,
    String? receiptPhotoPath,
    String? receiptPhotoUrl,
    String? receiptFilePath,
    String? receiptFileUrl,
    String? receiptFileName,
    String? receiptFileType,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<BoatExpenseShare>? shares,
  }) {
    return BoatExpense(
      id: id ?? this.id,
      boatId: boatId ?? this.boatId,
      boatName: boatName ?? this.boatName,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      incurredOn: incurredOn ?? this.incurredOn,
      description: description ?? this.description,
      divisionConfigured: divisionConfigured ?? this.divisionConfigured,
      divisionCompleted: divisionCompleted ?? this.divisionCompleted,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdByEmail: createdByEmail ?? this.createdByEmail,
      receiptPhotoPath: receiptPhotoPath ?? this.receiptPhotoPath,
      receiptPhotoUrl: receiptPhotoUrl ?? this.receiptPhotoUrl,
      receiptFilePath: receiptFilePath ?? this.receiptFilePath,
      receiptFileUrl: receiptFileUrl ?? this.receiptFileUrl,
      receiptFileName: receiptFileName ?? this.receiptFileName,
      receiptFileType: receiptFileType ?? this.receiptFileType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shares: shares ?? this.shares,
    );
  }

  factory BoatExpense.fromMap(Map<String, dynamic> data) {
    final rawAmount = data['amount'];
    final parsedAmount = rawAmount is num ? rawAmount.toDouble() : 0.0;
    final rawShares = data['shares'];
    final shareList = <BoatExpenseShare>[];
    if (rawShares is List) {
      for (final share in rawShares) {
        if (share is Map<String, dynamic>) {
          shareList.add(BoatExpenseShare.fromMap(share));
        } else if (share is Map) {
          shareList.add(
            BoatExpenseShare.fromMap(
              share.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }

    return BoatExpense(
      id: data['id']?.toString() ?? '',
      boatId: data['boat_id']?.toString() ?? '',
      boatName: data['boat_name']?.toString() ?? 'Embarcação',
      category: BoatExpenseCategory.fromValue(data['category']?.toString()),
      amount: parsedAmount,
      incurredOn: DateTime.parse(data['incurred_on'] as String),
      description: data['description'] as String?,
      divisionConfigured: data['division_configured'] as bool? ?? false,
      divisionCompleted: data['division_completed'] as bool? ?? false,
      createdBy: data['created_by']?.toString() ?? '',
      createdByName: data['created_by_name'] as String?,
      createdByEmail: data['created_by_email'] as String?,
      receiptPhotoPath: data['receipt_photo_path'] as String?,
      receiptPhotoUrl: data['receipt_photo_url'] as String?,
      receiptFilePath: data['receipt_file_path'] as String?,
      receiptFileUrl: data['receipt_file_url'] as String?,
      receiptFileName: data['receipt_file_name'] as String?,
      receiptFileType: data['receipt_file_type'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
      shares: List.unmodifiable(shareList),
    );
  }
}
