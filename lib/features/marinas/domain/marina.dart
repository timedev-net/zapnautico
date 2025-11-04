class Marina {
  Marina({
    required this.id,
    required this.name,
    this.whatsapp,
    this.instagram,
    this.address,
    required this.latitude,
    required this.longitude,
    this.photoUrl,
    this.photoPath,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? whatsapp;
  final String? instagram;
  final String? address;
  final double latitude;
  final double longitude;
  final String? photoUrl;
  final String? photoPath;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Marina.fromMap(Map<String, dynamic> data) {
    return Marina(
      id: data['id']?.toString() ?? '',
      name: data['name'] as String? ?? 'Marina',
      whatsapp: data['whatsapp'] as String?,
      instagram: data['instagram'] as String?,
      address: data['address'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      photoUrl: data['photo_url'] as String?,
      photoPath: data['photo_path'] as String?,
      createdBy: data['created_by']?.toString(),
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'whatsapp': whatsapp,
      'instagram': instagram,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'photo_url': photoUrl,
      'photo_path': photoPath,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

