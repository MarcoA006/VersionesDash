import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import '../updater.dart';
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../theme.dart';
import 'home_admin_screen.dart';

class LoginAdminScreen extends StatefulWidget {
  const LoginAdminScreen({super.key});

  @override
  State<LoginAdminScreen> createState() => _LoginAdminScreenState();
}

class _LoginAdminScreenState extends State<LoginAdminScreen> {
  final _userCtrl = TextEditingController(text: "superadmin");
  final _passCtrl = TextEditingController();
  final _mfaCtrl = TextEditingController();
  bool _validando = false;
  bool _pidiendoMfa = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AutoUpdater.checkForUpdates(context);
    });
  }

  Future<void> _entrar() async {
    setState(() {
      _validando = true;
      _error = null;
    });
    final state = context.read<AdminState>();
    try {
      final admin = await state.backend.buscarAdmin(_userCtrl.text.trim());
      if (admin == null || !admin.activo) {
        _fallar("Usuario no encontrado o inactivo.");
        return;
      }
      bool ok;
      try {
        ok = BCrypt.checkpw(_passCtrl.text, admin.passwordHash);
      } catch (_) {
        ok = false;
      }
      if (!ok) {
        _fallar("Contraseña incorrecta.");
        return;
      }

      // MFA: si está habilitado, pedimos un segundo factor antes de entrar.
      // En el mock aceptamos el código "000000" como placeholder; en producción
      // se valida contra TOTP (Google Authenticator) o un código por correo.
      if (admin.mfaHabilitado && !_pidiendoMfa) {
        setState(() {
          _pidiendoMfa = true;
          _validando = false;
        });
        return;
      }
      if (admin.mfaHabilitado && _mfaCtrl.text.trim() != "000000") {
        _fallar("Código MFA incorrecto.");
        return;
      }

      await state.recargarTodo();
      if (!mounted) return;
      state.iniciarSesion(admin);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeAdminScreen()),
      );
    } catch (e) {
      _fallar("Error: $e");
    }
  }

  void _fallar(String msg) {
    setState(() {
      _validando = false;
      _error = msg;
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _mfaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.superficie,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.admin_panel_settings, size: 56, color: AppColors.acento),
                const SizedBox(height: 8),
                const Text("Panel de administración",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                if (!_pidiendoMfa) ...[
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                        labelText: "Usuario", prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: "Contraseña", prefixIcon: Icon(Icons.lock)),
                    onSubmitted: (_) => _entrar(),
                  ),
                ] else ...[
                  const Text("Verificación en dos pasos",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text("Ingresa el código de 6 dígitos.",
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mfaCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                        labelText: "Código MFA",
                        prefixIcon: Icon(Icons.shield),
                        counterText: ""),
                    onSubmitted: (_) => _entrar(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.alerta, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _validando ? null : _entrar,
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: _validando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 3))
                      : Text(_pidiendoMfa ? "VERIFICAR" : "ENTRAR"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
