import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../services/premium_service.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> with WidgetsBindingObserver {
  bool _isPremium = false;
  bool _checking = false;
  bool _openingPortal = false;

  static const _features = [
    (
      icon: Icons.shield_outlined,
      title: 'Password Health Dashboard',
      desc: 'Find weak, reused, and old passwords across your vault.',
    ),
    (
      icon: Icons.warning_amber_rounded,
      title: 'Breach Monitoring',
      desc: 'Check if your passwords have appeared in known data breaches.',
    ),
    (
      icon: Icons.image_outlined,
      title: 'Custom Icons',
      desc: 'Website favicons for your vault entries instead of plain letters.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isPremium = PremiumService.isPremium();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    if (_isPremium || _checking) return;
    setState(() => _checking = true);
    try {
      await supabase.auth.refreshSession();
      if (!mounted) return;
      final nowPremium = PremiumService.isPremium();
      if (nowPremium != _isPremium) {
        setState(() => _isPremium = nowPremium);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _startPolling() {
    setState(() => _checking = true);
    int attempts = 0;
    const maxAttempts = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      attempts++;
      if (!mounted || _isPremium) return false;
      if (attempts >= maxAttempts) {
        if (mounted) {
          setState(() => _checking = false);
        }
        return false;
      }
      try {
        await supabase.auth.refreshSession();
        if (!mounted) return false;
        final nowPremium = PremiumService.isPremium();
        if (nowPremium) {
          setState(() {
            _isPremium = true;
            _checking = false;
          });
          return false;
        }
      } catch (_) {}
      return mounted && !_isPremium;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CryptKeep Pro')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                _isPremium ? Icons.verified : Icons.workspace_premium,
                size: 56,
                color: const Color(0xFFFFD700),
              ),
              const SizedBox(height: 16),
              const Text(
                'CryptKeep Pro',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isPremium
                    ? 'You have an active Pro subscription.'
                    : 'Unlock premium features to keep your vault secure.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
              if (_checking) ...[
                const SizedBox(height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Waiting for payment confirmation...',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              ...List.generate(_features.length, (i) {
                final f = _features[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(f.icon, color: const Color(0xFF8B5CF6), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(f.desc,
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_isPremium)
                        const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),
              if (_isPremium) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    if (_openingPortal) return;
                    setState(() => _openingPortal = true);
                    final email = supabase.auth.currentUser?.email;
                    if (email == null) {
                      setState(() => _openingPortal = false);
                      return;
                    }
                    try {
                      final response = await supabase.functions.invoke(
                        'manage-subscription',
                        body: {'email': email},
                      );
                      final url = response.data['url'];
                      if (url != null) {
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      debugPrint('Manage subscription error: $e');
                    }
                    if (mounted) setState(() => _openingPortal = false);
                  },
                  icon: _openingPortal
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.settings, size: 18),
                  label: Text(_openingPortal ? 'Opening...' : 'Manage Subscription'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A3E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cancel, resume, or update payment method',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
              if (!_isPremium) ...[
                const Text(
                  '\$3 / month',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cancel anytime',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    final email = supabase.auth.currentUser?.email ?? '';
                    final url =
                      'https://buy.stripe.com/14A3cwgAc0Jc96K8X2cQU00'
                      '?prefilled_email=${Uri.encodeComponent(email)}';

                    if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) {
                      // Use Google Play External Offers API on Android
                      try {
                        const channel = MethodChannel('com.eerie.cryptkeep/external_offers');
                        await channel.invokeMethod('launchExternalOffer', {'url': url});
                      } catch (_) {
                        // Fallback to direct URL if external offers unavailable
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      }
                    } else {
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    }
                    _startPolling();
                  },
                  child: const Text('Subscribe'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
