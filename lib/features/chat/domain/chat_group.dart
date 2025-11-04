class ChatGroup {
  ChatGroup({
    required this.id,
    required this.name,
    this.description,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ChatGroup.fromMap(Map<String, dynamic> data) {
    return ChatGroup(
      id: data['id']?.toString() ?? '',
      name: data['name'] as String? ?? 'Grupo',
      description: data['description'] as String?,
      createdBy: data['created_by']?.toString(),
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
    );
  }
}
