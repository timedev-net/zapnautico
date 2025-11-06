class LaunchQueueEntry {
  LaunchQueueEntry({
    required this.id,
    required this.boatId,
    required this.marinaId,
    required this.marinaName,
    required this.requestedBy,
    required this.requestedByName,
    required this.requestedByEmail,
    required this.status,
    required this.requestedAt,
    required this.queuePosition,
    this.boatName,
    this.genericBoatName,
    this.visibleBoatName,
    this.visibleOwnerName,
    required this.isOwnBoat,
    required this.isMarinaUser,
  });

  final String id;
  final String boatId;
  final String? boatName;
  final String? genericBoatName;
  final String marinaId;
  final String marinaName;
  final String requestedBy;
  final String requestedByName;
  final String? requestedByEmail;
  final String status;
  final DateTime requestedAt;
  final int queuePosition;
  final String? visibleBoatName;
  final String? visibleOwnerName;
  final bool isOwnBoat;
  final bool isMarinaUser;

  bool get isGenericEntry =>
      boatId.isEmpty && (genericBoatName?.isNotEmpty ?? false);

  bool get userCanSeeDetails => isOwnBoat || isMarinaUser;

  String get displayBoatName {
    if (visibleBoatName != null && visibleBoatName!.isNotEmpty) {
      return visibleBoatName!;
    }
    if (genericBoatName != null && genericBoatName!.isNotEmpty) {
      return genericBoatName!;
    }
    if ((isOwnBoat || isMarinaUser) &&
        boatName != null &&
        boatName!.isNotEmpty) {
      return boatName!;
    }
    return 'Embarcação na fila';
  }

  factory LaunchQueueEntry.fromMap(Map<String, dynamic> data) {
    final requestedAtValue = data['requested_at'];
    final requestedAt = _parseDateTime(requestedAtValue);

    final positionValue = data['queue_position'];
    final queuePosition = positionValue is int
        ? positionValue
        : (positionValue is num ? positionValue.toInt() : 0);

    final boatIdValue = data['boat_id'];
    final boatId = boatIdValue == null ? '' : boatIdValue.toString();

    return LaunchQueueEntry(
      id: data['id']?.toString() ?? '',
      boatId: boatId,
      marinaId: data['marina_id']?.toString() ?? '',
      marinaName: data['marina_name'] as String? ?? 'Marina',
      requestedBy: data['requested_by']?.toString() ?? '',
      requestedByName: data['requested_by_name'] as String? ?? '',
      requestedByEmail: data['requested_by_email'] as String?,
      status: data['status'] as String? ?? 'pending',
      requestedAt: requestedAt,
      queuePosition: queuePosition,
      boatName: data['boat_name'] as String?,
      genericBoatName: data['generic_boat_name'] as String?,
      visibleBoatName: data['visible_boat_name'] as String?,
      visibleOwnerName: data['visible_owner_name'] as String?,
      isOwnBoat: _parseBool(data['is_own_boat']),
      isMarinaUser: _parseBool(data['is_marina_user']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }
}
