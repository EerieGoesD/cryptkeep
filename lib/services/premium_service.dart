import '../app.dart';
import '../config.dart';

class PremiumService {
  /// Checks if the current user has an active premium subscription.
  /// Premium status is stored in user metadata as `premium_until` (ISO date).
  /// On bundled-Pro builds (kProIncluded), Pro is always on.
  static bool isPremium() {
    if (kProIncluded) return true;
    final metadata = supabase.auth.currentUser?.userMetadata;
    if (metadata == null) return false;
    final until = metadata['premium_until'] as String?;
    if (until == null) return false;
    try {
      return DateTime.parse(until).isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }
}
