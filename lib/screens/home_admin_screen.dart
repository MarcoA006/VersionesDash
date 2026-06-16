import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../theme.dart';
import 'login_admin_screen.dart';
import 'vendedores_tab.dart';
import 'clientes_tab.dart';
import 'inventario_tab.dart';
import 'cargar_tab.dart';
import 'config_tab.dart';
import 'dashboard_tab.dart';
import 'surtido_tab.dart';
import 'rutas_tab.dart';

class HomeAdminScreen extends StatefulWidget {
  const HomeAdminScreen({super.key});

  @override
  State<HomeAdminScreen> createState() => _HomeAdminScreenState();
}

class _HomeAdminScreenState extends State<HomeAdminScreen> {
  int _idx = 0;

  final _secciones = const [
    (icon: Icons.dashboard, label: "Dashboard"),
    (icon: Icons.local_shipping, label: "Surtido"),
    (icon: Icons.people, label: "Vendedores"),
    (icon: Icons.storefront, label: "Clientes"),
    (icon: Icons.map, label: "Rutas"),
    (icon: Icons.sim_card, label: "Inventario"),
    (icon: Icons.upload_file, label: "Cargar Excel"),
    (icon: Icons.settings, label: "Configuración"),
  ];

  Widget _cuerpo() {
    switch (_idx) {
      case 0:
        return const DashboardTab();
      case 1:
        return const SurtidoTab();
      case 2:
        return const VendedoresTab();
      case 3:
        return const ClientesTab();
      case 4:
        return const RutasTab();
      case 5:
        return const InventarioTab();
      case 6:
        return const CargarTab();
      default:
        return const ConfigTab();
    }
  }

  void _salir() {
    context.read<AdminState>().cerrarSesion();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginAdminScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 200,
            backgroundColor: AppColors.acento,
            selectedIndex: _idx,
            onDestinationSelected: (i) => setState(() => _idx = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
              child: Column(
                children: [
                  const Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 36),
                  const SizedBox(height: 6),
                  Text(state.admin?.usuario ?? "",
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextButton.icon(
                    onPressed: _salir,
                    icon: const Icon(Icons.logout, color: Colors.white70),
                    label: const Text("Salir",
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            selectedIconTheme: const IconThemeData(color: Colors.white),
            unselectedIconTheme: const IconThemeData(color: Colors.white60),
            selectedLabelTextStyle: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white60),
            destinations: _secciones
                .map((s) => NavigationRailDestination(
                      icon: Icon(s.icon),
                      label: Text(s.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (!state.appActiva) _bannerBloqueo(),
                Expanded(child: _cuerpo()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerBloqueo() {
    return Container(
      width: double.infinity,
      color: AppColors.alerta,
      padding: const EdgeInsets.all(8),
      child: const Text(
        "⚠ KILLSWITCH ACTIVO — la app móvil está bloqueada para todos los vendedores.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
