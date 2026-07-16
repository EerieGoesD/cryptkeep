import 'passkey_data.dart';
import 'totp_config.dart';

class VaultEntry {
  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String category;

  /// The site's two-factor code setup, or null if it has none. Encrypted with
  /// the rest of the entry - as sensitive as the password, since together they
  /// are the whole login.
  final TotpConfig? totp;

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
    this.totp,
    this.passkey,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True if this entry is a passkey.
  bool get isPasskey => passkey != null;

  /// True if this entry can produce a two-factor code.
  bool get hasTotp => totp != null;

  VaultEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? category,
    TotpConfig? totp,
    bool clearTotp = false,
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
      // clearTotp is needed because passing null cannot mean "remove it".
      totp: clearTotp ? null : (totp ?? this.totp),
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
        if (totp != null) 'totp': totp!.toJson(),
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
        totp: json['totp'] == null
            ? null
            : TotpConfig.fromJson(json['totp'] as Map<String, dynamic>),
        passkey: json['passkey'] == null
            ? null
            : PasskeyData.fromJson(json['passkey'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
