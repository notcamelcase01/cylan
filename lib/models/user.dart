class AppUser {
  final int id;
  final String username;
  final String email;

  AppUser({required this.id, required this.username, required this.email});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        username: json['username'] as String,
        email: json['email'] as String? ?? '',
      );
}
