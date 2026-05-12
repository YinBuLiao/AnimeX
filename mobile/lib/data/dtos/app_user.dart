class AppUser {
  final String username;
  final String role;
  const AppUser({required this.username, required this.role});

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        username: (j['username'] as String?) ?? '',
        role: (j['role'] as String?) ?? '',
      );
}
