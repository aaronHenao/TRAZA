import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/tracking/tracking_screen.dart';
import 'supabase_config.dart';
import 'theme/traza_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const ProviderScope(child: TrazaApp()));
}

class TrazaApp extends StatelessWidget {
  const TrazaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TRAZA',
      debugShowCheckedModeBanner: false,
      theme: buildTrazaTheme(),
      // Mientras no exista la pantalla de inicio (SCRUM-45), la app
      // abre directamente el entrenamiento en curso.
      home: const TrackingScreen(nombreActividad: 'Correr'),
    );
  }
}
