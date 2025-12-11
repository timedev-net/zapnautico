import 'launch_queue_photo.dart';

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
    this.processedAt,
    required this.queuePosition,
    this.fuelGallons,
    this.boatName,
    this.genericBoatName,
    this.visibleBoatName,
    this.visibleOwnerName,
    this.boatPhotoUrl,
    required this.isOwnBoat,
    required this.isMarinaUser,
    List<LaunchQueuePhoto> queuePhotos = const [],
  }) : queuePhotos = List.unmodifiable(queuePhotos);

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
  final DateTime? processedAt;
  final int queuePosition;
  final int? fuelGallons;
  final String? visibleBoatName;
  final String? visibleOwnerName;
  final String? boatPhotoUrl;
  final bool isOwnBoat;
  final bool isMarinaUser;
  final List<LaunchQueuePhoto> queuePhotos;

  bool get isGenericEntry => boatId.isEmpty;

  bool get hasBoatPhoto => boatPhotoUrl != null && boatPhotoUrl!.isNotEmpty;

  bool get hasQueuePhotos => queuePhotos.any((photo) => photo.hasUrl);

  bool get hasMarina => marinaId.isNotEmpty;

  bool get hasFuelRequest => fuelGallons != null && fuelGallons! > 0;

  LaunchQueuePhoto? get primaryQueuePhoto {
    for (final photo in queuePhotos) {
      if (photo.hasUrl) return photo;
    }
    return queuePhotos.isNotEmpty ? queuePhotos.first : null;
  }

  String? get queuePrimaryPhotoUrl => primaryQueuePhoto?.publicUrl;

  String get displayMarinaName =>
      hasMarina && marinaName.isNotEmpty ? marinaName : 'Sem marina associada';

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
    return 'Entrada genérica na fila';
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
      marinaName: (data['marina_name'] as String?)?.trim() ?? '',
      requestedBy: data['requested_by']?.toString() ?? '',
      requestedByName: data['requested_by_name'] as String? ?? '',
      requestedByEmail: data['requested_by_email'] as String?,
      status: data['status'] as String? ?? 'pending',
      requestedAt: requestedAt,
      processedAt: _parseNullableDateTime(data['processed_at']),
      queuePosition: queuePosition,
      fuelGallons: _parseNullableInt(data['fuel_gallons']),
      boatName: data['boat_name'] as String?,
      genericBoatName: data['generic_boat_name'] as String?,
      visibleBoatName: data['visible_boat_name'] as String?,
      visibleOwnerName: data['visible_owner_name'] as String?,
      boatPhotoUrl: data['boat_photo_url'] as String?,
      isOwnBoat: _parseBool(data['is_own_boat']),
      isMarinaUser: _parseBool(data['is_marina_user']),
      queuePhotos: const [],
    );
  }

  LaunchQueueEntry withQueuePhotos(List<LaunchQueuePhoto> photos) {
    return LaunchQueueEntry(
      id: id,
      boatId: boatId,
      marinaId: marinaId,
      marinaName: marinaName,
      requestedBy: requestedBy,
      requestedByName: requestedByName,
      requestedByEmail: requestedByEmail,
      status: status,
      requestedAt: requestedAt,
      processedAt: processedAt,
      queuePosition: queuePosition,
      fuelGallons: fuelGallons,
      boatName: boatName,
      genericBoatName: genericBoatName,
      visibleBoatName: visibleBoatName,
      visibleOwnerName: visibleOwnerName,
      boatPhotoUrl: boatPhotoUrl,
      isOwnBoat: isOwnBoat,
      isMarinaUser: isMarinaUser,
      queuePhotos: photos,
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

  static DateTime? _parseNullableDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
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
