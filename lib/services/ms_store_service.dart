import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native Microsoft Store add-on channel (Windows only).
///
/// Implemented in `windows/runner/ms_store_bridge.cpp` over the WinRT
/// `StoreContext` API. All methods fail closed (no entitlement) off Windows or
/// when the app is not running from a Store-signed package.
class MsStoreService {
  static const MethodChannel _channel = MethodChannel('cryptkeep/ms_store');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Whether the user currently owns any active Pro subscription add-on
  /// (monthly or yearly).
  static Future<bool> isSubscriptionActive() async {
    if (!isSupported) return false;
    try {
      final active =
          await _channel.invokeMethod<bool>('isSubscriptionActive');
      return active ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Localized formatted price (e.g. "$2.99") for the given add-on, or null if
  /// unavailable.
  static Future<String?> price(String productId) async {
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

  /// Launches the Store purchase flow for the given add-on. Returns a status
  /// string: 'succeeded', 'alreadyPurchased', 'notPurchased', 'networkError',
  /// 'serverError', 'productNotFound', or 'error'.
  static Future<String> purchase(String productId) async {
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
