import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../models.dart';
import '../theme.dart';

class RutasTab extends StatelessWidget {
  const RutasTab({super.key});

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
              const Text("Rutas",
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
                label: const Text("Nueva ruta"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: state.rutas.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = state.rutas[i];
                  final v = state.vendedores.where((v) => v.id == r.vendedorId).firstOrNull;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: r.activa ? AppColors.acento : Colors.grey,
                      child: const Icon(Icons.map, color: Colors.white),
                    ),
                    title: Text(r.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Vendedor: ${v?.nombre ?? 'Sin asignar'}  ·  ${r.activa ? 'Activa' : 'Inactiva'}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: "Modificar",
                          onPressed: () => _editar(context, r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.alerta),
                          tooltip: "Eliminar",
                          onPressed: () => _eliminar(context, r),
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

  Future<void> _editar(BuildContext context, Ruta? r) async {
    final state = context.read<AdminState>();
    final nombreCtrl = TextEditingController(text: r?.nombre ?? "");
    String? vendedorSel = r?.vendedorId;
    bool activa = r?.activa ?? true;
    final esNueva = r == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(esNueva ? "Nueva ruta" : "Modificar ruta"),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: "Nombre de la ruta")),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Vendedor asignado"),
                  value: (vendedorSel != null && vendedorSel!.isNotEmpty && state.vendedores.any((v) => v.id == vendedorSel)) ? vendedorSel : null,
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Sin asignar")),
                    ...state.vendedores.map((v) => DropdownMenuItem(value: v.id, child: Text(v.nombre))),
                  ],
                  onChanged: (v) => setLocal(() => vendedorSel = v),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Activa"),
                  value: activa,
                  onChanged: (x) => setLocal(() => activa = x),
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
    if (!context.mounted) return;
    if (nombreCtrl.text.trim().isEmpty) {
      _msg(context, "El nombre de la ruta es obligatorio.");
      return;
    }

    try {
      if (esNueva) {
        await state.backend.crearRuta(
          Ruta(
            id: "",
            nombre: nombreCtrl.text.trim(),
            vendedorId: vendedorSel ?? "",
            activa: activa,
          ),
        );
      } else {
        r.nombre = nombreCtrl.text.trim();
        r.vendedorId = vendedorSel ?? "";
        r.activa = activa;
        await state.backend.editarRuta(r);
      }
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Guardado.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  Future<void> _eliminar(BuildContext context, Ruta r) async {
    final state = context.read<AdminState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar ruta"),
        content: Text("¿Eliminar la ruta ${r.nombre}? Los clientes asignados quedarán sin ruta."),
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
    if (!context.mounted) return;
    try {
      await state.backend.eliminarRuta(r.id);
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Ruta eliminada.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  void _msg(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
