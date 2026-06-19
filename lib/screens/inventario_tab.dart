import 'dart:io';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Chip;
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../models.dart';
import '../theme.dart';
import 'multi_select_dialog.dart';

/// Pestaña Inventario con dos sub-vistas:
///  - "Ver inventario": lista los chips actuales (filtrable).
///  - "Asignar nuevo": da de alta chips NUEVOS y los asigna a un vendedor,
///     vía Excel (autodetecta ICC/DN) o pegando en 3 textareas.
/// La lada se calcula de los 3 primeros dígitos del DN, pero es editable.
class InventarioTab extends StatefulWidget {
  const InventarioTab({super.key});

  @override
  State<InventarioTab> createState() => _InventarioTabState();
}

class _InventarioTabState extends State<InventarioTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: AppColors.superficie,
          child: TabBar(
            controller: _tab,
            labelColor: AppColors.acento,
            indicatorColor: AppColors.acento,
            tabs: const [
              Tab(icon: Icon(Icons.list), text: "Ver inventario"),
              Tab(icon: Icon(Icons.add_box), text: "Asignar nuevo"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _VerInventario(),
              _AsignarNuevo(),
            ],
          ),
        ),
      ],
    );
  }
}

/// --------------------------------------------------------------------------
/// Sub-vista 1: lista de chips actuales con filtro.
/// --------------------------------------------------------------------------
class _VerInventario extends StatefulWidget {
  const _VerInventario();
  @override
  State<_VerInventario> createState() => _VerInventarioState();
}

class _VerInventarioState extends State<_VerInventario> {
  final _filtroCtrl = TextEditingController();
  String _q = "";
  Set<String> _vendedoresSel = {};
  Set<String> _estadosSel = {};
  Set<String> _ladasSel = {};
  Set<String> _clientesSel = {};
  Set<String> _companiasSel = {};

  static const _companiasDisponibles = ["AT&T", "Unefon", "Telcel", "Movistar", "Bait"];

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final ladas = state.chips.map((c) => c.lada).where((l) => l.isNotEmpty).toSet().toList()..sort();
    
    final lista = state.chips.where((c) {
      if (_vendedoresSel.isNotEmpty) {
        if (!_vendedoresSel.contains(c.vendedorId)) {
          return false;
        }
      }
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(c.lada)) {
        return false;
      }
      if (_clientesSel.isNotEmpty && !_clientesSel.contains(c.clienteId)) {
        return false;
      }
      
      if (_companiasSel.isNotEmpty) {
        // Normalizar para comparar de forma flexible
        final compNorm = c.compania.trim().toUpperCase();
        final match = _companiasSel.any((sel) {
          final sNorm = sel.toUpperCase();
          if (sNorm == "AT&T") return compNorm.contains("ATT") || compNorm.contains("AT&T");
          if (sNorm == "UNEFON") return compNorm.contains("UNE") || compNorm.contains("UNEFON");
          if (sNorm == "MOVISTAR") return compNorm.contains("MOV");
          if (sNorm == "TELCEL") return compNorm.contains("TELCEL");
          if (sNorm == "BAIT") return compNorm.contains("BAIT");
          return compNorm.contains(sNorm);
        });
        if (!match) return false;
      }
      if (_estadosSel.isNotEmpty) {
        if (!_estadosSel.contains(c.estado)) return false;
      } else {
        // Por defecto no mostrar vendidos
        if (c.estado == 'vendido') return false;
      }
      final t = "${c.iccid} ${c.dn} ${c.producto} ${c.estado}".toLowerCase();
      
      String query = _q;
      if (query.endsWith('f') && query.length >= 10 && query.startsWith('89')) {
        query = query.substring(0, query.length - 1);
      }
      
      return t.contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _filtroCtrl,
                  decoration: const InputDecoration(
                      labelText: "Buscar ICCID / DN / producto",
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () async {
                    final opts = {for (final v in state.vendedores) v.id: v.nombre};
                    final res = await showDialog<Set<String>>(
                        context: context,
                        builder: (_) => MultiSelectSearchDialog<String>(
                            title: "Vendedores", 
                            items: state.vendedores.map((v) => v.id).toList(), 
                            itemLabel: (id) => opts[id] ?? id,
                            initialSelected: _vendedoresSel));
                    if (res != null) setState(() => _vendedoresSel = res);
                  },
                  child: Text(_vendedoresSel.isEmpty
                      ? "Vendedor: Todos"
                      : "Vendedores (${_vendedoresSel.length})"),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () async {
                    final opts = {
                      "en_vendedor": "En vendedor",
                      "en_cliente": "En cliente",
                      "vendido": "Vendido",
                    };
                    final res = await showDialog<Set<String>>(
                        context: context,
                        builder: (_) => MultiSelectSearchDialog<String>(
                            title: "Estados", 
                            items: opts.keys.toList(),
                            itemLabel: (id) => opts[id] ?? id,
                            initialSelected: _estadosSel));
                    if (res != null) setState(() => _estadosSel = res);
                  },
                  child: Text(_estadosSel.isEmpty
                      ? "Estado: Inv. vendedor"
                      : "Estados (${_estadosSel.length})"),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () async {
                    final res = await showDialog<Set<String>>(
                        context: context,
                        builder: (_) => MultiSelectSearchDialog<String>(
                            title: "Ladas", 
                            items: ladas,
                            itemLabel: (l) => l,
                            initialSelected: _ladasSel));
                    if (res != null) setState(() => _ladasSel = res);
                  },
                  child: Text(_ladasSel.isEmpty
                      ? "Lada: Todas"
                      : "Ladas (${_ladasSel.length})"),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () async {
                    final res = await showDialog<Set<String>>(
                        context: context,
                        builder: (_) => MultiSelectSearchDialog<String>(
                            title: "Compañía",
                            items: _companiasDisponibles,
                            itemLabel: (c) => c,
                            initialSelected: _companiasSel));
                    if (res != null) setState(() => _companiasSel = res);
                  },
                  child: Text(_companiasSel.isEmpty
                      ? "Compañía: Todas"
                      : "Compañías (${_companiasSel.length})"),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () async {
                    final opts = {for (final c in state.clientes) c.id: c.nombre};
                    final res = await showDialog<Set<String>>(
                        context: context,
                        builder: (_) => MultiSelectSearchDialog<String>(
                            title: "Clientes", 
                            items: state.clientes.map((c) => c.id).toList(),
                            itemLabel: (id) => opts[id] ?? id,
                            initialSelected: _clientesSel));
                    if (res != null) setState(() => _clientesSel = res);
                  },
                  child: Text(_clientesSel.isEmpty
                      ? "Cliente: Todos"
                      : "Clientes (${_clientesSel.length})"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // --- Botones Actualizar / Exportar ---
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => context.read<AdminState>().recargarTodo(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text("Actualizar"),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _exportarInventario(lista, state),
                icon: const Icon(Icons.download, size: 18, color: Colors.blue),
                label: const Text("Exportar a Excel"),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _filtroCtrl.clear();
                  setState(() {
                    _q = "";
                    _vendedoresSel.clear();
                    _estadosSel.clear();
                    _ladasSel.clear();
                    _clientesSel.clear();
                    _companiasSel.clear();
                  });
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text("Limpiar filtros"),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text("${lista.length} chips",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              children: [
                Container(
                  color: AppColors.acento.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: const Row(
                    children: [
                      SizedBox(width: 210, child: Text("ICCID", style: TextStyle(fontWeight: FontWeight.bold))),
                      SizedBox(width: 160, child: Text("DN / Producto", style: TextStyle(fontWeight: FontWeight.bold))),
                      SizedBox(width: 80, child: Text("Compañía", style: TextStyle(fontWeight: FontWeight.bold))),
                      SizedBox(width: 200, child: Text("Ubicación", style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 1, child: Text("Asig. Vendedor", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text("Asig. Cliente", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text("Vendido Cliente", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(flex: 1, child: Text("Vinculado CURP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = lista[i];
                      String ubicacion = c.vendedorId.isEmpty ? "Sin asignar" : "Vend: ${state.nombreVendedor(c.vendedorId)}";
                      Color? visitColor;
                      
                      if (c.clienteId.isNotEmpty) {
                        final cli = state.clientes.where((cl) => cl.id == c.clienteId).firstOrNull;
                        if (cli != null) {
                          ubicacion = "Cli: ${cli.nombre}";
                          final ultimaV = state.ultimaVisitaCliente(cli.id);
                          if (ultimaV != null) {
                            final days = DateTime.now().difference(ultimaV).inDays;
                            if (days <= 7) visitColor = AppColors.exito;
                            else if (days <= 21) visitColor = AppColors.amarillo;
                            else visitColor = AppColors.alerta;
                          } else {
                            visitColor = AppColors.alerta;
                          }
                        } else {
                          ubicacion = "Cli: ${c.clienteId}";
                        }
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(width: 210, child: Text(c.iccid, style: const TextStyle(fontFamily: "monospace", fontSize: 13))),
                            SizedBox(width: 160, child: Text("${c.dn}\n${c.producto}", style: const TextStyle(fontSize: 12))),
                            SizedBox(width: 80, child: Align(alignment: Alignment.centerLeft, child: _badge(c.compania))),
                            SizedBox(
                              width: 200,
                              child: Text(ubicacion,
                                  style: TextStyle(
                                      color: visitColor,
                                      fontWeight: visitColor != null
                                          ? FontWeight.bold
                                          : null)),
                            ),
                            Expanded(flex: 1, child: Text(_fechaStr(c.fechaAsigVendedor), style: const TextStyle(fontSize: 12))),
                            Expanded(flex: 1, child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_fechaStr(c.fechaAsigCliente), style: const TextStyle(fontSize: 12)),
                                if (c.fechaAsigCliente != null && c.clienteId.isNotEmpty)
                                  Text(state.nombreCliente(c.clienteId), style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            Expanded(flex: 1, child: Text(_fechaStr(c.fechaVenta), style: const TextStyle(fontSize: 12))),
                            Expanded(flex: 1, child: Text(_fechaStr(c.fechaVinculadoCurp), style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fechaStr(DateTime? d) {
    if (d == null) return "-";
    return "${d.day}/${d.month}/${d.year}";
  }

  Widget _badge(String c) {
    final comp = c.trim().toUpperCase();
    final color = switch (comp) {
      "AT&T" || "ATT" => const Color(0xFF00A8E0),
      "UNEFON" => const Color(0xFF8BC53F),
      "TELCEL" => const Color(0xFF1B6CB3),
      "MOVISTAR" => const Color(0xFF019DF4),
      _ => Colors.grey,
    };
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(c,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _colorCell(xls.Sheet sheet, int row, int col, {String? bgHex, String? fontHex, bool bold = false}) {
    if (bgHex == null && fontHex == null && !bold) return;
    final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.cellStyle = xls.CellStyle(
      backgroundColorHex: bgHex != null ? xls.ExcelColor.fromHexString(bgHex) : xls.ExcelColor.none,
      fontColorHex: fontHex != null ? xls.ExcelColor.fromHexString(fontHex) : xls.ExcelColor.none,
      bold: bold,
    );
  }

  Future<void> _exportarInventario(List<Chip> lista, AdminState state) async {
    final libro = xls.Excel.createExcel();
    final sheet = libro['Inventario_Chips'];
    
    sheet.appendRow([
      xls.TextCellValue("ICCID"),
      xls.TextCellValue("DN"),
      xls.TextCellValue("Producto"),
      xls.TextCellValue("Lada"),
      xls.TextCellValue("Compañía"),
      xls.TextCellValue("Estado"),
      xls.TextCellValue("Ubicación"),
      xls.TextCellValue("Fecha Alta"),
    ]);
    
    // Header format
    for (int i = 0; i < 8; i++) {
      _colorCell(sheet, 0, i, bgHex: '#0F1E36', fontHex: '#FFFFFF', bold: true);
    }

    int rowIdx = 1;
    for (final c in lista) {
      String ubicacion = c.vendedorId.isEmpty ? "Sin asignar" : "Vend: ${state.nombreVendedor(c.vendedorId)}";
      String? colorCli;
      if (c.clienteId.isNotEmpty) {
        final cli = state.clientes.where((cl) => cl.id == c.clienteId).firstOrNull;
        if (cli != null) {
          ubicacion = "Cli: ${cli.nombre}";
          final ultimaV = state.ultimaVisitaCliente(cli.id);
          if (ultimaV != null) {
            final days = DateTime.now().difference(ultimaV).inDays;
            if (days <= 7) colorCli = '#4CAF50';
            else if (days <= 21) colorCli = '#FFC107';
            else colorCli = '#F44336';
          } else {
            colorCli = '#F44336';
          }
        } else {
          ubicacion = "Cli: ${c.clienteId}";
        }
      }

      sheet.appendRow([
        xls.TextCellValue(c.iccid),
        xls.TextCellValue(c.dn),
        xls.TextCellValue(c.producto),
        xls.TextCellValue(c.lada),
        xls.TextCellValue(c.compania),
        xls.TextCellValue(c.estado),
        xls.TextCellValue(ubicacion),
        xls.TextCellValue(c.fechaAlta?.toString().split(' ').first ?? ''),
      ]);

      // Badge comp
      final badgeColor = switch (c.compania.trim().toUpperCase()) {
        "AT&T" || "ATT" => '#00A8E0',
        "UNEFON" => '#8BC53F',
        "TELCEL" => '#1B6CB3',
        "MOVISTAR" => '#019DF4',
        _ => null,
      };
      if (badgeColor != null) {
        _colorCell(sheet, rowIdx, 4, bgHex: badgeColor, fontHex: '#FFFFFF', bold: true);
      }
      
      // Visita color (Ubicacion)
      if (colorCli != null) {
        _colorCell(sheet, rowIdx, 6, fontHex: colorCli, bold: true);
      }
      rowIdx++;
    }

    libro.delete('Sheet1');
    final bytes = libro.encode();
    if (bytes == null) return;
    final ruta = await FilePicker.saveFile(
      dialogTitle: 'Guardar inventario',
      fileName: 'inventario_chips.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (ruta == null) return;
    await File(ruta).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exportado a $ruta')));
    }
  }
}

/// Una fila de chip a dar de alta (editable en la tabla de revisión).
class _FilaChip {
  String iccid;
  String dn;
  String lada;
  String compania;
  _FilaChip(this.iccid, this.dn, this.lada, {this.compania = ''});
}

/// Calcula la lada de los primeros 3 dígitos del DN (solo dígitos).
String _ladaDeDn(String dn) {
  final soloDig = dn.replaceAll(RegExp(r'\D'), '');
  return soloDig.length >= 3 ? soloDig.substring(0, 3) : soloDig;
}

/// --------------------------------------------------------------------------
/// Sub-vista 2: alta de chips nuevos + asignación a un vendedor.
/// --------------------------------------------------------------------------
class _AsignarNuevo extends StatefulWidget {
  const _AsignarNuevo();
  @override
  State<_AsignarNuevo> createState() => _AsignarNuevoState();
}

class _AsignarNuevoState extends State<_AsignarNuevo> {
  final _iccCtrl = TextEditingController();
  final _dnCtrl = TextEditingController();
  final _ladaCtrl = TextEditingController();
  final _compCtrl = TextEditingController();

  String? _vendedorId;
  List<_FilaChip> _revision = [];
  bool _trabajando = false;
  double _progreso = 0;
  String _log = "";

  @override
  void dispose() {
    _iccCtrl.dispose();
    _dnCtrl.dispose();
    _ladaCtrl.dispose();
    _compCtrl.dispose();
    super.dispose();
  }

  /// Divide un textarea en líneas/valores no vacíos.
  List<String> _lineas(String s) => s
      .split(RegExp(r'[\n,;\t]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Construye la lista de revisión desde las 3 cajas de texto.
  void _desdeTextareas() {
    final iccs = _lineas(_iccCtrl.text);
    final dns = _lineas(_dnCtrl.text);
    final ladas = _lineas(_ladaCtrl.text);
    final comps = _lineas(_compCtrl.text);
    if (iccs.isEmpty) {
      _msg("Pega al menos los ICCID.");
      return;
    }
    final filas = <_FilaChip>[];
    for (var i = 0; i < iccs.length; i++) {
      final dn = i < dns.length ? dns[i] : "";
      final lada = i < ladas.length && ladas[i].isNotEmpty
          ? ladas[i]
          : _ladaDeDn(dn);
      final comp = i < comps.length && comps[i].isNotEmpty ? comps[i] : '';
      filas.add(_FilaChip(iccs[i], dn, lada, compania: comp));
    }
    setState(() {
      _revision = filas;
      _log = "Revisa los ${filas.length} chips antes de asignar. "
          "Puedes editar la lada.";
    });
  }

  /// Construye la lista de revisión desde un Excel (autodetecta columnas).
  Future<void> _desdeExcel() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["xlsx"],
      withData: true,
    );
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }
    try {
      final libro = xls.Excel.decodeBytes(res.files.first.bytes!);
      final hoja = libro.tables.values.first;
      final filas = hoja.rows;
      if (filas.length < 2) {
        _msg("El Excel no tiene datos.");
        return;
      }

      // Autodetección de columnas: busca encabezados que contengan
      // icc/iccid, dn, lada, compania en alguna de las primeras filas.
      int cIcc = -1, cDn = -1, cLada = -1, cComp = -1, filaEncab = -1;
      for (var f = 0; f < filas.length && f < 5; f++) {
        for (var c = 0; c < filas[f].length; c++) {
          final t = (filas[f][c]?.value?.toString() ?? "").toLowerCase();
          if (t.contains("icc")) cIcc = c;
          if (t == "dn" || t.contains("dn") || t.contains("numero")) cDn = c;
          if (t.contains("lada")) cLada = c;
          if (t.contains("compañia") || t.contains("compania") || t.contains("red")) cComp = c;
        }
        if (cIcc >= 0) {
          filaEncab = f;
          break;
        }
      }
      if (cIcc < 0) {
        _msg("No encontré una columna de ICCID en el Excel.");
        return;
      }

      final out = <_FilaChip>[];
      for (var i = filaEncab + 1; i < filas.length; i++) {
        final r = filas[i];
        String cell(int c) =>
            (c >= 0 && c < r.length) ? (r[c]?.value?.toString() ?? "") : "";
        final icc = cell(cIcc).trim();
        if (icc.isEmpty) continue;
        final dn = cell(cDn).trim();
        final ladaExcel = cell(cLada).trim();
        final comp = cell(cComp).trim();
        out.add(_FilaChip(icc, dn, ladaExcel.isNotEmpty ? ladaExcel : _ladaDeDn(dn), compania: comp));
      }
      if (out.isEmpty) {
        _msg("No se encontraron filas con ICCID.");
        return;
      }
      setState(() {
        _revision = out;
        _log = "Detecté ${out.length} chips desde el Excel "
            "(ICC col ${cIcc + 1}${cDn >= 0 ? ", DN col ${cDn + 1}" : ""}"
            "${cLada >= 0 ? ", lada col ${cLada + 1}" : ", lada calculada del DN"}"
            "${cComp >= 0 ? ", comp col ${cComp + 1}" : ""}). "
            "Revisa y asigna.";
      });
    } catch (e) {
      _msg("Error al leer Excel: $e");
    }
  }

  Future<void> _asignar() async {
    final state = context.read<AdminState>();
    if (_vendedorId == null) {
      _msg("Elige el vendedor destino.");
      return;
    }
    if (_revision.isEmpty) {
      _msg("Primero carga los chips (Excel o pegando los valores).");
      return;
    }

    setState(() {
      _trabajando = true;
      _progreso = 0;
      _log = "Asignando ${_revision.length} chips...";
    });

    // Chips NUEVOS -> Add. El vendedor_id es Ref, así que subimos de a 1
    // (tamLote=1) para evitar el rechazo 400 de AppSheet en Adds masivos a Ref.
    final filas = _revision
        .map((f) => <String, dynamic>{
              "iccid": f.iccid,
              "dn": f.dn,
              "producto": "",
              "compania": f.compania.isNotEmpty ? f.compania : "Por definir",
              "estado": "en_vendedor",
              "vendedor_id": _vendedorId,
              "fecha_asig_vendedor": DateTime.now().toIso8601String().split('T').first,
            })
        .toList();

    try {
      final n = await state.backend.insertarFilas(
        "chips",
        filas,
        tamLote: 1,
        onProgreso: (h, t) => setState(() {
          _progreso = t == 0 ? 1 : h / t;
          _log = "Asignando...  $h / $t";
        }),
      );
      await state.recargarTodo();
      setState(() {
        _trabajando = false;
        _progreso = 0;
        _revision = [];
        _iccCtrl.clear();
        _dnCtrl.clear();
        _ladaCtrl.clear();
        _compCtrl.clear();
        _log = "✓ Se asignaron $n chips a ${state.nombreVendedor(_vendedorId!)}.";
      });
    } catch (e) {
      setState(() {
        _trabajando = false;
        _log = "Error: $e";
      });
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selección de vendedor destino
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _vendedorId,
            decoration:
                const InputDecoration(labelText: "Vendedor destino"),
            items: state.vendedores
                .map((v) =>
                    DropdownMenuItem(value: v.id, child: Text(v.nombre)))
                .toList(),
            onChanged: (v) => setState(() => _vendedorId = v),
          ),
          const SizedBox(height: 16),

          // Opción A: Excel
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Opción A — Subir Excel",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                      "Detecta automáticamente ICCID, DN y lada. Si no hay lada, "
                      "la calcula de los 3 primeros dígitos del DN.",
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _trabajando ? null : _desdeExcel,
                    icon: const Icon(Icons.upload_file),
                    label: const Text("Elegir Excel"),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Opción B: 3 textareas
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Opción B — Pegar valores",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                      "Pega una columna por caja (un valor por línea). La lada "
                      "se calcula del DN si la dejas vacía.",
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _area("ICCID", _iccCtrl)),
                      const SizedBox(width: 8),
                      Expanded(child: _area("DN", _dnCtrl)),
                      const SizedBox(width: 8),
                      Expanded(child: _area("Lada (opcional)", _ladaCtrl)),
                      const SizedBox(width: 8),
                      Expanded(child: _area("Compañía (opcional)", _compCtrl)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _trabajando ? null : _desdeTextareas,
                    icon: const Icon(Icons.fact_check),
                    label: const Text("Procesar pegado"),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Revisión + asignar
          if (_revision.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Revisión (${_revision.length} chips) — edita la lada si hace falta",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._revision.asMap().entries.take(50).map((e) {
                      final i = e.key;
                      final f = e.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 4,
                                child: Text(f.iccid,
                                    style: const TextStyle(
                                        fontFamily: "monospace", fontSize: 12))),
                            Expanded(
                                flex: 3,
                                child: Text("DN ${f.dn}",
                                    style: const TextStyle(fontSize: 12))),
                            SizedBox(
                              width: 70,
                              child: TextFormField(
                                initialValue: f.lada,
                                decoration: const InputDecoration(
                                    isDense: true, labelText: "lada"),
                                onChanged: (v) => _revision[i].lada = v.trim(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_revision.length > 50)
                      Text("... y ${_revision.length - 50} más",
                          style: const TextStyle(
                              fontStyle: FontStyle.italic, fontSize: 12)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _trabajando ? null : _asignar,
                      icon: const Icon(Icons.assignment_turned_in),
                      label: Text("Asignar ${_revision.length} chips"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_trabajando)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                  value: _progreso == 0 ? null : _progreso),
            ),
          if (_log.isNotEmpty)
            Card(
              color: const Color(0xFFF3F6FA),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_log,
                    style:
                        const TextStyle(fontFamily: "monospace", fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _area(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      maxLines: 6,
      style: const TextStyle(fontFamily: "monospace", fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
