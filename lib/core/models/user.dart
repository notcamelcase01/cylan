class AppUser {
  final int id;
  final String username;

  /// Optional display name (Django `first_name`); empty when not set.
  final String name;
  final String email;

  AppUser({
    required this.id,
    required this.username,
    this.name = '',
    this.email = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    username: json['username'] as String,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
  );
}
