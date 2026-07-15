import 'passkey_data.dart';

class VaultEntry {
  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String category;

  /// Set when this entry is a passkey rather than a password. Entries saved
  /// before passkeys existed simply have none.
  final PasskeyData? passkey;

  final DateTime createdAt;
  final DateTime updatedAt;

  const VaultEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    this.url = '',
    this.notes = '',
    this.category = '',
    this.passkey,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True if this entry is a passkey.
  bool get isPasskey => passkey != null;

  VaultEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? category,
    PasskeyData? passkey,
  }) {
    return VaultEntry(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      passkey: passkey ?? this.passkey,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'category': category,
        if (passkey != null) 'passkey': passkey!.toJson(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        url: (json['url'] as String?) ?? '',
        notes: (json['notes'] as String?) ?? '',
        category: (json['category'] as String?) ?? '',
        passkey: json['passkey'] == null
            ? null
            : PasskeyData.fromJson(json['passkey'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
