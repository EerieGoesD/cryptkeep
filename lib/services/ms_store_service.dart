import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native Microsoft Store add-on channel (Windows only).
///
/// Implemented in `windows/runner/ms_store_bridge.cpp` over the WinRT
/// `StoreContext` API. All methods fail closed (no entitlement) off Windows or
/// when the app is not running from a Store-signed package.
class MsStoreService {
  static const MethodChannel _channel = MethodChannel('cryptkeep/ms_store');

  /// Add-on Product ID configured in Partner Center. Must match exactly.
  static const String productId = 'cryptkeep_pro_monthly';

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Whether the user currently owns an active subscription.
  static Future<bool> isSubscriptionActive() async {
    if (!isSupported) return false;
    try {
      final active = await _channel.invokeMethod<bool>(
        'isSubscriptionActive',
        {'productId': productId},
      );
      return active ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Localized formatted price (e.g. "$3.00") or null if unavailable.
  static Future<String?> price() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>(
        'getPrice',
        {'productId': productId},
      );
    } catch (_) {
      return null;
    }
  }

  /// Launches the Store purchase flow. Returns a status string:
  /// 'succeeded', 'alreadyPurchased', 'notPurchased', 'networkError',
  /// 'serverError', 'productNotFound', or 'error'.
  static Future<String> purchase() async {
    if (!isSupported) return 'error';
    try {
      final status = await _channel.invokeMethod<String>(
        'purchaseSubscription',
        {'productId': productId},
      );
      return status ?? 'error';
    } catch (_) {
      return 'error';
    }
  }
}
