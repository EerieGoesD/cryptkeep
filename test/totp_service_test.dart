import 'package:cryptkeep/models/totp_config.dart';
import 'package:cryptkeep/services/totp_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checked against the official test vectors in RFC 6238 Appendix B. If these
/// fail, every code the app shows is wrong and every login using them fails.
void main() {
  // RFC 6238 uses the ASCII secret "12345678901234567890" for SHA-1.
  // In base32 (what sites actually hand out) that is:
  const rfcSecret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

  String codeAt(int unixSeconds, {int digits = 8, String algorithm = 'SHA1'}) =>
      TotpService.generate(
        TotpConfig(secret: rfcSecret, digits: digits, algorithm: algorithm),
        at: DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true),
      );

  group('RFC 6238 official test vectors (SHA-1)', () {
    test('T = 59', () => expect(codeAt(59), '94287082'));
    test('T = 1111111109', () => expect(codeAt(1111111109), '07081804'));
    test('T = 1111111111', () => expect(codeAt(1111111111), '14050471'));
    test('T = 1234567890', () => expect(codeAt(1234567890), '89005924'));
    test('T = 2000000000', () => expect(codeAt(2000000000), '69279037'));
    test('T = 20000000000', () => expect(codeAt(20000000000), '65353130'));
  });

  test('six digits is the last six of the eight-digit code', () {
    expect(codeAt(59, digits: 6), '287082');
    expect(codeAt(1111111109, digits: 6), '081804');
  });

  test('the code holds steady inside its window and then changes', () {
    // A code must not change mid-typing.
    expect(codeAt(1111111111), codeAt(1111111111 + 9));
    expect(codeAt(1111111111), isNot(codeAt(1111111111 + 30)));
  });

  test('a 60 second window changes half as often', () {
    // Sites that use a longer window: the code must survive past 30s.
    // Windows start on multiples of the period, so 1200-1259 is one window
    // and 1260 begins the next.
    const cfg = TotpConfig(secret: rfcSecret, period: 60);
    at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

    expect(TotpService.generate(cfg, at: at(1200)),
        TotpService.generate(cfg, at: at(1250)),
        reason: 'same 60s window, so the code must not change');
    expect(TotpService.generate(cfg, at: at(1200)),
        isNot(TotpService.generate(cfg, at: at(1260))),
        reason: 'next window, so the code must change');

    // And the same instants under a 30s window land in different windows,
    // proving the period is actually being used.
    const thirty = TotpConfig(secret: rfcSecret, period: 30);
    expect(TotpService.generate(thirty, at: at(1200)),
        isNot(TotpService.generate(thirty, at: at(1250))));
  });

  test('countdown matches the site window, not a hardcoded 30', () {
    at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
    const thirty = TotpConfig(secret: rfcSecret);
    const sixty = TotpConfig(secret: rfcSecret, period: 60);
    expect(TotpService.secondsRemaining(thirty, at(29)), 1);
    expect(TotpService.secondsRemaining(thirty, at(30)), 30);
    expect(TotpService.secondsRemaining(sixty, at(30)), 30);
    expect(TotpService.secondsRemaining(sixty, at(59)), 1);
  });

  group('reading what a site gives you', () {
    test('a QR link keeps the site settings instead of assuming defaults', () {
      // The bug this guards: dropping digits/period and always doing 6/30
      // produces codes that are silently wrong on these sites.
      const uri = 'otpauth://totp/ACME:bob?secret=JBSWY3DPEHPK3PXP'
          '&issuer=ACME&digits=8&period=60&algorithm=SHA256';
      final cfg = TotpService.parse(uri)!;
      expect(cfg.secret, 'JBSWY3DPEHPK3PXP');
      expect(cfg.digits, 8);
      expect(cfg.period, 60);
      expect(cfg.algorithm, 'SHA256');
      expect(cfg.issuer, 'ACME');
      expect(cfg.account, 'bob');
      expect(TotpService.generate(cfg).length, 8);
    });

    test('a plain link falls back to the standard settings', () {
      final cfg =
          TotpService.parse('otpauth://totp/GitHub:eerie?secret=JBSWY3DPEHPK3PXP')!;
      expect(cfg.digits, 6);
      expect(cfg.period, 30);
      expect(cfg.algorithm, 'SHA1');
      expect(cfg.issuer, 'GitHub');
      expect(cfg.isDefault, isTrue);
    });

    test('accepts a key typed by hand, spaced and lower case', () {
      final cfg =
          TotpService.parse('gezd gnbv-gy3t qojq gezdgnbvgy3tqojq')!;
      expect(cfg.secret, rfcSecret);
      expect(cfg.digits, 6);
    });

    test('refuses counter-based codes rather than showing a stuck number', () {
      expect(
        TotpService.parse('otpauth://hotp/ACME:bob?secret=JBSWY3DPEHPK3PXP&counter=1'),
        isNull,
      );
    });

    test('rejects rubbish rather than showing wrong codes', () {
      expect(TotpService.parse('not a real key!'), isNull);
      expect(TotpService.parse(''), isNull);
      // 0, 1 and 8 are not in the base32 alphabet.
      expect(TotpService.parse('01810181'), isNull);
      // A link with no key in it.
      expect(TotpService.parse('otpauth://totp/ACME:bob?issuer=ACME'), isNull);
    });

    test('a nonsense digit count falls back rather than breaking', () {
      final cfg =
          TotpService.parse('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=99')!;
      expect(cfg.digits, 6);
    });
  });

  test('only non-default settings are written, so old entries are unchanged',
      () {
    expect(const TotpConfig(secret: 'ABC').toJson(), {'secret': 'ABC'});
    expect(
      const TotpConfig(secret: 'ABC', digits: 8, period: 60).toJson(),
      {'secret': 'ABC', 'digits': 8, 'period': 60},
    );
  });
}
