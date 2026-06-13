import '../app.dart';
import '../config.dart';

class PremiumService {
  /// Checks if the current user has an active premium subscription.
  /// Server-verified Premium status is stored in app metadata as
  /// `premium_until` (ISO date). User metadata is kept as a legacy fallback for
  /// manually granted reviewer/test accounts.
  /// On bundled-Pro builds (kProIncluded), Pro is always on.
  static bool isPremium() {
    if (kProIncluded) return true;
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
}
