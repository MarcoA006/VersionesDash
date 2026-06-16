import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../models.dart';
import '../theme.dart';

class VendedoresTab extends StatelessWidget {
  const VendedoresTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text("Vendedores",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => context.read<AdminState>().recargarTodo(),
                icon: const Icon(Icons.refresh),
                label: const Text("Actualizar"),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _editar(context, null),
                icon: const Icon(Icons.add),
                label: const Text("Nuevo vendedor"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: state.vendedores.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final v = state.vendedores[i];
                  final nClientes =
                      state.clientes.where((c) => c.vendedorId == v.id).length;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          v.activo ? AppColors.acento : Colors.grey,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(v.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "usuario: ${v.usuario}  ·  $nClientes clientes  ·  ${v.activo ? "activo" : "inactivo"}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: "Modificar",
                          onPressed: () => _editar(context, v),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.alerta),
                          tooltip: "Eliminar",
                          onPressed: () => _eliminar(context, v, nClientes),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editar(BuildContext context, Vendedor? v) async {
    final state = context.read<AdminState>();
    final nombreCtrl = TextEditingController(text: v?.nombre ?? "");
    final usuarioCtrl = TextEditingController(text: v?.usuario ?? "");
    final passCtrl = TextEditingController();
    bool activo = v?.activo ?? true;
    final esNuevo = v == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(esNuevo ? "Nuevo vendedor" : "Modificar vendedor"),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: "Nombre")),
                const SizedBox(height: 10),
                TextField(
                    controller: usuarioCtrl,
                    decoration: const InputDecoration(labelText: "Usuario")),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: esNuevo
                        ? "Contraseña"
                        : "Nueva contraseña (dejar vacío = no cambiar)",
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Activo"),
                  value: activo,
                  onChanged: (x) => setLocal(() => activo = x),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancelar")),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Guardar")),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (nombreCtrl.text.trim().isEmpty || usuarioCtrl.text.trim().isEmpty) {
      _msg(context, "Nombre y usuario son obligatorios.");
      return;
    }
    if (esNuevo && passCtrl.text.isEmpty) {
      _msg(context, "La contraseña es obligatoria para un vendedor nuevo.");
      return;
    }

    try {
      if (esNuevo) {
        final hash = BCrypt.hashpw(passCtrl.text, BCrypt.gensalt());
        await state.backend.crearVendedor(
          Vendedor(
            id: state.nuevoVendedorId(),
            nombre: nombreCtrl.text.trim(),
            usuario: usuarioCtrl.text.trim(),
            passwordHash: hash,
            activo: activo,
          ),
          passCtrl.text,
        );
      } else {
        v.nombre = nombreCtrl.text.trim();
        v.usuario = usuarioCtrl.text.trim();
        v.activo = activo;
        if (passCtrl.text.isNotEmpty) {
          v.passwordHash = BCrypt.hashpw(passCtrl.text, BCrypt.gensalt());
        }
        await state.backend.editarVendedor(v);
      }
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Guardado.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  Future<void> _eliminar(
      BuildContext context, Vendedor v, int nClientes) async {
    final state = context.read<AdminState>();

    // Regla pedida: no se puede eliminar un vendedor con clientes; primero hay
    // que reasignarlos o eliminarlos.
    if (nClientes > 0) {
      _msg(context,
          "No puedes eliminar a ${v.nombre}: tiene $nClientes cliente(s). Reasígnalos o elimínalos primero en la pestaña Clientes.");
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar vendedor"),
        content: Text("¿Eliminar a ${v.nombre}? Esta acción no se puede deshacer."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.alerta),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.backend.eliminarVendedor(v.id);
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Vendedor eliminado.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  void _msg(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
