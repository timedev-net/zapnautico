class BoatExpenseShare {
  BoatExpenseShare({
    this.id,
    required this.ownerId,
    required this.ownerName,
    this.ownerEmail,
    required this.shareAmount,
  });

  final String? id;
  final String ownerId;
  final String ownerName;
  final String? ownerEmail;
  final double shareAmount;

  BoatExpenseShare copyWith({
    String? id,
    String? ownerId,
    String? ownerName,
    String? ownerEmail,
    double? shareAmount,
  }) {
    return BoatExpenseShare(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      shareAmount: shareAmount ?? this.shareAmount,
    );
  }

  factory BoatExpenseShare.fromMap(Map<String, dynamic> data) {
    final rawAmount = data['share_amount'];
    final parsedAmount = rawAmount is num ? rawAmount.toDouble() : 0.0;
    return BoatExpenseShare(
      id: data['id']?.toString(),
      ownerId: data['owner_id']?.toString() ?? '',
      ownerName:
          data['owner_name']?.toString() ??
          data['owner_email']?.toString() ??
          'Proprietário',
      ownerEmail: data['owner_email']?.toString(),
      shareAmount: parsedAmount,
    );
  }

  Map<String, dynamic> toInsertPayload(String expenseId) {
    return {
      'expense_id': expenseId,
      'owner_id': ownerId,
      'share_amount': shareAmount,
      'owner_name_snapshot': ownerName,
      'owner_email_snapshot': ownerEmail,
    };
  }
}
