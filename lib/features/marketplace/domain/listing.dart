class Listing {
  Listing({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.ownerId,
    this.price,
    this.currency,
    this.description,
    this.mediaUrl,
  });

  final String id;
  final String title;
  final String type;
  final String status;
  final String ownerId;
  final double? price;
  final String? currency;
  final String? description;
  final String? mediaUrl;

  factory Listing.fromMap(Map<String, dynamic> data) {
    return Listing(
      id: data['id']?.toString() ?? '',
      title: data['title'] as String? ?? 'Anúncio',
      type: data['type'] as String? ?? 'acessorio',
      status: data['status'] as String? ?? 'ativo',
      ownerId: data['owner_id']?.toString() ?? '',
      price: (data['price'] as num?)?.toDouble(),
      currency: data['currency'] as String?,
      description: data['description'] as String?,
      mediaUrl: data['media_url'] as String?,
    );
  }
}

