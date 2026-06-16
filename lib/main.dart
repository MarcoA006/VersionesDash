import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_state.dart';
import 'config.dart';
import 'theme.dart';
import 'screens/login_admin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => AdminState(),
      child: const AccAdminApp(),
    ),
  );
}

class AccAdminApp extends StatelessWidget {
  const AccAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Panel Admin — Ventas Chips",
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const LoginAdminScreen(),
    );
  }
}
