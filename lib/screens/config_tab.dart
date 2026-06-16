import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bcrypt/bcrypt.dart';
import '../admin_state.dart';
import '../models.dart';
import '../theme.dart';

class ConfigTab extends StatefulWidget {
  const ConfigTab({super.key});

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final admins = state.admins;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text("Configuración",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Parámetros de la fórmula de surtido",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text(
                      "pedido = ceil((activación_máxima − inventario) × semanas_a_surtir / semanas_restantes)\n"
                      "Valores actuales: meses_ventana=4, semanas_a_surtir=2, semanas_restantes=3.\n"
                      "Se editan en la tabla 'config' de la BD."),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text("Gestión de Administradores",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: admins.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final a = admins[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.acento,
                    child: Text(a.usuario.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(a.usuario,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      "Rol: ${a.rol} | Activo: ${a.activo ? 'Sí' : 'No'} | MFA: ${a.mfaHabilitado ? 'Sí' : 'No'}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _modalAdmin(a),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminarAdmin(a),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: () => _modalAdmin(null),
              icon: const Icon(Icons.add),
              label: const Text("Añadir Administrador"),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarAdmin(Admin a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar administrador"),
        content: Text("¿Seguro que deseas eliminar a ${a.usuario}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        await context.read<AdminState>().backend.eliminarAdmin(a.id);
        if (!mounted) return;
        await context.read<AdminState>().recargarTodo();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _modalAdmin(Admin? admin) async {
    final esNuevo = admin == null;
    final userCtrl = TextEditingController(text: admin?.usuario ?? "");
    final passCtrl = TextEditingController();
    bool activo = admin?.activo ?? true;
    bool mfa = admin?.mfaHabilitado ?? false;
    String rol = admin?.rol ?? "admin";

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(esNuevo ? "Nuevo Administrador" : "Editar Administrador"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: "Usuario"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  decoration: InputDecoration(
                      labelText: esNuevo
                          ? "Contraseña"
                          : "Nueva contraseña (opcional)"),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: rol,
                  decoration: const InputDecoration(labelText: "Rol"),
                  items: const [
                    DropdownMenuItem(value: "admin", child: Text("Admin")),
                    DropdownMenuItem(
                        value: "superadmin", child: Text("SuperAdmin")),
                  ],
                  onChanged: (val) => setLocal(() => rol = val ?? "admin"),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text("MFA Habilitado"),
                  value: mfa,
                  onChanged: (v) => setLocal(() => mfa = v),
                ),
                SwitchListTile(
                  title: const Text("Activo"),
                  value: activo,
                  onChanged: (v) => setLocal(() => activo = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (userCtrl.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("El usuario es obligatorio.")));
      return;
    }
    if (esNuevo && passCtrl.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("La contraseña es obligatoria para nuevos admins.")));
      return;
    }

    try {
      final state = context.read<AdminState>();
      String hash = admin?.passwordHash ?? "";
      if (passCtrl.text.isNotEmpty) {
        hash = BCrypt.hashpw(passCtrl.text, BCrypt.gensalt());
      }

      final a = Admin(
        id: esNuevo ? state.nuevoAdminId() : admin.id,
        usuario: userCtrl.text.trim(),
        passwordHash: hash,
        rol: rol,
        mfaHabilitado: mfa,
        activo: activo,
      );

      if (esNuevo) {
        await state.backend.crearAdmin(a, passCtrl.text);
      } else {
        await state.backend.editarAdmin(a);
      }

      if (!mounted) return;
      await state.recargarTodo();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}
