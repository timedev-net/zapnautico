class BoatPhoto {
  BoatPhoto({
    required this.id,
    required this.storagePath,
    required this.publicUrl,
    required this.position,
  });

  final String id;
  final String storagePath;
  final String publicUrl;
  final int position;

  factory BoatPhoto.fromMap(Map<String, dynamic> data) {
    return BoatPhoto(
      id: data['id']?.toString() ?? '',
      storagePath: data['storage_path'] as String? ?? '',
      publicUrl: data['public_url'] as String? ?? '',
      position: (data['position'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storage_path': storagePath,
      'public_url': publicUrl,
      'position': position,
    };
  }

  BoatPhoto copyWith({
    String? id,
    String? storagePath,
    String? publicUrl,
    int? position,
  }) {
    return BoatPhoto(
      id: id ?? this.id,
      storagePath: storagePath ?? this.storagePath,
      publicUrl: publicUrl ?? this.publicUrl,
      position: position ?? this.position,
    );
  }
}
