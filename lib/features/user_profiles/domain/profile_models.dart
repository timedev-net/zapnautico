class ProfileType {
  ProfileType({required this.slug, required this.name, this.description});

  final String slug;
  final String name;
  final String? description;

  factory ProfileType.fromMap(Map<String, dynamic> data) {
    return ProfileType(
      slug: data['slug'] as String,
      name: data['name'] as String,
      description: data['description'] as String?,
    );
  }
}

class UserProfileAssignment {
  UserProfileAssignment({
    required this.id,
    required this.userId,
    required this.profileSlug,
    required this.profileName,
    this.assignedBy,
    required this.createdAt,
    this.marinaId,
    this.marinaName,
  });

  final String id;
  final String userId;
  final String profileSlug;
  final String profileName;
  final String? assignedBy;
  final DateTime createdAt;
  final String? marinaId;
  final String? marinaName;

  factory UserProfileAssignment.fromMap(Map<String, dynamic> data) {
    return UserProfileAssignment(
      id: data['id']?.toString() ?? '',
      userId: data['user_id']?.toString() ?? '',
      profileSlug: data['profile_slug'] as String,
      profileName: data['profile_name'] as String,
      assignedBy: data['assigned_by']?.toString(),
      createdAt: DateTime.parse(data['created_at'] as String),
      marinaId: data['marina_id']?.toString(),
      marinaName: data['marina_name'] as String?,
    );
  }
}

class AppUser {
  AppUser({
    required this.id,
    this.email,
    this.fullName,
    this.phone,
    this.avatarUrl,
    required this.createdAt,
  });

  final String id;
  final String? email;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final DateTime createdAt;

  String get displayName => fullName?.isNotEmpty == true
      ? fullName!
      : email?.isNotEmpty == true
      ? email!
      : id;

  factory AppUser.fromMap(Map<String, dynamic> data) {
    return AppUser(
      id: data['id']?.toString() ?? '',
      email: data['email'] as String?,
      fullName: data['full_name'] as String?,
      phone: data['phone'] as String?,
      avatarUrl: data['avatar_url'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }
}

class AppUserWithProfiles {
  AppUserWithProfiles({required this.user, required this.profiles});

  final AppUser user;
  final List<UserProfileAssignment> profiles;
}
