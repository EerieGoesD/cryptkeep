/// Everything needed to produce a site's two-factor code.
///
/// A site hands these out in an `otpauth://` link (what its QR code holds).
/// Most use the defaults, but not all: some use 8 digits, a 60 second window,
/// or SHA256. Storing only the secret and assuming the defaults produces codes
/// that are silently wrong on those sites, so all of it is kept.
///
/// Reference: https://github.com/google/google-authenticator/wiki/Key-Uri-Format
class TotpConfig {
  /// Base32 seed the codes are derived from.
  final String secret;

  /// 6 or 8. Anything else is not used in practice.
  final int digits;

  /// Seconds a code stays valid. 30 nearly always.
  final int period;

  /// SHA1, SHA256 or SHA512. SHA1 nearly always, despite the name - this is
  /// not a security weakness here, it is what the standard specifies.
  final String algorithm;

  /// Who the code is for, e.g. "GitHub". Only for display.
  final String issuer;

  /// Which account at the issuer. Only for display.
  final String account;

  const TotpConfig({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
    this.issuer = '',
    this.account = '',
  });

  /// True when everything matches the defaults, so the entry can be stored as
  /// a bare secret string and stays readable by older versions of the app.
  bool get isDefault =>
      digits == 6 && period == 30 && algorithm.toUpperCase() == 'SHA1';

  Map<String, dynamic> toJson() => {
        'secret': secret,
        if (digits != 6) 'digits': digits,
        if (period != 30) 'period': period,
        if (algorithm.toUpperCase() != 'SHA1') 'algorithm': algorithm,
        if (issuer.isNotEmpty) 'issuer': issuer,
        if (account.isNotEmpty) 'account': account,
      };

  factory TotpConfig.fromJson(Map<String, dynamic> json) => TotpConfig(
        secret: json['secret'] as String,
        digits: (json['digits'] as int?) ?? 6,
        period: (json['period'] as int?) ?? 30,
        algorithm: (json['algorithm'] as String?) ?? 'SHA1',
        issuer: (json['issuer'] as String?) ?? '',
        account: (json['account'] as String?) ?? '',
      );
}
