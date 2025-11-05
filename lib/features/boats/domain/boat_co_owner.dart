class BoatCoOwner {
  BoatCoOwner({required this.userId, this.email, this.fullName});

  final String userId;
  final String? email;
  final String? fullName;

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) {
      return fullName!;
    }
    if (email != null && email!.isNotEmpty) {
      return email!;
    }
    return userId;
  }

  factory BoatCoOwner.fromMap(Map<String, dynamic> data) {
    return BoatCoOwner(
      userId: data['user_id']?.toString() ?? '',
      email: data['email'] as String?,
      fullName: data['full_name'] as String?,
    );
  }
}
