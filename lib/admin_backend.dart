import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'models.dart';

/// Contrato de datos del panel admin. La UI solo conoce esta interfaz.
abstract class AdminBackend {
  // Sesión
  Future<Admin?> buscarAdmin(String usuario);

  // Lecturas
  Future<List<Vendedor>> vendedores();
  Future<List<Cliente>> clientes();
  Future<List<Ruta>> rutas();
  Future<List<Chip>> chips();
  Future<List<Escaneo>> escaneos();
  Future<String?> valorConfig(String clave);

  /// Histórico combinado (escaneos de la app + ventas de los Excel) para el
  /// dashboard. Se lee en vivo de la API.
  Future<List<VentaHist>> historicoVentas();
  // Admins
  Future<List<Admin>> admins();
  Future<void> crearAdmin(Admin a, String passwordPlano);
  Future<void> editarAdmin(Admin a);
  Future<void> eliminarAdmin(String adminId);

  // Vendedores
  Future<void> crearVendedor(Vendedor v, String passwordPlano);
  Future<void> editarVendedor(Vendedor v);
  Future<void> eliminarVendedor(String vendedorId);

  // Clientes
  Future<void> crearCliente(Cliente c);
  Future<void> editarCliente(Cliente c);
  Future<void> eliminarCliente(String clienteId);
  Future<void> reasignarCliente(String clienteId, String nuevoVendedorId);

  // Rutas
  Future<void> crearRuta(Ruta r);
  Future<void> editarRuta(Ruta r);
  Future<void> eliminarRuta(String rutaId);

  // Inventario / chips
  Future<void> asignarChipsAVendedor(List<String> iccids, String vendedorId);
  Future<void> altaChips(List<Chip> nuevos);
  Future<void> eliminarChips(List<String> iccids);
  Future<void> editarChipsMasivo(List<String> iccids, Map<String, dynamic> campos);

  // Config / killswitch
  Future<void> setConfig(String clave, String valor);

  /// Inserta filas en una tabla por lotes (para subir Excel históricos).
  /// [onProgreso] reporta (insertadas, total) para mostrar avance.
  /// Devuelve el total de filas insertadas con éxito.
  Future<int> procesarVentasConCruce(List<Map<String, dynamic>> filas, {void Function(int hechas, int total)? onProgreso});
  Future<int> insertarFilas(
    String tabla,
    List<Map<String, dynamic>> filas, {
    String accion = "Add",
    int tamLote = 100,
    void Function(int hechas, int total)? onProgreso,
  });



  factory AdminBackend.crear() =>
      Config.usarMock ? MockAdminBackend() : SupabaseAdminBackend();
}


class SupabaseAdminBackend implements AdminBackend {
  final _sb = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _fetchAll(String tabla, {String select = '*'}) async {
    final List<Map<String, dynamic>> todos = [];
    int from = 0;
    const int bloque = 1000;
    while (true) {
      final res = await _sb.from(tabla).select(select).range(from, from + bloque - 1);
      for (var row in res) {
        todos.add(row as Map<String, dynamic>);
      }
      if (res.length < bloque) break;
      from += bloque;
    }
    return todos;
  }

  @override
  Future<Admin?> buscarAdmin(String usuario) async {
    final res = await _sb.from(Config.tablaAdmins).select().eq('usuario', usuario).maybeSingle();
    return res == null ? null : Admin.fromJson(res);
  }

  @override
  Future<List<Vendedor>> vendedores() async {
    final res = await _fetchAll(Config.tablaVendedores);
    return res.map((r) => Vendedor.fromJson(r)).toList();
  }

  @override
  Future<List<Cliente>> clientes() async {
    final res = await _fetchAll(Config.tablaClientes);
    
    // Cruce manual para asignar vendedor a partir de cliente_vendedor (más robusto que join automático)
    List<Map<String, dynamic>> cv = [];
    try {
      cv = await _fetchAll('cliente_vendedor');
      cv.sort((a,b) {
         final fa = a['fecha_asig'] ?? '';
         final fb = b['fecha_asig'] ?? '';
         return fb.toString().compareTo(fa.toString()); // descendente
      });
    } catch (_) {}

    final mapVendedores = <String, String>{};
    for (var row in cv) {
      final cid = (row['cliente_id'] ?? '').toString();
      final vid = (row['vendedor_id'] ?? '').toString();
      if (cid.isNotEmpty && vid.isNotEmpty && !mapVendedores.containsKey(cid)) {
         mapVendedores[cid] = vid;
      }
    }

    return res.map((r) {
       final cli = Cliente.fromJson(r);
       if (mapVendedores.containsKey(cli.id)) {
          cli.vendedorId = mapVendedores[cli.id]!;
       }
       return cli;
    }).toList();
  }

  @override
  Future<List<Ruta>> rutas() async {
    final res = await _fetchAll("rutas");
    return res.map((j) => Ruta.fromJson(j)).toList();
  }

  @override
  Future<List<Chip>> chips() async {
    final res = await _fetchAll(Config.tablaChips);
    return res.map((j) => Chip.fromJson(j)).toList();
  }

  @override
  Future<List<Escaneo>> escaneos() async {
    final res = await _fetchAll(Config.tablaEscaneos);
    return res.map((j) => Escaneo.fromJson(j)).toList();
  }

  @override
  Future<List<VentaHist>> historicoVentas() async {
    final esc = await _fetchAll(Config.tablaEscaneos);
    final ven = await _fetchAll('ventas');
    final chipsRaw = await _fetchAll(Config.tablaChips, select: 'iccid, lada, compania, dn, estado, fecha_asig_cliente, vendedor_id, cliente_id');

    String normIccid(String icc) {
      final s = icc.trim().toUpperCase();
      if (s.length > 1 && s.endsWith('F')) return s.substring(0, s.length - 1);
      return s;
    }

    final ladaPorIccid = <String, String>{};
    final compPorIccid = <String, String>{};
    final vendedorPorIccid = <String, String>{};
    for (final c in chipsRaw) {
      final icc = normIccid((c['iccid'] ?? '').toString());
      if (icc.isEmpty) continue;
      final String ladaDb = (c['lada'] ?? '').toString().trim();
      final String dnDb = (c['dn'] ?? '').toString().trim();
      ladaPorIccid[icc] = ladaDb.isNotEmpty ? ladaDb : (dnDb.length >= 3 ? dnDb.substring(0, 3) : '');
      String compDb = (c['compania'] ?? '').toString().trim();
      if (compDb.isEmpty) compDb = 'Por definir';
      compPorIccid[icc] = compDb;
      vendedorPorIccid[icc] = (c['vendedor_id'] ?? '').toString().trim();
    }

    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

    final cls = await clientes();
    final nombrePorId = {for (final c in cls) c.id: c.nombre};
    final idPorClienteNombre = {for (final c in cls) norm(c.nombre): c.id};
    final idsClientes = cls.map((c) => c.id).toSet();

    final vends = await vendedores();
    final idPorNombre = {for (final v in vends) norm(v.nombre): v.id};
    final idsVendedores = vends.map((v) => v.id).toSet();

    final out = <VentaHist>[];
    final iccidsVistos = <String>{};

    for (final r in ven) {
      final f = _fecha(r['fecha']);
      if (f == null) continue;
      
      final vid = (r['vendedor_id'] ?? '').toString().trim();
      final vnom = (r['vendedor'] ?? '').toString().trim();
      String vendedor = '';
      if (idsVendedores.contains(vid)) {
        vendedor = vid;
      } else if (idPorNombre.containsKey(norm(vid))) {
        vendedor = idPorNombre[norm(vid)]!;
      } else if (idPorNombre.containsKey(norm(vnom))) {
        vendedor = idPorNombre[norm(vnom)]!;
      } else {
        vendedor = vid.isNotEmpty ? vid : vnom;
      }

      final cid = (r['cliente_id'] ?? '').toString().trim();
      final cnom = (r['cliente'] ?? '').toString().trim();
      String clienteId = '';
      if (idsClientes.contains(cid)) {
        clienteId = cid;
      } else if (idPorClienteNombre.containsKey(norm(cid))) {
        clienteId = idPorClienteNombre[norm(cid)]!;
      } else if (idPorClienteNombre.containsKey(norm(cnom))) {
        clienteId = idPorClienteNombre[norm(cnom)]!;
      } else {
        clienteId = cid.isNotEmpty ? cid : cnom;
      }

      final iccVenta = normIccid((r['iccid'] ?? '').toString());
      if (iccVenta.isNotEmpty) iccidsVistos.add(iccVenta);

      if (vendedor.isEmpty && iccVenta.isNotEmpty) {
        final chipVid = vendedorPorIccid[iccVenta] ?? '';
        if (chipVid.isNotEmpty) {
          if (idsVendedores.contains(chipVid)) {
            vendedor = chipVid;
          } else if (idPorNombre.containsKey(norm(chipVid))) {
            vendedor = idPorNombre[norm(chipVid)]!;
          } else {
            vendedor = chipVid;
          }
        }
      }

      final dnVenta = (r['dn'] ?? '').toString().trim();
      final ladaCalculada = dnVenta.length >= 3 ? dnVenta.substring(0, 3) : '';
      
      String prodDb = (r['producto'] ?? '').toString();
      String compDb = (r['compania'] ?? '').toString();
      if (compDb.isEmpty && iccVenta.isNotEmpty) {
        compDb = compPorIccid[iccVenta] ?? '';
      }

      out.add(VentaHist(
        fecha: f,
        vendedorId: vendedor,
        clienteId: clienteId,
        clienteNombre: nombrePorId[clienteId] ?? cnom,
        compania: companiaDeProducto(prodDb, carrier: compDb),
        lada: ladaCalculada.isNotEmpty ? ladaCalculada : (r['plaza'] ?? '').toString(),
        lat: _num(r['lat']),
        lng: _num(r['lng']),
        origen: 'venta',
      ));
    }

    for (final r in esc) {
      final f = _fecha(r['fecha_hora']);
      if (f == null) continue;
      
      final cid = (r['cliente_id'] ?? '').toString().trim();
      String clienteId = cid;
      if (!idsClientes.contains(cid)) {
        if (idPorClienteNombre.containsKey(norm(cid))) {
          clienteId = idPorClienteNombre[norm(cid)]!;
        }
      }

      final vid = (r['vendedor_id'] ?? '').toString().trim();
      String vendedor = vid;
      if (!idsVendedores.contains(vid)) {
        if (idPorNombre.containsKey(norm(vid))) {
          vendedor = idPorNombre[norm(vid)]!;
        }
      }

      final iccEsc = normIccid((r['iccid'] ?? '').toString());
      if (iccEsc.isNotEmpty && iccidsVistos.contains(iccEsc)) continue;
      if (iccEsc.isNotEmpty) iccidsVistos.add(iccEsc);

      final ladaChip = ladaPorIccid[iccEsc] ?? '';
      final compChip = compPorIccid[iccEsc];
      String compFinal = (r['compania'] ?? '').toString().trim();
      if (compFinal.isEmpty || compFinal == 'null') {
         compFinal = (compChip != null && compChip.isNotEmpty) ? compChip : 'Por definir';
      }

      out.add(VentaHist(
        fecha: f,
        vendedorId: vendedor,
        clienteId: clienteId,
        clienteNombre: nombrePorId[clienteId] ?? cid,
        compania: compFinal,
        lada: ladaChip,
        lat: _num(r['lat']),
        lng: _num(r['lng']),
        origen: 'escaneo',
      ));
    }

    for (final r in chipsRaw) {
      final icc = normIccid((r['iccid'] ?? '').toString());
      if (icc.isEmpty || iccidsVistos.contains(icc)) continue;
      
      final estado = r['estado']?.toString() ?? '';
      if (estado != 'en_cliente') continue;
      
      final f = _fecha(r['fecha_asig_cliente']) ?? DateTime.now();
      
      final cid = (r['cliente_id'] ?? '').toString().trim();
      final vid = (r['vendedor_id'] ?? '').toString().trim();
      
      String vendedor = vid;
      if (!idsVendedores.contains(vid) && idPorNombre.containsKey(norm(vid))) {
        vendedor = idPorNombre[norm(vid)]!;
      }

      String clienteId = cid;
      if (!idsClientes.contains(cid) && idPorClienteNombre.containsKey(norm(cid))) {
        clienteId = idPorClienteNombre[norm(cid)]!;
      }

      final ladaChip = ladaPorIccid[icc] ?? '';
      String compFinal = (r['compania'] ?? '').toString().trim();
      if (compFinal.isEmpty) compFinal = 'Por definir';

      out.add(VentaHist(
        fecha: f,
        vendedorId: vendedor,
        clienteId: clienteId,
        clienteNombre: nombrePorId[clienteId] ?? cid,
        compania: compFinal,
        lada: ladaChip,
        lat: 0,
        lng: 0,
        origen: 'escaneo',
      ));
      iccidsVistos.add(icc);
    }

    return out;
  }

  DateTime? _fecha(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s.replaceFirst(' ', 'T')) ?? DateTime.tryParse(s);
    if (iso != null) return iso;
    final partes = s.split(RegExp(r'[/\s:]+'));
    if (partes.length >= 3) {
      final mes = int.tryParse(partes[0]);
      final dia = int.tryParse(partes[1]);
      final anio = int.tryParse(partes[2]);
      if (mes != null && dia != null && anio != null) {
        final hora = partes.length > 3 ? int.tryParse(partes[3]) ?? 0 : 0;
        final min = partes.length > 4 ? int.tryParse(partes[4]) ?? 0 : 0;
        final seg = partes.length > 5 ? int.tryParse(partes[5]) ?? 0 : 0;
        return DateTime(anio, mes, dia, hora, min, seg);
      }
    }
    return null;
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Future<List<Admin>> admins() async {
    final res = await _sb.from('admins').select();
    return res.map((r) => Admin.fromJson(r)).toList();
  }

  @override
  Future<void> crearAdmin(Admin a, String passwordPlano) async {
    await _sb.from('admins').insert({
      "admin_id": a.id,
      "usuario": a.usuario,
      "password_hash": a.passwordHash,
      "rol": a.rol,
      "mfa_habilitado": a.mfaHabilitado,
      "activo": a.activo,
      "fecha_alta": DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> editarAdmin(Admin a) async {
    final up = {
      "usuario": a.usuario,
      "rol": a.rol,
      "mfa_habilitado": a.mfaHabilitado,
      "activo": a.activo,
    };
    if (a.passwordHash.isNotEmpty) {
      up["password_hash"] = a.passwordHash;
    }
    await _sb.from('admins').update(up).eq('admin_id', a.id);
  }

  @override
  Future<void> eliminarAdmin(String adminId) async {
    await _sb.from('admins').delete().eq('admin_id', adminId);
  }

  @override
  Future<String?> valorConfig(String clave) async {
    final res = await _sb.from(Config.tablaConfig).select('valor').eq('clave', clave).maybeSingle();
    return res == null ? null : res['valor']?.toString();
  }

  @override
  Future<void> crearVendedor(Vendedor v, String passwordPlano) async {
    await _sb.from(Config.tablaVendedores).insert({
      "vendedor_id": v.id,
      "nombre": v.nombre,
      "usuario": v.usuario,
      "password_hash": v.passwordHash,
      "activo": v.activo,
      "fecha_alta": DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> editarVendedor(Vendedor v) async {
    await _sb.from(Config.tablaVendedores).update({
      "nombre": v.nombre,
      "usuario": v.usuario,
      "password_hash": v.passwordHash,
      "activo": v.activo,
    }).eq("vendedor_id", v.id);
  }

  @override
  Future<void> eliminarVendedor(String vendedorId) async {
    await _sb.from(Config.tablaVendedores).delete().eq("vendedor_id", vendedorId);
  }

  @override
  Future<void> crearCliente(Cliente c) async {
    await _sb.from(Config.tablaClientes).insert({
      "cliente_id": c.id,
      "nombre": c.nombre,
      "activo": c.activo,
      "fecha_alta": DateTime.now().toIso8601String(),
      "ruta_id": c.rutaId.isEmpty ? null : c.rutaId,
    });
    if (c.vendedorId.isNotEmpty) {
      await _sb.from('cliente_vendedor').insert({
        "cliente_id": c.id,
        "vendedor_id": c.vendedorId,
      });
    }
  }

  @override
  Future<void> editarCliente(Cliente c) async {
    await _sb.from(Config.tablaClientes).update({
      "nombre": c.nombre,
      "activo": c.activo,
      "ruta_id": c.rutaId.isEmpty ? null : c.rutaId,
    }).eq("cliente_id", c.id);
  }

  @override
  Future<void> eliminarCliente(String clienteId) async {
    await _sb.from('cliente_vendedor').delete().eq("cliente_id", clienteId);
    await _sb.from(Config.tablaClientes).delete().eq("cliente_id", clienteId);
  }

  @override
  Future<void> reasignarCliente(String clienteId, String nuevoVendedorId) async {
    await _sb.from('cliente_vendedor').delete().eq('cliente_id', clienteId);
    if (nuevoVendedorId.isNotEmpty) {
      await _sb.from('cliente_vendedor').insert({
        "cliente_id": clienteId,
        "vendedor_id": nuevoVendedorId,
      });
    }
    try {
        await _sb.from(Config.tablaChips).update({'vendedor_id': nuevoVendedorId}).eq('cliente_id', clienteId);
    } catch (_) {}
  }

  @override
  Future<void> crearRuta(Ruta r) async {
    await _sb.from("rutas").insert(r.toJson());
  }

  @override
  Future<void> editarRuta(Ruta r) async {
    await _sb.from("rutas").update(r.toJson()).eq('id', r.id);
  }

  @override
  Future<void> eliminarRuta(String rutaId) async {
    await _sb.from("rutas").delete().eq('id', rutaId);
  }

  @override
  Future<void> asignarChipsAVendedor(List<String> iccids, String vendedorId) async {
    for (var i = 0; i < iccids.length; i += 100) {
      final lote = iccids.sublist(i, (i + 100 > iccids.length) ? iccids.length : i + 100);
      await _sb.from(Config.tablaChips).update({
        "vendedor_id": vendedorId,
        "estado": "en_vendedor",
      }).inFilter("iccid", lote);
    }
  }

  @override
  Future<void> altaChips(List<Chip> nuevos) async {
    final filas = nuevos.map((c) => {
      "iccid": c.iccid,
      "dn": c.dn,
      "producto": c.producto,
      "compania": c.compania,
      "lada": c.lada.isEmpty ? null : c.lada,
      "estado": c.estado,
      "vendedor_id": c.vendedorId.isEmpty ? null : c.vendedorId,
      "cliente_id": c.clienteId.isEmpty ? null : c.clienteId,
    }).toList();
    
    for (var i = 0; i < filas.length; i += 500) {
      final lote = filas.sublist(i, (i + 500 > filas.length) ? filas.length : i + 500);
      await _sb.from(Config.tablaChips).upsert(lote);
    }
  }

  @override
  Future<void> eliminarChips(List<String> iccids) async {
    for (var i = 0; i < iccids.length; i += 100) {
      final lote = iccids.sublist(i, (i + 100 > iccids.length) ? iccids.length : i + 100);
      await _sb.from(Config.tablaChips).delete().inFilter('iccid', lote);
    }
  }

  @override
  Future<void> editarChipsMasivo(List<String> iccids, Map<String, dynamic> campos) async {
    if (campos.isEmpty) return;
    for (var i = 0; i < iccids.length; i += 100) {
      final lote = iccids.sublist(i, (i + 100 > iccids.length) ? iccids.length : i + 100);
      await _sb.from(Config.tablaChips).update(campos).inFilter('iccid', lote);
    }
  }

  @override
  Future<void> setConfig(String clave, String valor) async {
    await _sb.from(Config.tablaConfig).upsert({"clave": clave, "valor": valor});
  }

  @override
  Future<int> insertarFilas(
    String tabla,
    List<Map<String, dynamic>> filas, {
    String accion = "Add",
    int tamLote = 500,
    void Function(int hechas, int total)? onProgreso,
  }) async {
    var hechas = 0;


    
    for (var fila in filas) {
      if (fila['vendedor_id'] != null && fila['vendedor_id'].toString().isEmpty) {
        fila.remove('vendedor_id');
      }
      if (fila['cliente_id'] != null && fila['cliente_id'].toString().isEmpty) {
        fila.remove('cliente_id');
      }
    }

    for (var i = 0; i < filas.length; i += tamLote) {
      final fin = (i + tamLote < filas.length) ? i + tamLote : filas.length;
      final lote = filas.sublist(i, fin);
      try {
        if (accion == "Add") {
          await _sb.from(tabla).insert(lote);
        } else if (accion == "Edit") {
          await _sb.from(tabla).upsert(lote);
        }
      } catch (e) {
        final ejemplo = lote.isNotEmpty ? lote.first.toString() : "(vacío)";
        throw Exception("Falló el lote en fila $i de '$tabla'.\n"
            "Ejemplo de fila enviada: $ejemplo\n"
            "Detalle: $e");
      }
      hechas += lote.length;
      onProgreso?.call(hechas, filas.length);
    }
    return hechas;
  }

  @override
  Future<int> procesarVentasConCruce(
    List<Map<String, dynamic>> filas, {
    void Function(int hechas, int total)? onProgreso,
  }) async {
    var hechas = 0;
    const tamLote = 500;

    for (var i = 0; i < filas.length; i += tamLote) {
      final fin = (i + tamLote < filas.length) ? i + tamLote : filas.length;
      final loteOriginal = filas.sublist(i, fin);
      
      final chipsData = <Map<String, dynamic>>[];
      final ventasData = <Map<String, dynamic>>[];

      for (final fila in loteOriginal) {
        final iccid = fila['iccid'];
        final compania = fila['compania'];
        final dn = fila['dn'];
        final producto = fila['producto'];
        final vendedorId = fila['vendedor_id']?.toString().isEmpty == true ? null : fila['vendedor_id'];
        final clienteId = fila['cliente_id']?.toString().isEmpty == true ? null : fila['cliente_id'];
        final fecha = fila['fecha'];
        
        // Preparar UPSERT para chips
        final chipMap = <String, dynamic>{
          'iccid': iccid,
          'estado': 'vendido',
          'fecha_vinculado_curp': fecha,
        };
        if (compania != null && compania.toString().isNotEmpty) chipMap['compania'] = compania;
        if (dn != null && dn.toString().isNotEmpty) chipMap['dn'] = dn;
        if (producto != null && producto.toString().isNotEmpty) chipMap['producto'] = producto;
        if (vendedorId != null) chipMap['vendedor_id'] = vendedorId;
        if (clienteId != null) {
          chipMap['cliente_id'] = clienteId;
          chipMap['fecha_asig_cliente'] = fecha;
        }
        chipsData.add(chipMap);

        // Preparar INSERT para ventas
        final ventaMap = <String, dynamic>{
          'fecha': fecha,
          'vendedor_id': vendedorId,
          'iccid': iccid,
          'cliente_id': clienteId,
          'monto': fila['monto'],
          'plaza': fila['plaza'],
          'lat': fila['lat'],
          'lng': fila['lng'],
        };
        // Eliminar nulos
        ventaMap.removeWhere((key, value) => value == null);
        ventasData.add(ventaMap);
      }

      try {
        await _sb.from(Config.tablaChips).upsert(chipsData);
        await _sb.from('ventas').insert(ventasData);
      } catch (e) {
        throw Exception("Falló el lote de ventas en fila $i.\\nDetalle: $e");
      }
      
      hechas += loteOriginal.length;
      onProgreso?.call(hechas, filas.length);
    }
    return hechas;
  }
}


/// ---------------------------------------------------------------------------
/// Mock en memoria. Login admin de prueba: "superadmin" / "admin" (hash abajo).
/// ---------------------------------------------------------------------------
class MockAdminBackend implements AdminBackend {
  // hash bcrypt de "admin"
  static const _hashAdmin =
      r'$2b$10$OG.8dZxjKrj3Tux9.NA6v.TEmF2rrCHBsuFdoalJ.zsvLlkY5fBsG';

  final _admins = <Admin>[
    Admin(
        id: "A001",
        usuario: "superadmin",
        passwordHash: _hashAdmin,
        rol: "superadmin",
        mfaHabilitado: true,
        activo: true),
  ];

  final _vendedores = <Vendedor>[
    Vendedor(id: "V001", nombre: "Carlos Lenin Vazquez", usuario: "carlos", passwordHash: "x", activo: true),
    Vendedor(id: "V002", nombre: "Eric Alejandro Ruiz", usuario: "eric", passwordHash: "x", activo: true),
    Vendedor(id: "V003", nombre: "Jose Manuel Rodriguez", usuario: "jose", passwordHash: "x", activo: true),
  ];

  final _clientes = <Cliente>[
    Cliente(id: "C001", nombre: "Carlos explanada", vendedorId: "V001", rutaId: "", activo: true, ultimaVisita: DateTime.now().subtract(const Duration(days: 2))),
    Cliente(id: "C002", nombre: "Dulce Ortiz", vendedorId: "V001", rutaId: "", activo: true, ultimaVisita: DateTime.now().subtract(const Duration(days: 10))),
    Cliente(id: "C003", nombre: "Miriam Sanchez", vendedorId: "V002", rutaId: "", activo: true, ultimaVisita: DateTime.now().subtract(const Duration(days: 25))),
  ];

  final _chips = <Chip>[
    Chip(iccid: "8952050102564854039F", dn: "4446584866", producto: "ACTIVA ATT 50", compania: "AT&T", estado: "en_vendedor", vendedorId: "V001", clienteId: "", lada: "444"),
    Chip(iccid: "8952050112504977675F", dn: "4446350174", producto: "ACTIVA UNE 50", compania: "UNEFON", estado: "en_vendedor", vendedorId: "V002", clienteId: "", lada: "444"),
    Chip(iccid: "8952050202532309106F", dn: "4425598889", producto: "ACTIVA ATT 50", compania: "AT&T", estado: "sin_asignar", vendedorId: "", clienteId: "", lada: "442"),
  ];

  final _config = <String, String>{"app_activa": "TRUE"};
  Future<T> _delay<T>(T v) async {
    await Future.delayed(const Duration(milliseconds: 120));
    return v;
  }

  @override
  Future<List<Escaneo>> escaneos() => _delay([]);

  @override
  Future<Admin?> buscarAdmin(String usuario) =>
      _delay(_admins.where((a) => a.usuario == usuario).cast<Admin?>().firstOrNull);

  @override
  Future<List<Vendedor>> vendedores() => _delay(List.of(_vendedores));
  @override
  Future<List<Cliente>> clientes() async {
    return _clientes;
  }

  @override
  Future<List<Ruta>> rutas() async {
    return _delay([]);
  }

  @override
  Future<List<Chip>> chips() => _delay(List.of(_chips));

  @override
  Future<int> procesarVentasConCruce(
    List<Map<String, dynamic>> filas, {
    void Function(int hechas, int total)? onProgreso,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    onProgreso?.call(filas.length, filas.length);
    return filas.length;
  }

  @override
  Future<List<VentaHist>> historicoVentas() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Genera un histórico determinista de varios meses, vendedores y compañías
    // para poder ver el dashboard sin backend. Reemplazado por datos reales al
    // conectar AppSheet.
    final companias = ["AT&T", "UNEFON", "TELCEL", "MOVISTAR"];
    final ladas = ["444", "481", "487", "488"];
    final clientesPorVend = {
      "V001": ["Carlos explanada", "Dulce Ortiz"],
      "V002": ["Miriam Sanchez", "Karla 1"],
      "V003": ["Angeles Hernandez", "Adán Romero"],
    };
    final out = <VentaHist>[];
    var seed = 7;
    int rnd(int n) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % n;
    }

    for (var mesAtras = 5; mesAtras >= 0; mesAtras--) {
      final base = DateTime(2026, 3, 1);
      final fecha = DateTime(base.year, base.month - mesAtras, 1 + rnd(27));
      for (final v in clientesPorVend.entries) {
        for (final cli in v.value) {
          for (final comp in companias) {
            final cuantas = rnd(8); // 0..7 ventas de esa compañía ese mes
            for (var k = 0; k < cuantas; k++) {
              out.add(VentaHist(
                fecha: fecha.add(Duration(days: rnd(20))),
                vendedorId: v.key,
                clienteId: cli,
                clienteNombre: cli,
                compania: comp,
                lada: ladas[rnd(ladas.length)],
                lat: 22.15 + rnd(100) / 1000.0,
                lng: -100.97 + rnd(100) / 1000.0,
                origen: mesAtras == 0 ? "escaneo" : "venta",
              ));
            }
          }
        }
      }
    }
    return out;
  }
  @override
  Future<String?> valorConfig(String clave) => _delay(_config[clave]);

  @override
  Future<void> crearVendedor(Vendedor v, String passwordPlano) =>
      _delay(_vendedores.add(v));
  @override
  Future<void> editarVendedor(Vendedor v) async {
    final i = _vendedores.indexWhere((x) => x.id == v.id);
    if (i >= 0) _vendedores[i] = v;
    return _delay(null);
  }

  @override
  Future<List<Admin>> admins() async => _delay(_admins);

  @override
  Future<void> crearAdmin(Admin a, String passwordPlano) async {
    _admins.add(a);
  }

  @override
  Future<void> editarAdmin(Admin a) async {
    final i = _admins.indexWhere((x) => x.id == a.id);
    if (i >= 0) _admins[i] = a;
  }

  @override
  Future<void> eliminarAdmin(String adminId) async {
    _admins.removeWhere((x) => x.id == adminId);
  }

  @override
  Future<void> eliminarVendedor(String vendedorId) =>
      _delay(_vendedores.removeWhere((x) => x.id == vendedorId));

  @override
  Future<void> crearCliente(Cliente c) => _delay(_clientes.add(c));
  @override
  Future<void> editarCliente(Cliente c) async {
    final idx = _clientes.indexWhere((x) => x.id == c.id);
    if (idx != -1) _clientes[idx] = c;
    return _delay(null);
  }

  @override
  Future<void> crearRuta(Ruta r) => _delay(null);

  @override
  Future<void> editarRuta(Ruta r) => _delay(null);

  @override
  Future<void> eliminarRuta(String id) => _delay(null);

  @override
  Future<void> eliminarCliente(String clienteId) =>
      _delay(_clientes.removeWhere((x) => x.id == clienteId));

  @override
  Future<void> reasignarCliente(String clienteId, String nuevoVendedorId) async {
    final i = _clientes.indexWhere((x) => x.id == clienteId);
    if (i >= 0) _clientes[i].vendedorId = nuevoVendedorId;
    return _delay(null);
  }

  @override
  Future<void> asignarChipsAVendedor(List<String> iccids, String vendedorId) async {
    for (final ic in iccids) {
      final i = _chips.indexWhere((x) => x.iccid == ic);
      if (i >= 0) {
        _chips[i].vendedorId = vendedorId;
        _chips[i].estado = "en_vendedor";
      }
    }
    return _delay(null);
  }

  @override
  Future<void> altaChips(List<Chip> nuevos) => _delay(_chips.addAll(nuevos));

  @override
  Future<void> eliminarChips(List<String> iccids) async {
    _chips.removeWhere((c) => iccids.contains(c.iccid));
    return _delay(null);
  }

  @override
  Future<void> editarChipsMasivo(List<String> iccids, Map<String, dynamic> campos) async {
    for (var c in _chips) {
      if (iccids.contains(c.iccid)) {
        if (campos.containsKey('estado')) c.estado = campos['estado'];
        if (campos.containsKey('compania')) c.compania = campos['compania'];
        if (campos.containsKey('vendedor_id')) c.vendedorId = campos['vendedor_id'];
      }
    }
    return _delay(null);
  }

  @override
  Future<void> setConfig(String clave, String valor) =>
      _delay(_config[clave] = valor);

  @override
  Future<int> insertarFilas(
    String tabla,
    List<Map<String, dynamic>> filas, {
    String accion = "Add",
    int tamLote = 100,
    void Function(int hechas, int total)? onProgreso,
  }) async {
    var hechas = 0;


    for (var i = 0; i < filas.length; i += tamLote) {
      final fin = (i + tamLote < filas.length) ? i + tamLote : filas.length;
      await Future.delayed(const Duration(milliseconds: 200));
      hechas = fin;
      onProgreso?.call(hechas, filas.length);
    }
    return hechas;
  }
}
