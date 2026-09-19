import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/carto_basemap_config.dart';
import 'core/config/supabase_build_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CartoBasemapConfig.ensureConfigured();
  final supabaseConfig = SupabaseBuildConfig.fromEnvironment();
  supabaseConfig.ensureClientKey();
  if (supabaseConfig.isComplete) {
    await Supabase.initialize(
      url: supabaseConfig.url,
      publishableKey: supabaseConfig.publishableKey,
    );
  }
  runApp(
    ProviderScope(
      overrides: [
        supabaseBuildConfigProvider.overrideWithValue(supabaseConfig),
      ],
      child: const BicimadSocialApp(),
    ),
  );
}
