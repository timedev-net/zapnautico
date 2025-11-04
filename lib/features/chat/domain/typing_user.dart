class TypingUser {
  const TypingUser({
    required this.userId,
    required this.name,
  });

  final String userId;
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TypingUser && other.userId == userId;
  }

  @override
  int get hashCode => userId.hashCode;
}
