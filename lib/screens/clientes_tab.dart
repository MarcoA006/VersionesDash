import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../models.dart';
import '../theme.dart';

class ClientesTab extends StatefulWidget {
  const ClientesTab({super.key});

  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> {
  final _filtroCtrl = TextEditingController();
  String _q = "";
  String? _filtroVendedorId;
  String? _filtroRutaId;

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final lista = state.clientes.where((c) {
      if (!c.nombre.toLowerCase().contains(_q)) return false;
      if (_filtroVendedorId != null && c.vendedorId != _filtroVendedorId) return false;
      if (_filtroRutaId != null && c.rutaId != _filtroRutaId) return false;
      return true;
    }).toList();
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text("Clientes",
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
                label: const Text("Nuevo cliente"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _filtroCtrl,
                  decoration: const InputDecoration(
                      labelText: "Buscar cliente", prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Vendedor"),
                  value: _filtroVendedorId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Todos")),
                    ...state.vendedores.map((v) => DropdownMenuItem(value: v.id, child: Text(v.nombre))),
                  ],
                  onChanged: (v) => setState(() {
                    _filtroVendedorId = v;
                    _filtroRutaId = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Ruta"),
                  value: _filtroRutaId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Todas")),
                    ...state.rutas
                        .where((r) => _filtroVendedorId == null || r.vendedorId == _filtroVendedorId)
                        .map((r) => DropdownMenuItem(value: r.id, child: Text(r.nombre))),
                  ],
                  onChanged: (v) => setState(() => _filtroRutaId = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: lista.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = lista[i];
                  return ListTile(
                    leading: Icon(Icons.storefront,
                        color: c.activo ? AppColors.acento : Colors.grey),
                    title: Text(c.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "Vendedor: ${state.nombreVendedor(c.vendedorId)}  ·  ${c.activo ? "activo" : "inactivo"}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.swap_horiz),
                          tooltip: "Reasignar a otro vendedor",
                          onPressed: () => _reasignar(context, c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: "Modificar",
                          onPressed: () => _editar(context, c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.alerta),
                          tooltip: "Eliminar",
                          onPressed: () => _eliminar(context, c),
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

  Future<void> _editar(BuildContext context, Cliente? c) async {
    final state = context.read<AdminState>();
    final nombreCtrl = TextEditingController(text: c?.nombre ?? "");
    String? vendedorId = c?.vendedorId;
    if (vendedorId != null && !state.vendedores.any((v) => v.id == vendedorId)) {
      vendedorId = null;
    }
    String? rutaId = c?.rutaId;
    if (rutaId != null && !state.rutas.any((r) => r.id == rutaId)) {
      rutaId = null;
    }
    bool activo = c?.activo ?? true;
    final esNuevo = c == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(esNuevo ? "Nuevo cliente" : "Modificar cliente"),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: "Nombre")),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: vendedorId,
                  decoration: const InputDecoration(labelText: "Asignar a vendedor"),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Sin asignar")),
                    ...state.vendedores.map((v) => DropdownMenuItem(value: v.id, child: Text(v.nombre))),
                  ],
                  onChanged: (x) => setLocal(() {
                    vendedorId = x;
                    if (rutaId != null) {
                      final r = state.rutas.where((r) => r.id == rutaId).firstOrNull;
                      if (r != null && r.vendedorId != vendedorId) {
                        rutaId = null;
                      }
                    }
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: rutaId,
                  decoration: const InputDecoration(labelText: "Asignar a ruta"),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Sin ruta")),
                    ...state.rutas
                        .where((r) => vendedorId == null || r.vendedorId == vendedorId)
                        .map((r) => DropdownMenuItem(value: r.id, child: Text(r.nombre))),
                  ],
                  onChanged: (x) => setLocal(() => rutaId = x),
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
    if (nombreCtrl.text.trim().isEmpty) {
      _msg(context, "El nombre es obligatorio.");
      return;
    }
    try {
      if (esNuevo) {
        await state.backend.crearCliente(Cliente(
          id: state.nuevoClienteId(),
          nombre: nombreCtrl.text.trim(),
          vendedorId: vendedorId ?? "",
          rutaId: rutaId ?? "",
          activo: activo,
        ));
      } else {
        final vendedorIdAntiguo = c!.vendedorId;
        c.nombre = nombreCtrl.text.trim();
        c.activo = activo;
        c.vendedorId = vendedorId ?? "";
        c.rutaId = rutaId ?? "";
        await state.backend.editarCliente(c);
        if (vendedorIdAntiguo != c.vendedorId) {
          await state.backend.reasignarCliente(c.id, c.vendedorId);
        }
      }
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Guardado.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  Future<void> _reasignar(BuildContext context, Cliente c) async {
    final state = context.read<AdminState>();
    String? destino = c.vendedorId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text("Reasignar a ${c.nombre}"),
          content: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: destino,
            decoration: const InputDecoration(labelText: "Nuevo vendedor"),
            items: state.vendedores
                .map((v) =>
                    DropdownMenuItem(value: v.id, child: Text(v.nombre)))
                .toList(),
            onChanged: (x) => setLocal(() => destino = x),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancelar")),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Reasignar")),
          ],
        ),
      ),
    );
    if (ok != true || destino == null) return;
    try {
      await state.backend.reasignarCliente(c.id, destino!);
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Cliente reasignado.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  Future<void> _eliminar(BuildContext context, Cliente c) async {
    final state = context.read<AdminState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar cliente"),
        content: Text("¿Eliminar a ${c.nombre}?"),
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
      await state.backend.eliminarCliente(c.id);
      await state.recargarTodo();
      if (context.mounted) _msg(context, "Cliente eliminado.");
    } catch (e) {
      if (context.mounted) _msg(context, "Error: $e");
    }
  }

  void _msg(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
