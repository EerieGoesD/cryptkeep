import '../app.dart';
import '../config.dart';
import 'ms_store_service.dart';

class PremiumService {
  /// Cached Microsoft Store entitlement, refreshed via
  /// [refreshStoreEntitlement]. The native Store license check is async, so the
  /// synchronous [isPremium] reads this cached value.
  static bool _storeActive = false;

  /// True when this build sells Pro through a Microsoft Store add-on
  /// (free Windows build, not the bundled-Pro build).
  static bool get usesMsStore =>
      !kProIncluded && MsStoreService.isSupported;

  /// Checks if the current user has an active premium subscription.
  /// Server-verified Premium status is stored in app metadata as
  /// `premium_until` (ISO date). User metadata is kept as a legacy fallback for
  /// manually granted reviewer/test accounts. On Windows, an active Microsoft
  /// Store subscription add-on also grants Pro. On bundled-Pro builds
  /// (kProIncluded), Pro is always on.
  static bool isPremium() {
    if (kProIncluded) return true;
    if (_storeActive) return true;
    final user = supabase.auth.currentUser;
    final until =
        user?.appMetadata['premium_until'] as String? ??
        user?.userMetadata?['premium_until'] as String?;
    if (until == null) return false;
    try {
      return DateTime.parse(until).isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Re-queries the Microsoft Store license and updates the cached entitlement.
  /// No-op on platforms without a Store add-on. Returns the latest value.
  static Future<bool> refreshStoreEntitlement() async {
    if (!usesMsStore) return _storeActive;
    _storeActive = await MsStoreService.isSubscriptionActive();
    return _storeActive;
  }
}
