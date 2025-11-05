class OwnerSummary {
  OwnerSummary({required this.id, required this.email, required this.fullName});

  final String id;
  final String email;
  final String fullName;

  factory OwnerSummary.fromMap(Map<String, dynamic> data) {
    return OwnerSummary(
      id: data['user_id']?.toString() ?? '',
      email: data['email'] as String? ?? '',
      fullName: data['full_name'] as String? ?? '',
    );
  }

  bool get isValid => id.isNotEmpty && email.isNotEmpty;
}
