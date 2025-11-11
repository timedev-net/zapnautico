import 'dart:math';

class Listing {
  Listing({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.ownerId,
    required this.condition,
    required this.paymentOptions,
    required this.photos,
    required this.whatsappContacts,
    required this.createdAt,
    required this.updatedAt,
    this.price,
    this.description,
    this.videoUrl,
    this.city,
    this.state,
    this.latitude,
    this.longitude,
    this.advertiserName,
    this.instagramHandle,
    this.showEmail = false,
    this.ownerName,
    this.ownerEmail,
    this.publishedAt,
    this.soldAt,
    this.boatId,
  });

  final String id;
  final String title;
  final String category;
  final String status;
  final String ownerId;
  final double? price;
  final String? description;
  final String condition;
  final List<String> paymentOptions;
  final List<ListingPhoto> photos;
  final String? videoUrl;
  final String? city;
  final String? state;
  final double? latitude;
  final double? longitude;
  final String? advertiserName;
  final List<ListingWhatsappContact> whatsappContacts;
  final String? instagramHandle;
  final bool showEmail;
  final String? ownerName;
  final String? ownerEmail;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final DateTime? soldAt;
  final String? boatId;

  bool get isPending => status == ListingStatus.pending;
  bool get isPublished => status == ListingStatus.published;
  bool get isSold => status == ListingStatus.sold;
  bool get hasMedia => photos.isNotEmpty || videoUrl != null;
  bool get canEdit => !isSold;

  factory Listing.fromMap(Map<String, dynamic> data) {
    final photosData = data['photos'];
    final parsedPhotos = <ListingPhoto>[];
    if (photosData is List) {
      for (final item in photosData) {
        final map = _forceMap(item);
        if (map == null) continue;
        parsedPhotos.add(ListingPhoto.fromMap(map));
      }
      parsedPhotos.sort((a, b) => a.position.compareTo(b.position));
    }

    final contactsData = data['whatsapp_contacts'];
    final parsedContacts = <ListingWhatsappContact>[];
    if (contactsData is List) {
      for (final item in contactsData) {
        final map = _forceMap(item);
        if (map == null) continue;
        parsedContacts.add(ListingWhatsappContact.fromMap(map));
      }
    }

    final paymentData = data['payment_options'];
    final payments = <String>[];
    if (paymentData is List) {
      payments.addAll(
        paymentData
            .whereType<String>()
            .where((value) => marketplacePaymentOptions.contains(value)),
      );
    }

    return Listing(
      id: data['id']?.toString() ?? '',
      title: data['title'] as String? ?? 'Anúncio',
      category: data['category'] as String? ?? listingCategories.first,
      status: data['status'] as String? ?? ListingStatus.pending,
      ownerId: data['owner_id']?.toString() ?? '',
      price: (data['price'] as num?)?.toDouble(),
      description: data['description'] as String?,
      condition: data['condition'] as String? ?? ListingCondition.used,
      paymentOptions: payments,
      photos: parsedPhotos,
      videoUrl: data['video_url'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      advertiserName: data['advertiser_name'] as String?,
      whatsappContacts: parsedContacts,
      instagramHandle: data['instagram_handle'] as String?,
      showEmail: data['show_email'] as bool? ?? false,
      ownerName: data['owner_full_name'] as String?,
      ownerEmail: data['owner_email'] as String?,
      createdAt: DateTime.parse(
        (data['created_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        (data['updated_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
      ),
      publishedAt: (data['published_at'] as String?) != null
          ? DateTime.tryParse(data['published_at'] as String)
          : null,
      soldAt: (data['sold_at'] as String?) != null
          ? DateTime.tryParse(data['sold_at'] as String)
          : null,
      boatId: data['boat_id']?.toString(),
    );
  }
}

class ListingPhoto {
  ListingPhoto({
    required this.id,
    required this.publicUrl,
    required this.position,
    required this.bucket,
    this.storagePath,
    this.source,
  });

  final String id;
  final String publicUrl;
  final int position;
  final String bucket;
  final String? storagePath;
  final String? source;

  bool get isMarketplaceFile => bucket == 'marketplace_photos';

  ListingPhoto copyWith({int? position}) {
    return ListingPhoto(
      id: id,
      publicUrl: publicUrl,
      position: position ?? this.position,
      bucket: bucket,
      storagePath: storagePath,
      source: source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'public_url': publicUrl,
      'position': position,
      'bucket': bucket,
      if (storagePath != null) 'storage_path': storagePath,
      if (source != null) 'source': source,
    };
  }

  factory ListingPhoto.fromMap(Map<String, dynamic> data) {
    return ListingPhoto(
      id: data['id']?.toString() ?? _randomId(),
      publicUrl: data['public_url'] as String? ?? '',
      position: (data['position'] as num?)?.toInt() ?? 0,
      bucket: data['bucket']?.toString() ?? 'marketplace_photos',
      storagePath: data['storage_path']?.toString(),
      source: data['source']?.toString(),
    );
  }

  static String _randomId() => DateTime.now().microsecondsSinceEpoch.toString();
}

class ListingWhatsappContact {
  ListingWhatsappContact({
    required this.name,
    required this.number,
    this.contactId,
  });

  final String name;
  final String number;
  final String? contactId;

  String get formattedNumber {
    final digits = number.replaceAll(RegExp(r'\\D'), '');
    if (digits.length < 11) {
      return number;
    }
    final country = digits.substring(0, digits.length - 11);
    final ddd = digits.substring(digits.length - 11, digits.length - 9);
    final local = digits.substring(digits.length - 9);
    final first = local.substring(0, max(1, local.length - 4));
    final last = local.substring(local.length - 4);
    final parts = [
      if (country.isNotEmpty) '+$country',
      '($ddd)',
      '$first-$last',
    ];
    return parts.join(' ');
  }

  String get whatsappDeepLink {
    final digits = number.replaceAll(RegExp(r'\\D'), '');
    return 'https://wa.me/$digits';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'number': number,
      if (contactId != null) 'contact_id': contactId,
    };
  }

  factory ListingWhatsappContact.fromMap(Map<String, dynamic> data) {
    return ListingWhatsappContact(
      name: data['name'] as String? ?? 'Contato',
      number: data['number'] as String? ?? '+55',
      contactId: data['contact_id']?.toString(),
    );
  }
}

class ListingStatus {
  static const pending = 'aguardando_publicacao';
  static const published = 'publicado';
  static const sold = 'vendido';
}

class ListingCondition {
  static const newItem = 'novo';
  static const used = 'usado';
}

const listingCategories = <String>[
  'Embarcações',
  'Peças e Acessórios',
  'Equipamentos de Segurança',
  'Eletrônicos Náuticos',
  'Serviços',
  'Itens de Lazer e Esportes Aquáticos',
  'Equipamentos de Bordo / Conforto',
  'Vestuário e Acessórios',
  'Locação / Charter',
  'Cotas / Consórcios',
];

const marketplacePaymentOptions = <String>[
  'pix',
  'credito_vista',
  'credito_parcelado',
  'negociavel',
];

const paymentOptionLabels = <String, String>{
  'pix': 'Pix',
  'credito_vista': 'Cartão de crédito (à vista)',
  'credito_parcelado': 'Cartão de crédito (parcelado)',
  'negociavel': 'Aberto a negociação',
};

Map<String, dynamic>? _forceMap(Object? source) {
  if (source is Map<String, dynamic>) {
    return source;
  }
  if (source is Map) {
    return source.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return null;
}
