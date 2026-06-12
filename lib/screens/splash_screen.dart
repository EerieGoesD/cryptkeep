import 'package:flutter/material.dart';

import '../app.dart';
import 'auth/login_screen.dart';
import 'vault/unlock_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final authNotice = _authRedirectNotice();
    if (authNotice != null) {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialNotice: authNotice),
        ),
      );
      return;
    }

    final session = supabase.auth.currentSession;
    if (session != null && !session.isExpired) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UnlockScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  String? _authRedirectNotice() {
    final uri = Uri.base;
    final params = <String, String>{...uri.queryParameters};

    if (uri.fragment.isNotEmpty) {
      var fragment = uri.fragment;
      final queryIndex = fragment.indexOf('?');
      if (queryIndex != -1) {
        fragment = fragment.substring(queryIndex + 1);
      }
      if (fragment.contains('=')) {
        params.addAll(Uri.splitQueryString(fragment));
      }
    }

    if (params.containsKey('error')) {
      final code = params['error_code'];
      if (code == 'otp_expired') {
        return 'Email verification link expired. Please create a new account or request a new verification email.';
      }
      return 'Email verification failed. Please try again.';
    }

    if (params['type'] == 'signup' || params.containsKey('code')) {
      return 'Email verified. Please sign in.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Color(0xFF8B5CF6)),
            SizedBox(height: 16),
            Text(
              'CryptKeep',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE2E8F0),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
