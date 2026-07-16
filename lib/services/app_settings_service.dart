import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local, per-device preferences. Never synced - these are choices about this
/// device, not vault contents.
class AppSettingsService {
  static const _siteIconsKey = 'cryptkeep_site_icons_enabled';
  static const _storage = FlutterSecureStorage();

  /// Whether to fetch website icons for vault entries.
  ///
  /// OFF by default, and deliberately so: the icons come from Google, one
  /// request per site, which tells Google which sites the user has accounts
  /// with. That is a reasonable trade to offer, but not one to make on
  /// someone's behalf in an app whose whole promise is that nobody sees their
  /// data. Opt in, informed, or not at all.
  static Future<bool> siteIconsEnabled() async {
    try {
      return await _storage.read(key: _siteIconsKey) == 'true';
    } catch (e) {
      if (kDebugMode) debugPrint('Could not read site icon setting: $e');
      return false;
    }
  }

  static Future<void> setSiteIconsEnabled(bool value) async {
    try {
      await _storage.write(key: _siteIconsKey, value: value.toString());
    } catch (e) {
      if (kDebugMode) debugPrint('Could not save site icon setting: $e');
    }
  }
}
