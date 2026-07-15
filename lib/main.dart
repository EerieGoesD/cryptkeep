import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'providers/app_state.dart';
import 'screens/autofill/autofill_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const CryptKeepApp(),
    ),
  );
}

/// Entrypoint used by AutofillActivity when another app requests a password.
/// Runs the small autofill picker instead of the full app.
@pragma('vm:entry-point')
void autofillEntryPoint() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const AutofillApp());
}
