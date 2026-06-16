import 'package:flutter/foundation.dart';
import 'admin_backend.dart';
import 'models.dart';

/// Estado global del panel: sesión del admin + cachés de cada tabla.
/// Las pantallas leen de aquí y llaman a recargar tras cada cambio.
class AdminState extends ChangeNotifier {
  final AdminBackend backend = AdminBackend.crear();

  Admin? admin;
  List<Vendedor> vendedores = [];
  List<Cliente> clientes = [];
  List<Ruta> rutas = [];
  List<Chip> chips = [];
  List<Escaneo> escaneos = [];
  List<Admin> admins = [];
  bool appActiva = true;

  void iniciarSesion(Admin a) {
    admin = a;
    notifyListeners();
  }

  void cerrarSesion() {
    admin = null;
    notifyListeners();
  }

  Future<void> recargarTodo() async {
    final res = await Future.wait([
      backend.vendedores(),
      backend.clientes(),
      backend.rutas(),
      backend.chips(),
      backend.escaneos(),
      backend.admins(),
      backend.valorConfig("app_activa"),
    ]);
    vendedores = (res[0] as List<Vendedor>)..sort((a, b) => a.nombre.compareTo(b.nombre));
    clientes = (res[1] as List<Cliente>)..sort((a, b) => a.nombre.compareTo(b.nombre));
    rutas = (res[2] as List<Ruta>)..sort((a, b) => a.nombre.compareTo(b.nombre));
    chips = res[3] as List<Chip>;
    escaneos = res[4] as List<Escaneo>;
    admins = (res[5] as List<Admin>)..sort((a, b) => a.usuario.compareTo(b.usuario));
    appActiva = ((res[6] as String?) ?? "TRUE").toUpperCase() == "TRUE";
    notifyListeners();
  }

  String nombreVendedor(String id) =>
      vendedores.where((v) => v.id == id).map((v) => v.nombre).firstOrNull ?? id;

  String nombreCliente(String id) =>
      clientes.where((c) => c.id == id).map((c) => c.nombre).firstOrNull ?? id;

  /// IDs incrementales simples para el mock (en AppSheet puedes usar UNIQUEID()).
  String nuevoVendedorId() {
    final n = vendedores.length + 1;
    return "V${n.toString().padLeft(3, '0')}";
  }

  String nuevoClienteId() {
    final n = clientes.length + 1;
    return "C${n.toString().padLeft(4, '0')}";
  }

  String nuevoAdminId() {
    final n = admins.length + 1;
    return "A${n.toString().padLeft(3, '0')}";
  }

  DateTime? ultimaVisitaCliente(String id) {
    DateTime? ultima;
    for (final c in chips) {
      if (c.clienteId == id && c.fechaAsigCliente != null) {
        if (ultima == null || c.fechaAsigCliente!.isAfter(ultima)) {
          ultima = c.fechaAsigCliente;
        }
      }
    }
    return ultima;
  }
}
