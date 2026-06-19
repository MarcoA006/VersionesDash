import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../admin_state.dart';
import '../models.dart';
import '../theme.dart';

/// Carga de los tres reportes. Lee el Excel, mapea las columnas según el tipo
/// de reporte y escribe a la BD por lotes vía API, mostrando progreso.
///
/// - "ventas"      -> tabla `ventas`   (histórico que alimenta el dashboard)
/// - "inv_vendedor"-> tabla `chips`    (chips en manos del vendedor)
/// - "inv_cliente" -> pendiente (el PDF tiene nombres pegados; 2da etapa)
class CargarTab extends StatefulWidget {
  const CargarTab({super.key});

  @override
  State<CargarTab> createState() => _CargarTabState();
}

class _CargarTabState extends State<CargarTab> {
  String _log = "Selecciona un archivo para comenzar.";
  bool _trabajando = false;
  double _progreso = 0;

  /// Normaliza un nombre para cruzarlo (quita dobles espacios y baja a minúsculas).
  String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  /// Compañía a partir del texto del producto (y opcionalmente del carrier).
  String _comp(String producto, {String carrier = ''}) =>
      companiaDeProducto(producto, carrier: carrier);

  /// Convierte el valor de celda a texto plano legible.
  String _cell(xls.Data? d) {
    final v = d?.value;
    if (v == null) return '';
    if (v is xls.TextCellValue) return v.value.toString();
    if (v is xls.IntCellValue) return v.value.toString();
    if (v is xls.DoubleCellValue) return v.value.toString();
    if (v is xls.DateCellValue) {
      return '${v.year.toString().padLeft(4, '0')}-'
          '${v.month.toString().padLeft(2, '0')}-'
          '${v.day.toString().padLeft(2, '0')}';
    }
    if (v is xls.DateTimeCellValue) {
      return '${v.year.toString().padLeft(4, '0')}-'
          '${v.month.toString().padLeft(2, '0')}-'
          '${v.day.toString().padLeft(2, '0')} '
          '${v.hour.toString().padLeft(2, '0')}:'
          '${v.minute.toString().padLeft(2, '0')}:'
          '${v.second.toString().padLeft(2, '0')}';
    }
    return v.toString();
  }

  /// Normaliza una fecha dd/mm/yyyy o yyyy-mm-dd a ISO yyyy-mm-dd.
  String _fechaIso(String s) {
    s = s.trim();
    if (s.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return s.split(' ').first;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m != null) {
      final d = m.group(1)!.padLeft(2, '0');
      final mo = m.group(2)!.padLeft(2, '0');
      return '${m.group(3)}-$mo-$d';
    }
    return s;
  }

  Future<void> _subir(String tipo) async {
    final state = context.read<AdminState>();

    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["xlsx"],
      withData: true,
    );
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }

    setState(() {
      _trabajando = true;
      _progreso = 0;
      _log = "Leyendo ${res.files.first.name}...";
    });

    try {
      final libro = xls.Excel.decodeBytes(res.files.first.bytes!);
      final hoja = libro.tables.values.first;
      final filas = hoja.rows;

      // Encabezado en la fila índice 2 (fila 3 visible).
      if (filas.length <= 3) {
        _fin("El archivo no tiene filas de datos (encabezado en fila 3).");
        return;
      }
      final encab = filas[2].map((c) => _norm(_cell(c))).toList();
      int col(String nombre) => encab.indexOf(_norm(nombre));

      // Mapa nombre_vendedor -> vendedor_id, para resolver referencias.
      final idPorNombre = {
        for (final v in state.vendedores) _norm(v.nombre): v.id
      };
      final idPorCliente = {
        for (final c in state.clientes) _norm(c.nombre): c.id
      };

      List<Map<String, dynamic>> registros = [];
      String tablaDestino;

      String _normIccid(String icc) {
        final s = icc.trim().toUpperCase();
        if (s.length > 1 && s.endsWith('F')) return s.substring(0, s.length - 1);
        return s;
      }

      if (tipo == "ventas") {
        tablaDestino = "ventas";
        final cFecha = col("fecha"),
            cVend = col("vendedor"),
            cCli = col("cliente"),
            cMonto = col("monto"),
            cIcc = col("iccid"),
            cDn = col("dn"),
            cProd = col("producto"),
            cPlaza = col("plaza");
        if ([cFecha, cVend, cProd].contains(-1)) {
          _fin("No encuentro las columnas esperadas (fecha, vendedor, producto).");
          return;
        }
        for (var i = 3; i < filas.length; i++) {
          final r = filas[i];
          final vendNombre = _cell(r[cVend]).trim();
          if (vendNombre.isEmpty || vendNombre.toLowerCase() == "vendedor") continue;
          final vid = idPorNombre[_norm(vendNombre)] ?? "";

          final prod = _cell(r[cProd]).trim();
          if (prod.isEmpty || prod == "0" || prod == "0.0" || prod.toLowerCase() == "producto") continue;

          final iccRaw = cIcc >= 0 ? _cell(r[cIcc]).trim() : "";
          if (iccRaw.toLowerCase() == "iccid" || iccRaw.toLowerCase() == "icc") continue;
          final icc = _normIccid(iccRaw);

          final cliNombre = cCli >= 0 ? _cell(r[cCli]).trim() : "";
          final cid = idPorCliente[_norm(cliNombre)] ?? "";

          final fila = <String, dynamic>{
            "fecha": _fechaIso(_cell(r[cFecha])),
            "vendedor": vendNombre,
            "cliente": cliNombre,
            "iccid": icc,
            "producto": prod,
            "plaza": cPlaza >= 0 ? _cell(r[cPlaza]) : "",
            "compania": _comp(prod),
          };
          if (vid.isNotEmpty) fila["vendedor_id"] = vid;
          if (cid.isNotEmpty) fila["cliente_id"] = cid;
          final montoStr = cMonto >= 0 ? _cell(r[cMonto]) : "";
          final monto = double.tryParse(montoStr);
          if (monto != null) fila["monto"] = monto;

          final dnStr = cDn >= 0 ? _cell(r[cDn]).trim() : "";
          final dnVal = double.tryParse(dnStr);
          if (dnVal != null) {
            fila["dn"] = dnStr;
          }
          registros.add(fila);
        }
      } else if (tipo == "inv_vendedor") {
        tablaDestino = "chips";
        final cFecha = col("fecha asignacion vendedor"),
            cVend = col("vendedor"),
            cProd = col("producto"),
            cIcc = col("iccid"),
            cDn = col("dn"),
            cCarrierVend = col("carrier") != -1 ? col("carrier") : col("compañía");  // columna carrier/compañía opcional
        if ([cIcc, cVend, cProd].contains(-1)) {
          _fin("No encuentro las columnas esperadas (iccid, vendedor, producto).");
          return;
        }
        for (var i = 3; i < filas.length; i++) {
          final r = filas[i];
          final iccRaw = _cell(r[cIcc]).trim();
          if (iccRaw.isEmpty || iccRaw.toLowerCase() == "iccid" || iccRaw.toLowerCase() == "icc") continue;
          final icc = _normIccid(iccRaw);

          final prod = _cell(r[cProd]).trim();
          if (prod.isEmpty || prod == "0" || prod == "0.0" || prod.toLowerCase() == "producto") continue;

          final vendNombre = _cell(r[cVend]).trim();
          final vid = idPorNombre[_norm(vendNombre)] ?? "";
          final carrierVend = cCarrierVend >= 0 ? _cell(r[cCarrierVend]).trim() : '';
          final compDetectada = _comp(prod, carrier: carrierVend);
          final fila = <String, dynamic>{
            "iccid": icc,
            "producto": prod,
            "compania": compDetectada,
            "estado": "en_vendedor",
            "fecha_asig_vendedor":
                cFecha >= 0 ? _fechaIso(_cell(r[cFecha])) : "",
          };
          if (vid.isNotEmpty) fila["vendedor_id"] = vid;

          final dnStr = cDn >= 0 ? _cell(r[cDn]).trim() : "";
          final dnVal = double.tryParse(dnStr);
          if (dnVal != null) {
            fila["dn"] = dnStr;
          }
          registros.add(fila);
        }
      } else if (tipo == "inv_cliente") {
        tablaDestino = "chips";
        final cFecha = col("fecha asignacion cliente"),
            cCarrier = col("carrier") != -1 ? col("carrier") : col("compañía"),
            cVend = col("vendedor"),
            cCli = col("cliente"),
            cProd = col("producto"),
            cIcc = col("iccid"),
            cDn = col("dn");
        if ([cIcc, cCli, cProd].contains(-1)) {
          _fin("No encuentro las columnas esperadas (iccid, cliente, producto).");
          return;
        }
        for (var i = 3; i < filas.length; i++) {
          final r = filas[i];
          final iccRaw = _cell(r[cIcc]).trim();
          if (iccRaw.isEmpty || iccRaw.toLowerCase() == "iccid" || iccRaw.toLowerCase() == "icc") continue;
          final icc = _normIccid(iccRaw);

          final prod = _cell(r[cProd]).trim();
          if (prod.isEmpty || prod == "0" || prod == "0.0" || prod.toLowerCase() == "producto") continue;

          final vendNombre = cVend >= 0 ? _cell(r[cVend]).trim() : "";
          final vid = idPorNombre[_norm(vendNombre)] ?? "";
          final cliNombre = _cell(r[cCli]).trim();
          final cid = idPorCliente[_norm(cliNombre)] ?? "";
          final carrierExcel = cCarrier >= 0 ? _cell(r[cCarrier]).trim() : "ATT";
          final compDetectadaCli = _comp(prod, carrier: carrierExcel);

          final fila = <String, dynamic>{
            "iccid": icc,
            "producto": prod,
            "compania": compDetectadaCli,
            "estado": "en_cliente",
            "fecha_asig_cliente": cFecha >= 0 ? _fechaIso(_cell(r[cFecha])) : "",
          };
          if (vid.isNotEmpty) fila["vendedor_id"] = vid;
          if (cid.isNotEmpty) fila["cliente_id"] = cid;

          final dnStr = cDn >= 0 ? _cell(r[cDn]).trim() : "";
          final dnVal = double.tryParse(dnStr);
          if (dnVal != null) {
            fila["dn"] = dnStr;
          }
          registros.add(fila);
        }
      } else {
        _fin("Tipo de reporte desconocido.");
        return;
      }

      if (registros.isEmpty) {
        _fin("No se encontraron registros válidos para subir.");
        return;
      }

      // Deduplicar registros en base a ICCID para el archivo actual
      final vistos = <String>{};
      final dedup = <Map<String, dynamic>>[];
      for (final r in registros) {
        final icc = (r["iccid"] ?? "").toString();
        if (icc.isEmpty || vistos.add(icc)) {
          dedup.add(r);
        }
      }
      registros = dedup;

      // Crear vendedores faltantes en la BD
      final faltantes = <String, String>{}; // nombre -> ID
      for (final r in registros) {
        if ((r["vendedor_id"] ?? "").toString().isEmpty) {
          final v = (r["vendedor"] ?? "").toString();
          if (v.isNotEmpty) {
            final genId = "VEND-${v.hashCode.abs()}-${DateTime.now().millisecond}";
            faltantes.putIfAbsent(v, () => genId);
            r["vendedor_id"] = faltantes[v];
          }
        }
      }

      if (faltantes.isNotEmpty) {
        setState(() => _log = "Creando ${faltantes.length} vendedores faltantes en la BD...");
        final loteNuevos = faltantes.entries.map((e) => {
          "vendedor_id": e.value,
          "nombre": e.key,
          "usuario": e.value,
          "password_hash": "PENDIENTE",
          "activo": true
        }).toList();
        try {
           await Supabase.instance.client.from('vendedores').upsert(loteNuevos);
        } catch (_) {}
      }

      final sinId = registros.where((r) =>
          (r["vendedor_id"] ?? "").toString().isEmpty).length;

      int insertadas = 0;
      if (tablaDestino == "chips") {
        final iccidsExistentes = state.chips.map((c) => c.iccid).toSet();
        final paraAgregar = registros.where((r) => !iccidsExistentes.contains(r["iccid"])).toList();
        final paraEditar = registros.where((r) => iccidsExistentes.contains(r["iccid"])).toList();
        final totalFilas = paraAgregar.length + paraEditar.length;

        setState(() => _log =
            "Procesando ${registros.length} chips en '$tablaDestino'...\n"
            "Nuevos a agregar: ${paraAgregar.length} | Existentes a actualizar: ${paraEditar.length}\n"
            "${sinId > 0 ? "Aviso: $sinId filas sin vendedor_id resuelto.\n" : ""}");

        if (paraAgregar.isNotEmpty) {
          insertadas += await state.backend.insertarFilas(
            tablaDestino,
            paraAgregar,
            accion: "Edit",
            tamLote: 50,
            onProgreso: (hechas, total) {
              setState(() {
                _progreso = totalFilas == 0 ? 1 : hechas / totalFilas;
                _log = "Agregando nuevos chips... $hechas / $totalFilas";
              });
            },
          );
        }

        if (paraEditar.isNotEmpty) {
          final hechasAgregar = insertadas;
          await state.backend.insertarFilas(
            tablaDestino,
            paraEditar,
            accion: "Edit",
            tamLote: 50,
            onProgreso: (hechas, total) {
              final totalHechas = hechasAgregar + hechas;
              setState(() {
                _progreso = totalFilas == 0 ? 1 : totalHechas / totalFilas;
                _log = "Actualizando chips existentes... $totalHechas / $totalFilas";
              });
            },
          );
          insertadas += paraEditar.length;
        }
      } else {
        setState(() => _log =
            "Subiendo ${registros.length} filas a '$tablaDestino'...\n"
            "${sinId > 0 ? "Aviso: $sinId filas sin vendedor_id resuelto.\n" : ""}");

        if (tablaDestino == 'ventas') {
          final validos = registros.where((r) => (r["vendedor_id"] ?? "").toString().isNotEmpty).toList();
          if (validos.isEmpty) {
            _fin("No hay ventas válidas con vendedor reconocido.");
            return;
          }
          insertadas = await state.backend.procesarVentasConCruce(
            validos,
            onProgreso: (hechas, total) {
              setState(() {
                _progreso = total == 0 ? 1 : hechas / total;
                _log = "Procesando ventas y cruzando chips... $hechas / $total";
              });
            },
          );
        } else {
          insertadas = await state.backend.insertarFilas(
            tablaDestino,
            registros,
            accion: "Add",
            tamLote: 50,
            onProgreso: (hechas, total) {
              setState(() {
                _progreso = total == 0 ? 1 : hechas / total;
                _log = "Subiendo a '$tablaDestino'...  $hechas / $total";
              });
            },
          );
        }
      }

      await state.recargarTodo();

      _fin("✓ Listo. Se procesaron $insertadas filas en '$tablaDestino'.\n"
          "${sinId > 0 ? "($sinId quedaron sin vendedor_id; revisa nombres que no coinciden con la tabla vendedores.)\n" : ""}");
    } catch (e) {
      _fin("Error: $e");
    }
  }

  void _fin(String msg) {
    setState(() {
      _trabajando = false;
      _progreso = 0;
      _log = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Cargar reportes (Excel)",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              "Sube los reportes que hoy llegan manualmente. Se leen y se "
              "escriben a la BD por lotes."),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _botonCarga("Ventas (chips)", Icons.point_of_sale, "ventas"),
              _botonCarga(
                  "Inventario vendedor", Icons.inventory_2, "inv_vendedor"),
              _botonCarga("Inventario cliente", Icons.store, "inv_cliente"),
            ],
          ),
          const SizedBox(height: 20),
          if (_trabajando) ...[
            LinearProgressIndicator(value: _progreso == 0 ? null : _progreso),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Text(_log,
                      style: const TextStyle(
                          fontFamily: "monospace", fontSize: 13)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonCarga(String etiqueta, IconData icon, String tipo) {
    return SizedBox(
      width: 220,
      height: 90,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.superficie,
            foregroundColor: AppColors.acento,
            side: const BorderSide(color: AppColors.acento, width: 1.5)),
        onPressed: _trabajando ? null : () => _subir(tipo),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 8),
            Text(etiqueta, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
