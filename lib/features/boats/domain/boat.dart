import 'boat_co_owner.dart';
import 'boat_enums.dart';
import 'boat_photo.dart';

class Boat {
  Boat({
    required this.id,
    required this.name,
    required this.boatType,
    this.registrationNumber,
    required this.fabricationYear,
    required this.propulsionType,
    this.engineCount,
    this.engineBrand,
    this.engineModel,
    this.engineYear,
    this.enginePower,
    required this.usageType,
    required this.size,
    this.description,
    this.trailerPlate,
    this.marinaId,
    this.marinaName,
    required this.primaryOwnerId,
    this.primaryOwnerName,
    this.primaryOwnerEmail,
    required this.coOwners,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.photos,
  });

  final String id;
  final String name;
  final BoatType boatType;
  final String? registrationNumber;
  final int fabricationYear;
  final BoatPropulsionType propulsionType;
  final int? engineCount;
  final String? engineBrand;
  final String? engineModel;
  final int? engineYear;
  final String? enginePower;
  final BoatUsageType usageType;
  final BoatSize size;
  final String? description;
  final String? trailerPlate;
  final String? marinaId;
  final String? marinaName;
  final String primaryOwnerId;
  final String? primaryOwnerName;
  final String? primaryOwnerEmail;
  final List<BoatCoOwner> coOwners;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<BoatPhoto> photos;

  bool get hasEngineDetails => propulsionType.requiresEngineDetails;

  bool canEdit(String? userId) {
    if (userId == null || userId.isEmpty) {
      return false;
    }
    if (userId == primaryOwnerId) {
      return true;
    }
    for (final owner in coOwners) {
      if (owner.userId == userId) {
        return true;
      }
    }
    return false;
  }

  factory Boat.fromMap(Map<String, dynamic> data) {
    final boatTypeValue = data['boat_type'] as String?;
    final propulsionValue = data['propulsion_type'] as String?;
    final usageValue = data['usage_type'] as String?;
    final sizeValue = data['boat_size'] as String?;

    final photoData = data['photos'];
    final photos = <BoatPhoto>[];
    if (photoData is List) {
      for (final item in photoData) {
        if (item is Map<String, dynamic>) {
          photos.add(BoatPhoto.fromMap(item));
        } else if (item is Map) {
          photos.add(
            BoatPhoto.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
      photos.sort((a, b) => a.position.compareTo(b.position));
    }

    final coOwnerData = data['co_owners'];
    final coOwners = <BoatCoOwner>[];
    if (coOwnerData is List) {
      for (final item in coOwnerData) {
        if (item is Map<String, dynamic>) {
          if ((item['user_id']?.toString() ?? '').isEmpty) continue;
          coOwners.add(BoatCoOwner.fromMap(item));
        } else if (item is Map) {
          final mapped = item.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          if ((mapped['user_id']?.toString() ?? '').isEmpty) continue;
          coOwners.add(BoatCoOwner.fromMap(mapped));
        }
      }
    }

    return Boat(
      id: data['id']?.toString() ?? '',
      name: data['name'] as String? ?? 'Embarcação',
      boatType: BoatType.fromValue(boatTypeValue),
      registrationNumber: data['registration_number'] as String?,
      fabricationYear: (data['fabrication_year'] as num?)?.toInt() ?? 0,
      propulsionType: BoatPropulsionType.fromValue(propulsionValue),
      engineCount: data['engine_count'] != null
          ? (data['engine_count'] as num?)?.toInt()
          : null,
      engineBrand: data['engine_brand'] as String?,
      engineModel: data['engine_model'] as String?,
      engineYear: data['engine_year'] != null
          ? (data['engine_year'] as num?)?.toInt()
          : null,
      enginePower: data['engine_power'] as String?,
      usageType: BoatUsageType.fromValue(usageValue),
      size: BoatSize.fromValue(sizeValue),
      description: data['description'] as String?,
      trailerPlate: data['trailer_plate'] as String?,
      marinaId: data['marina_id']?.toString(),
      marinaName: data['marina_name'] as String?,
      primaryOwnerId: data['primary_owner_id']?.toString() ?? '',
      primaryOwnerName: data['primary_owner_name'] as String?,
      primaryOwnerEmail: data['primary_owner_email'] as String?,
      coOwners: coOwners,
      createdBy: data['created_by']?.toString() ?? '',
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
      photos: photos,
    );
  }
}
