// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Map<String, String> defaultHeaders = {'Content-Type': 'application/json'};

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    if (!path.startsWith('/')) path = '/$path';
    return Uri.parse('$normalizedBase$path');
  }

  // Decode JWT payload (no external package) - returns map or {}
  Map<String, dynamic> _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return {};
      var payload = parts[1];

      // add padding if required
      final mod4 = payload.length % 4;
      if (mod4 != 0) payload += '=' * (4 - mod4);

      final decoded = utf8.decode(base64Url.decode(payload));
      final Map<String, dynamic> map = json.decode(decoded) as Map<String, dynamic>;
      return map;
    } catch (_) {
      return {};
    }
  }

  Map<String, String> _withAuthHeader(String token, [Map<String, String>? extra]) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  // --------------------
  // Auth
  // --------------------
  Future<User> login(String email, String password) async {
    final uri = _uri('/api/auth/login');
    final resp = await _client.post(uri,
        headers: defaultHeaders, body: json.encode({'email': email, 'password': password}));
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final token = (body['token'] ?? '') as String;
      if (token.isEmpty) throw Exception('Login succeeded but no token returned');

      // server returns role,name,phone but not always email -> decode token
      final payload = _decodeJwtPayload(token);
      final emailFromToken = ((payload['email'] ?? payload['sub']) ?? '') as String;

      final user = User(
        email: (body['email'] as String?) ?? emailFromToken,
        name: (body['name'] ?? '') as String,
        phone: (body['phone'] ?? '') as String,
        role: (body['role'] ?? payload['role'] ?? 'client') as String,
        token: token,
      );
      return user;
    } else if (resp.statusCode == 401) {
      throw Exception('Invalid credentials');
    } else {
      throw Exception('Login failed (${resp.statusCode})');
    }
  }

  Future<User> register(String name, String email, String phone, String password) async {
    final uri = _uri('/api/auth/register');
    final resp = await _client.post(uri,
        headers: defaultHeaders,
        body: json.encode({'name': name, 'email': email, 'phone': phone, 'password': password}));
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final token = (body['token'] ?? '') as String;
      if (token.isEmpty) throw Exception('Register succeeded but no token returned');

      final payload = _decodeJwtPayload(token);
      final emailFromToken = ((payload['email'] ?? payload['sub']) ?? '') as String;

      final user = User(
        email: (body['email'] as String?) ?? emailFromToken,
        name: (body['name'] ?? name) as String,
        phone: (body['phone'] ?? phone) as String,
        role: (body['role'] ?? payload['role'] ?? 'client') as String,
        token: token,
      );
      return user;
    } else if (resp.statusCode == 409) {
      throw Exception('Email already registered');
    } else {
      throw Exception('Register failed (${resp.statusCode})');
    }
  }

  Future<bool> healthcheck() async {
    try {
      final uri = _uri('/health');
      final resp = await _client.get(uri, headers: defaultHeaders).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --------------------
  // Users / profile endpoints (new)
  // --------------------

  /// GET /api/users
  /// Returns list of users (minimal info). Admin-only on server.
  Future<List<User>> getUsers(String token) async {
    final uri = _uri('/api/users');
    final headers = _withAuthHeader(token);
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode == 200) {
      final list = json.decode(resp.body) as List<dynamic>;
      return list.map((e) {
        final m = Map<String, dynamic>.from(e);
        try {
          return User.fromJson(m);
        } catch (_) {
          // Defensive: if User.fromJson missing some fields, construct minimally
          return User(
            email: (m['email'] ?? '') as String,
            name: (m['name'] ?? '') as String,
            phone: (m['phone'] ?? '') as String,
            role: (m['role'] ?? 'client') as String,
            token: '',
          );
        }
      }).toList();
    } else if (resp.statusCode == 401) {
      throw Exception('Unauthorized');
    } else {
      throw Exception('Failed to fetch users (${resp.statusCode})');
    }
  }

  /// GET /api/users/:email/profile
  /// Returns a profile object (email,name,phone,role,balances,notificationsCount)
  Future<Map<String, dynamic>> getProfile(String normalizedEmail, String token) async {
    final uri = _uri('/api/users/$normalizedEmail/profile');
    final headers = _withAuthHeader(token);
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode == 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      return Map<String, dynamic>.from(body);
    } else if (resp.statusCode == 401) {
      throw Exception('Unauthorized');
    } else if (resp.statusCode == 404) {
      throw Exception('User not found');
    } else {
      throw Exception('Failed to get profile (${resp.statusCode})');
    }
  }

  /// PUT /api/users/:email/profile
  /// Body: { name?, phone?, role? } - role allowed only for ovadmin server-side
  Future<Map<String, dynamic>> updateProfile(String normalizedEmail, Map<String, dynamic> body, String token) async {
    final uri = _uri('/api/users/$normalizedEmail/profile');
    final headers = _withAuthHeader(token);
    final resp = await _client.put(uri, headers: headers, body: json.encode(body));
    if (resp.statusCode == 200) {
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      return Map<String, dynamic>.from(decoded);
    } else if (resp.statusCode == 401) {
      throw Exception('Unauthorized');
    } else if (resp.statusCode == 403) {
      throw Exception('Forbidden');
    } else if (resp.statusCode == 404) {
      throw Exception('User not found');
    } else {
      throw Exception('Failed to update profile (${resp.statusCode})');
    }
  }

  /// GET /api/users/:email/next_payment
  /// Returns { next_payment: { amount, date } } or { next_payment: null }
  Future<Map<String, dynamic>?> getNextPayment(String normalizedEmail, String token) async {
    final uri = _uri('/api/users/$normalizedEmail/next_payment');
    final headers = _withAuthHeader(token);
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode == 200) {
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final np = decoded['next_payment'];
      if (np == null) return null;
      return Map<String, dynamic>.from(np);
    } else if (resp.statusCode == 401) {
      throw Exception('Unauthorized');
    } else if (resp.statusCode == 404) {
      throw Exception('User not found');
    } else {
      throw Exception('Failed to fetch next payment (${resp.statusCode})');
    }
  }
}
