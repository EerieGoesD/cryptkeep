import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../config.dart';
import '../../services/ms_store_service.dart';
import '../../services/premium_service.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with WidgetsBindingObserver {
  static const _googlePlayPackageName = 'com.eerie.cryptkeep';
  static const _stripeCheckoutBaseUrl =
      'https://buy.stripe.com/14A3cwgAc0Jc96K8X2cQU00';

  static const _productIds = {kProductIdMonthly, kProductIdYearly};

  bool _isPremium = false;
  bool _checking = false;
  bool _openingPortal = false;
  bool _loadingBilling = false;
  bool _purchasePending = false;
  int _restoreAttempt = 0;
  bool _restoreMatchedPurchase = false;
  // Google Play product details, keyed by product ID.
  final Map<String, ProductDetails> _gpProducts = {};
  // Microsoft Store formatted prices, keyed by product ID.
  final Map<String, String> _msPrices = {};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  String? _billingMessage;

  bool get _usesGooglePlayBilling =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      !kProIncluded;

  bool get _usesMsStoreBilling =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      !kProIncluded;

  bool get _canInteract => !_purchasePending && !_loadingBilling;

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
    if (_usesGooglePlayBilling) {
      _initGooglePlayBilling();
    } else if (_usesMsStoreBilling) {
      _initMsStoreBilling();
    }
  }

  Future<void> _initMsStoreBilling() async {
    final monthly = await MsStoreService.price(kProductIdMonthly);
    final yearly = await MsStoreService.price(kProductIdYearly);
    final active = await PremiumService.refreshStoreEntitlement();
    if (!mounted) return;
    setState(() {
      if (monthly != null) _msPrices[kProductIdMonthly] = monthly;
      if (yearly != null) _msPrices[kProductIdYearly] = yearly;
      _isPremium = active || _isPremium;
    });
  }

  Future<void> _buyMsStoreSubscription(String productId) async {
    if (_purchasePending) return;
    setState(() {
      _purchasePending = true;
      _billingMessage = null;
    });
    final status = await MsStoreService.purchase(productId);
    if (!mounted) return;
    if (status == 'succeeded' || status == 'alreadyPurchased') {
      await PremiumService.refreshStoreEntitlement();
      if (!mounted) return;
      setState(() {
        _isPremium = PremiumService.isPremium();
        _purchasePending = false;
      });
    } else {
      setState(() {
        _purchasePending = false;
        _billingMessage = _msStoreErrorMessage(status);
      });
    }
  }

  String _msStoreErrorMessage(String status) {
    switch (status) {
      case 'notPurchased':
        return 'Purchase canceled.';
      case 'networkError':
        return 'Network error. Check your connection and try again.';
      case 'serverError':
        return 'Microsoft Store error. Please try again later.';
      case 'productNotFound':
        return 'Subscription is not available yet. Please try again later.';
      default:
        return 'Purchase could not be completed. Please try again.';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _initGooglePlayBilling() async {
    setState(() {
      _loadingBilling = true;
      _billingMessage = null;
    });

    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _purchasePending = false;
          _billingMessage = 'Purchase update failed. Please try again.';
        });
        debugPrint('Google Play purchase stream error: $error');
      },
    );

    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!mounted) return;

      if (!available) {
        setState(() {
          _loadingBilling = false;
          _billingMessage =
              'Google Play Billing is not available on this device.';
        });
        return;
      }

      final response =
          await InAppPurchase.instance.queryProductDetails(_productIds);
      if (!mounted) return;

      if (response.error != null) {
        setState(() {
          _loadingBilling = false;
          _billingMessage = 'Could not load Google Play subscription details.';
        });
        debugPrint('Google Play product query error: ${response.error}');
        return;
      }

      setState(() {
        for (final product in response.productDetails) {
          _gpProducts[product.id] = product;
        }
        _loadingBilling = false;
        if (_gpProducts.isEmpty) {
          _billingMessage = 'Google Play subscriptions are not active yet.';
        }
      });

      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBilling = false;
        _billingMessage = 'Could not initialize Google Play Billing.';
      });
      debugPrint('Google Play billing init error: $e');
    }
  }

  Future<void> _refreshStatus() async {
    if (_isPremium || _checking) return;
    setState(() => _checking = true);
    try {
      await supabase.auth.refreshSession();
      if (!mounted) return;
      if (_usesMsStoreBilling) {
        await PremiumService.refreshStoreEntitlement();
      }
      final nowPremium = PremiumService.isPremium();
      if (nowPremium != _isPremium) {
        setState(() => _isPremium = nowPremium);
      }
      if (_usesGooglePlayBilling) {
        await InAppPurchase.instance.restorePurchases();
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

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_productIds.contains(purchase.productID)) continue;
      _restoreMatchedPurchase = true;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (mounted) {
            setState(() {
              _purchasePending = true;
              _billingMessage = 'Purchase is pending in Google Play.';
            });
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            final active = await _verifyGooglePlayPremium(purchase);
            if (active && purchase.pendingCompletePurchase) {
              await InAppPurchase.instance.completePurchase(purchase);
            }
            if (!mounted) return;
            if (active) {
              setState(() {
                _isPremium = true;
                _purchasePending = false;
                _billingMessage = null;
              });
            } else {
              setState(() {
                _purchasePending = false;
                _billingMessage =
                    'No active Google Play subscription was found for this account.';
              });
            }
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _purchasePending = false;
              _billingMessage =
                  'Subscription was purchased, but Pro activation failed.';
            });
            debugPrint('Google Play premium grant error: $e');
          }
          break;
        case PurchaseStatus.error:
          if (mounted) {
            setState(() {
              _purchasePending = false;
              _billingMessage =
                  purchase.error?.message ?? 'Google Play purchase failed.';
            });
          }
          break;
        case PurchaseStatus.canceled:
          if (mounted) {
            setState(() {
              _purchasePending = false;
              _billingMessage = 'Purchase canceled.';
            });
          }
          break;
      }
    }
  }

  Future<bool> _verifyGooglePlayPremium(PurchaseDetails purchase) async {
    final purchaseToken = purchase.verificationData.serverVerificationData;
    if (purchaseToken.isEmpty) {
      throw StateError('Missing Google Play purchase token');
    }

    final response = await supabase.functions.invoke(
      'verify-google-play-purchase',
      body: {
        'packageName': _googlePlayPackageName,
        'productId': purchase.productID,
        'purchaseToken': purchaseToken,
      },
    );

    final data = response.data;
    if (data is! Map || data['active'] != true) {
      return false;
    }

    await supabase.auth.refreshSession();
    return true;
  }

  Future<void> _buyGooglePlaySubscription(ProductDetails product) async {
    if (_purchasePending) return;

    setState(() {
      _purchasePending = true;
      _billingMessage = null;
    });

    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final started = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!started && mounted) {
        setState(() {
          _purchasePending = false;
          _billingMessage = 'Google Play purchase could not be started.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _purchasePending = false;
        _billingMessage = 'Google Play purchase could not be started.';
      });
      debugPrint('Google Play buy error: $e');
    }
  }

  Future<void> _restoreGooglePlayPurchase() async {
    if (_purchasePending) return;
    final attempt = ++_restoreAttempt;
    _restoreMatchedPurchase = false;
    setState(() {
      _checking = true;
      _billingMessage = 'Checking Google Play subscriptions...';
    });
    try {
      await InAppPurchase.instance.restorePurchases();
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || attempt != _restoreAttempt) return;
      if (!_isPremium && !_restoreMatchedPurchase && !_purchasePending) {
        setState(
          () => _billingMessage =
              'No active Google Play subscription was found for this account.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _billingMessage = 'Could not restore Google Play purchases.',
      );
      debugPrint('Google Play restore error: $e');
    } finally {
      if (mounted && attempt == _restoreAttempt) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _openStripeCheckout() async {
    final email = supabase.auth.currentUser?.email ?? '';
    final url = Uri.parse(
      '$_stripeCheckoutBaseUrl?prefilled_email=${Uri.encodeComponent(email)}',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
    _startPolling();
  }

  Future<void> _openSubscriptionManagement() async {
    if (_openingPortal) return;
    setState(() => _openingPortal = true);

    try {
      if (_usesGooglePlayBilling) {
        await launchUrl(
          Uri.parse('https://play.google.com/store/account/subscriptions'),
          mode: LaunchMode.externalApplication,
        );
      } else if (_usesMsStoreBilling) {
        await launchUrl(
          Uri.parse('https://account.microsoft.com/services'),
          mode: LaunchMode.externalApplication,
        );
      } else {
        final email = supabase.auth.currentUser?.email;
        if (email == null) return;
        final response = await supabase.functions.invoke(
          'manage-subscription',
          body: {'email': email},
        );
        final url = response.data['url'];
        if (url != null) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else if (mounted) {
          setState(
            () => _billingMessage =
                'No subscription portal is available for this account.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _billingMessage = 'Could not open subscription management.',
        );
      }
      debugPrint('Manage subscription error: $e');
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  // Builds the monthly + yearly plan buttons for the active billing backend.
  List<Widget> _buildPlans() {
    if (_usesGooglePlayBilling) {
      final monthly = _gpProducts[kProductIdMonthly];
      final yearly = _gpProducts[kProductIdYearly];
      return [
        _planButton(
          title: 'Monthly',
          subtitle: 'Billed monthly, cancel anytime',
          price: monthly?.price,
          highlight: false,
          onTap: (_canInteract && monthly != null)
              ? () => _buyGooglePlaySubscription(monthly)
              : null,
        ),
        _planButton(
          title: 'Yearly',
          subtitle: 'Best value',
          price: yearly?.price,
          highlight: true,
          onTap: (_canInteract && yearly != null)
              ? () => _buyGooglePlaySubscription(yearly)
              : null,
        ),
      ];
    }
    if (_usesMsStoreBilling) {
      return [
        _planButton(
          title: 'Monthly',
          subtitle: 'Billed monthly, cancel anytime',
          price: _msPrices[kProductIdMonthly],
          highlight: false,
          onTap: _canInteract
              ? () => _buyMsStoreSubscription(kProductIdMonthly)
              : null,
        ),
        _planButton(
          title: 'Yearly',
          subtitle: 'Best value',
          price: _msPrices[kProductIdYearly],
          highlight: true,
          onTap: _canInteract
              ? () => _buyMsStoreSubscription(kProductIdYearly)
              : null,
        ),
      ];
    }
    // Stripe (web / macOS / other): single monthly checkout.
    return [
      _planButton(
        title: 'Monthly',
        subtitle: 'Cancel anytime',
        price: '\$3',
        highlight: false,
        onTap: _canInteract ? _openStripeCheckout : null,
      ),
    ];
  }

  Widget _planButton({
    required String title,
    required String subtitle,
    required String? price,
    required bool highlight,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              highlight ? const Color(0xFF8B5CF6) : const Color(0xFF2A2A3E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFE2E8F0)),
                  ),
                ],
              ),
            ),
            Text(
              price ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
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
                kProIncluded
                    ? 'Pro is included with your Microsoft Store purchase.'
                    : _isPremium
                    ? 'You have an active Pro subscription.'
                    : 'Unlock premium features to keep your vault secure.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
              if (_checking || _purchasePending) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _purchasePending
                          ? 'Processing purchase...'
                          : 'Checking subscription...',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
              if (_billingMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _billingMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 13,
                  ),
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
                          color: const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          f.icon,
                          color: const Color(0xFF8B5CF6),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.desc,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isPremium)
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF22C55E),
                          size: 20,
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),
              if (_isPremium && !kProIncluded) ...[
                ElevatedButton.icon(
                  onPressed: _openingPortal
                      ? null
                      : _openSubscriptionManagement,
                  icon: _openingPortal
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.settings, size: 18),
                  label: Text(
                    _openingPortal ? 'Opening...' : 'Manage Subscription',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A3E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _usesGooglePlayBilling
                      ? 'Managed through Google Play'
                      : _usesMsStoreBilling
                          ? 'Managed through the Microsoft Store'
                          : 'Cancel, resume, or update payment method',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
              if (!_isPremium && !kProIncluded) ...[
                const Text(
                  'Choose your plan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 14),
                ..._buildPlans(),
                if (_usesGooglePlayBilling) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _checking ? null : _restoreGooglePlayPurchase,
                    child: const Text('Restore Google Play purchase'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
