class MarinaWallPost {
  MarinaWallPost({
    required this.id,
    required this.marinaId,
    required this.title,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
    this.marinaName,
    this.description,
    this.imageUrl,
    this.imagePath,
    this.createdBy,
    this.createdByName,
  });

  final String id;
  final String marinaId;
  final String? marinaName;
  final String title;
  final String? description;
  final String type;
  final DateTime startDate;
  final DateTime endDate;
  final String? imageUrl;
  final String? imagePath;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get isSingleDay =>
      startDate.year == endDate.year &&
      startDate.month == endDate.month &&
      startDate.day == endDate.day;

  factory MarinaWallPost.fromMap(Map<String, dynamic> data) {
    return MarinaWallPost(
      id: data['id']?.toString() ?? '',
      marinaId: data['marina_id']?.toString() ?? '',
      marinaName: data['marina_name'] as String?,
      title: data['title']?.toString() ?? '',
      description: data['description'] as String?,
      type: data['type']?.toString() ?? '',
      startDate: DateTime.parse(data['start_date'] as String),
      endDate: DateTime.parse(data['end_date'] as String),
      imageUrl: data['image_url'] as String?,
      imagePath: data['image_path'] as String?,
      createdBy: data['created_by']?.toString(),
      createdByName: data['created_by_name'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
    );
  }
}

const muralPostTypes = <String>['evento', 'aviso', 'publicidade'];

const muralPostTypeLabels = <String, String>{
  'evento': 'Evento',
  'aviso': 'Aviso',
  'publicidade': 'Publicidade',
};
