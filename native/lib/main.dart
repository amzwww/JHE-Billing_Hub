import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    const qaRefreshToken = String.fromEnvironment('QA_REFRESH_TOKEN');
    if (qaRefreshToken.isNotEmpty &&
        Supabase.instance.client.auth.currentSession == null) {
      await Supabase.instance.client.auth.setSession(qaRefreshToken);
    }
  }

  runApp(const BillsMakerApp());
}
