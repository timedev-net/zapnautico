class Quota {
  Quota({
    required this.id,
    required this.boatName,
    required this.totalSlots,
    required this.reservedSlots,
    required this.marina,
    required this.status,
    this.nextDeparture,
    this.notes,
  });

  final String id;
  final String boatName;
  final int totalSlots;
  final int reservedSlots;
  final String marina;
  final String status;
  final DateTime? nextDeparture;
  final String? notes;

  int get availableSlots => totalSlots - reservedSlots;

  factory Quota.fromMap(Map<String, dynamic> data) {
    return Quota(
      id: data['id']?.toString() ?? '',
      boatName: data['boat_name'] as String? ?? 'Embarcação',
      totalSlots: data['total_slots'] as int? ?? 0,
      reservedSlots: data['reserved_slots'] as int? ?? 0,
      marina: data['marina'] as String? ?? '',
      status: data['status'] as String? ?? 'indefinido',
      nextDeparture: data['next_departure'] != null
          ? DateTime.tryParse(data['next_departure'] as String)
          : null,
      notes: data['notes'] as String?,
    );
  }
}

