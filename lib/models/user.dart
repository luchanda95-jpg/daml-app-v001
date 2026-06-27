// lib/models/user.dart
class User {
  final String email;
  final String name;
  final String phone;
  final String role;
  final String token;

  User({
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    required this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      email: (json['email'] ?? json['email_address'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      phone: (json['phone'] ?? '') as String,
      role: (json['role'] ?? 'client') as String,
      token: (json['token'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        'phone': phone,
        'role': role,
        'token': token,
      };
}
