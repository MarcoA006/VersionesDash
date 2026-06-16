import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../admin_state.dart';
import '../dashboard_logic.dart';
import '../models.dart';
import '../theme.dart';
import 'multi_select_dialog.dart';

/// Panel de Surtido por cliente (réplica del Power BI):
///  - Barra lateral con filtros de Vendedor, Lada y Cliente.
///  - Grid con las tablas de "Pedido Por Surtir" y "Activación Máxima" (arriba).
///  - Mapa de ubicaciones e "Inventario QR" (abajo).
class SurtidoTab extends StatefulWidget {
  const SurtidoTab({super.key});

  @override
  State<SurtidoTab> createState() => _SurtidoTabState();
}

class _SurtidoTabState extends State<SurtidoTab> {
  List<VentaHist> _ventas = [];
  bool _cargando = true;
  String? _error;

  final Set<String> _vendedoresSel = {};
  final Set<String> _ladasSel = {};
  final Set<String> _clientesSel = {};
  final Set<String> _companiasSel = {};

  // Estado para ordenamiento de tabla Pedido
  String? _sortCol;
  bool _sortAsc = false;

  static const _companias5 = ["AT&T", "Unefon", "Movistar", "Telcel", "Bait"];

  bool _matchCompania(String dbComp, Set<String> sel) {
    final compNorm = dbComp.toUpperCase();
    return sel.any((s) {
      final sNorm = s.toUpperCase();
      if (sNorm == "AT&T") return compNorm.contains("ATT") || compNorm.contains("AT&T");
      if (sNorm == "UNEFON") return compNorm.contains("UNE") || compNorm.contains("UNEFON");
      if (sNorm == "MOVISTAR") return compNorm.contains("MOV");
      if (sNorm == "TELCEL") return compNorm.contains("TELCEL");
      if (sNorm == "BAIT") return compNorm.contains("BAIT");
      return compNorm.contains(sNorm);
    });
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Recargamos chips/clientes/vendedores frescos antes del historial
      await context.read<AdminState>().recargarTodo();
      if (!mounted) return;
      final h = await context.read<AdminState>().backend.historicoVentas();
      if (!mounted) return;
      setState(() {
        _ventas = h;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = "No se pudo cargar: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    final state = context.watch<AdminState>();

    // 1) Filtrar las ventas y los chips para alimentar el dashboard y mapa
    final ventasF = _ventas.where((v) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(v.vendedorId)) return false;
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(v.lada)) return false;
      if (_clientesSel.isNotEmpty && !_clientesSel.contains(v.clienteId)) return false;
      if (_companiasSel.isNotEmpty && !_matchCompania(v.compania, _companiasSel)) return false;
      return true;
    }).toList();

    final chipsF = state.chips.where((c) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(c.vendedorId)) return false;
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(c.lada)) return false;
      if (_companiasSel.isNotEmpty && !_matchCompania(c.compania, _companiasSel)) return false;
      return true;
    }).toList();

    // 2) Obtener ladas y clientes disponibles para los dropdowns
    final ladasDisponibles = _ventas
        .map((v) => v.lada)
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final dropdownClientes = state.clientes.where((c) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(c.vendedorId)) return false;
      return true;
    }).toList();

    // 3) Cálculos de Surtido
    final logic = SurtidoLogic(_ventas, chipsF);
    final activMax = logic.activacionMaximaPorCliente(ventasF);
    final invPorId = logic.inventarioPorCliente();

    // Mapa cliente_id -> nombre y nombre -> cliente_id (para cruzar).
    final nombrePorId = {for (final c in state.clientes) c.id: c.nombre};
    final idPorNombreNorm = {
      for (final c in state.clientes) c.nombre.trim().toLowerCase(): c.id
    };

    final nombresCliente = <String>{
      ...activMax.keys,
      ...invPorId.keys.map((id) => nombrePorId[id] ?? id),
    };

    var clientesFiltrados = nombresCliente.toList()..sort();
    if (_clientesSel.isNotEmpty) {
      final selNames = _clientesSel.map((id) => nombrePorId[id]?.trim().toLowerCase() ?? id.trim().toLowerCase()).toSet();
      clientesFiltrados = clientesFiltrados
          .where((c) => selNames.contains(c.trim().toLowerCase()))
          .toList();
    }

    final diasDelMes =
        DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;

    final tendenciasClientes = logic.tendenciaTotalPorCliente(ventasF);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebar(state, ladasDisponibles, dropdownClientes),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildTablaPedido(
                          clientesFiltrados, activMax, invPorId, idPorNombreNorm, diasDelMes, tendenciasClientes, state),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTablaMaximas(clientesFiltrados, activMax, invPorId, idPorNombreNorm),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildMapa(ventasF),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTablaInventario(
                          clientesFiltrados, invPorId, idPorNombreNorm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(
      AdminState state, List<String> ladas, List<Cliente> dropdownClientes) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.filter_alt, color: AppColors.acento),
              SizedBox(width: 8),
              Text("Filtros",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: () async {
              final res = await showDialog<Set<String>>(
                context: context,
                builder: (_) => MultiSelectSearchDialog<String>(
                  title: "Seleccionar Vendedor",
                  items: state.vendedores.map((v) => v.id).toList(),
                  initialSelected: _vendedoresSel,
                  itemLabel: (vId) => state.nombreVendedor(vId),
                ),
              );
              if (res != null) {
                setState(() {
                  _vendedoresSel.clear();
                  _vendedoresSel.addAll(res);
                  _clientesSel.clear();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
              child: Text(_vendedoresSel.isEmpty ? "Vendedor: Todos" : "Vendedor: ${_vendedoresSel.length} sel.", style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final res = await showDialog<Set<String>>(
                context: context,
                builder: (_) => MultiSelectSearchDialog<String>(
                  title: "Seleccionar Compañía",
                  items: _companias5,
                  initialSelected: _companiasSel,
                  itemLabel: (c) => c,
                ),
              );
              if (res != null) {
                setState(() {
                  _companiasSel.clear();
                  _companiasSel.addAll(res);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
              child: Text(_companiasSel.isEmpty ? "Compañía: Todas" : "Compañía: ${_companiasSel.length} sel.", style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final res = await showDialog<Set<String>>(
                context: context,
                builder: (_) => MultiSelectSearchDialog<String>(
                  title: "Seleccionar Lada",
                  items: ladas,
                  initialSelected: _ladasSel,
                  itemLabel: (l) => l,
                ),
              );
              if (res != null) {
                setState(() {
                  _ladasSel.clear();
                  _ladasSel.addAll(res);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
              child: Text(_ladasSel.isEmpty ? "Lada: Todas" : "Lada: ${_ladasSel.length} sel.", style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final res = await showDialog<Set<String>>(
                context: context,
                builder: (_) => MultiSelectSearchDialog<String>(
                  title: "Seleccionar Cliente",
                  items: dropdownClientes.map((c) => c.id).toList(),
                  initialSelected: _clientesSel,
                  itemLabel: (cId) => state.clientes.firstWhere((c) => c.id == cId, orElse: () => Cliente(id:'',nombre:cId,vendedorId:'',rutaId:'',activo:true)).nombre,
                ),
              );
              if (res != null) {
                setState(() {
                  _clientesSel.clear();
                  _clientesSel.addAll(res);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
              child: Text(_clientesSel.isEmpty ? "Cliente: Todos" : "Cliente: ${_clientesSel.length} sel.", style: const TextStyle(fontSize: 16)),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.acento),
              foregroundColor: AppColors.acento,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => setState(() {
              _vendedoresSel.clear();
              _ladasSel.clear();
              _clientesSel.clear();
              _companiasSel.clear();
            }),
            icon: const Icon(Icons.clear_all),
            label: const Text("Limpiar filtros"),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.acento,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
            label: const Text("Actualizar"),
          ),

          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _exportarMapa,
            icon: const Icon(Icons.map),
            label: const Text("Exportar Mapa"),
          ),
        ],
      ),
    );
  }

  // Helper para pintar celdas
  void _colorCell(xls.Sheet sheet, int row, int col, {String? bgHex, String? fontHex, bool bold = false}) {
    if (bgHex == null && fontHex == null && !bold) return;
    final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.cellStyle = xls.CellStyle(
      backgroundColorHex: bgHex != null ? xls.ExcelColor.fromHexString(bgHex) : xls.ExcelColor.none,
      fontColorHex: fontHex != null ? xls.ExcelColor.fromHexString(fontHex) : xls.ExcelColor.none,
      bold: bold,
    );
  }

  Future<void> _exportarPedidoPorSurtir() async {
    final state = context.read<AdminState>();
    final logic = SurtidoLogic(_ventas, state.chips);
    final ventasF = _ventas.where((v) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(v.vendedorId)) return false;
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(v.lada)) return false;
      if (_clientesSel.isNotEmpty && !_clientesSel.contains(v.clienteId)) return false;
      return true;
    }).toList();

    final companias = SurtidoLogic.companiasSurtido;
    final activMax = logic.activacionMaximaPorCliente(ventasF);
    final invPorId = logic.inventarioPorCliente();
    final nombrePorId = {for (final c in state.clientes) c.id: c.nombre};
    final idPorNombre = {for (final c in state.clientes) c.nombre.trim().toLowerCase(): c.id};
    final diasDelMes = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;

    final clientes = <String>{...activMax.keys, ...invPorId.keys.map((id) => nombrePorId[id] ?? id)}.toList()..sort();

    final libro = xls.Excel.createExcel();
    final h1 = libro['Pedido_Por_Surtir'];
    h1.appendRow([xls.TextCellValue('Cliente'), ...companias.map(xls.TextCellValue.new)]);
    int r = 1;
    for (final cli in clientes) {
      final cid = idPorNombre[cli.trim().toLowerCase()] ?? '';
      final mx = activMax[cli] ?? {};
      final inv = invPorId[cid] ?? {};
      
      String? colorCli;
      final u = state.ultimaVisitaCliente(cid);
      if (u != null) {
        final d = DateTime.now().difference(u).inDays;
        if (d <= 7) colorCli = '#4CAF50';
        else if (d <= 21) colorCli = '#FFC107';
        else colorCli = '#F44336';
      }

      h1.appendRow([
        xls.TextCellValue(cli),
        ...companias.map((c) => xls.IntCellValue(SurtidoLogic.pedido(mx[c] ?? 0, inv[c] ?? 0, diasDelMes))),
      ]);
      if (colorCli != null) _colorCell(h1, r, 0, fontHex: colorCli, bold: true);
      
      int c = 1;
      for (final comp in companias) {
        final p = SurtidoLogic.pedido(mx[comp] ?? 0, inv[comp] ?? 0, diasDelMes);
        if (p > 0) _colorCell(h1, r, c, bgHex: '#FFF200');
        else if (p < 0) _colorCell(h1, r, c, bgHex: '#FF4D4D', fontHex: '#FFFFFF');
        c++;
      }
      r++;
    }
    libro.delete('Sheet1');
    _guardarExcel(libro, 'pedido_por_surtir.xlsx');
  }

  Future<void> _exportarActivacionMaxima() async {
    final state = context.read<AdminState>();
    final logic = SurtidoLogic(_ventas, state.chips);
    final ventasF = _ventas.where((v) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(v.vendedorId)) return false;
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(v.lada)) return false;
      if (_clientesSel.isNotEmpty && !_clientesSel.contains(v.clienteId)) return false;
      return true;
    }).toList();

    final companias = SurtidoLogic.companiasSurtido;
    final activMax = logic.activacionMaximaPorCliente(ventasF);
    final invPorId = logic.inventarioPorCliente();
    final nombrePorId = {for (final c in state.clientes) c.id: c.nombre};
    final idPorNombre = {for (final c in state.clientes) c.nombre.trim().toLowerCase(): c.id};
    final clientes = <String>{...activMax.keys, ...invPorId.keys.map((id) => nombrePorId[id] ?? id)}.toList()..sort();

    final libro = xls.Excel.createExcel();
    final h2 = libro['Activacion_Maxima'];
    h2.appendRow([xls.TextCellValue('Cliente'), ...companias.map(xls.TextCellValue.new)]);
    int r = 1;
    for (final cli in clientes) {
      final mx = activMax[cli] ?? {};
      h2.appendRow([xls.TextCellValue(cli), ...companias.map((c) => xls.IntCellValue(mx[c] ?? 0))]);
      
      final cid = idPorNombre[cli.trim().toLowerCase()] ?? '';
      String? colorCli;
      final u = state.ultimaVisitaCliente(cid);
      if (u != null) {
        final d = DateTime.now().difference(u).inDays;
        if (d <= 7) colorCli = '#4CAF50';
        else if (d <= 21) colorCli = '#FFC107';
        else colorCli = '#F44336';
      }
      if (colorCli != null) _colorCell(h2, r, 0, fontHex: colorCli, bold: true);
      r++;
    }
    libro.delete('Sheet1');
    _guardarExcel(libro, 'activacion_maxima.xlsx');
  }

  Future<void> _exportarInventarioQR() async {
    final state = context.read<AdminState>();
    final logic = SurtidoLogic(_ventas, state.chips);
    final ventasF = _ventas.where((v) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(v.vendedorId)) return false;
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(v.lada)) return false;
      if (_clientesSel.isNotEmpty && !_clientesSel.contains(v.clienteId)) return false;
      return true;
    }).toList();

    final companias = SurtidoLogic.companiasSurtido;
    final activMax = logic.activacionMaximaPorCliente(ventasF);
    final invPorId = logic.inventarioPorCliente();
    final nombrePorId = {for (final c in state.clientes) c.id: c.nombre};
    final idPorNombre = {for (final c in state.clientes) c.nombre.trim().toLowerCase(): c.id};
    final clientes = <String>{...activMax.keys, ...invPorId.keys.map((id) => nombrePorId[id] ?? id)}.toList()..sort();

    final libro = xls.Excel.createExcel();
    final h3 = libro['Inventario_QR'];
    h3.appendRow([xls.TextCellValue('Cliente'), ...companias.map(xls.TextCellValue.new), xls.TextCellValue('Total')]);
    int r = 1;
    for (final cli in clientes) {
      final cid = idPorNombre[cli.trim().toLowerCase()] ?? '';
      final inv = invPorId[cid] ?? {};
      final total = companias.fold<int>(0, (a, c) => a + (inv[c] ?? 0));
      h3.appendRow([xls.TextCellValue(cli), ...companias.map((c) => xls.IntCellValue(inv[c] ?? 0)), xls.IntCellValue(total)]);
      
      String? colorCli;
      final u = state.ultimaVisitaCliente(cid);
      if (u != null) {
        final d = DateTime.now().difference(u).inDays;
        if (d <= 7) colorCli = '#4CAF50';
        else if (d <= 21) colorCli = '#FFC107';
        else colorCli = '#F44336';
      }
      if (colorCli != null) _colorCell(h3, r, 0, fontHex: colorCli, bold: true);
      r++;
    }
    libro.delete('Sheet1');
    _guardarExcel(libro, 'inventario_qr.xlsx');
  }

  Future<void> _guardarExcel(xls.Excel libro, String defaultName) async {
    final bytes = libro.encode();
    if (bytes == null) return;
    final ruta = await FilePicker.saveFile(
      dialogTitle: 'Guardar tabla',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (ruta == null) return;
    await File(ruta).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exportado a $ruta')));
    }
  }

  Future<void> _exportarMapa() async {
    final ventasF = _ventas.where((v) {
      if (_vendedoresSel.isNotEmpty && !_vendedoresSel.contains(v.vendedorId)) return false;
      if (_ladasSel.isNotEmpty && !_ladasSel.contains(v.lada)) return false;
      if (_clientesSel.isNotEmpty && !_clientesSel.contains(v.clienteId)) return false;
      if (_companiasSel.isNotEmpty && !_matchCompania(v.compania, _companiasSel)) return false;
      return true;
    }).toList();

    // Ordenar de más reciente a más antiguo
    ventasF.sort((a, b) => b.fecha.compareTo(a.fecha));

    final Map<String, VentaHist> unicos = {};
    for (final v in ventasF) {
      if (v.lat != 0 && v.lng != 0) {
        if (!unicos.containsKey(v.clienteId)) {
          unicos[v.clienteId] = v;
        }
      }
    }

    final mapaVentas = unicos.values.toList();
    if (mapaVentas.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay ventas con coordenadas para exportar')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text("Obteniendo ubicaciones y generando Excel...")),
          ],
        ),
      ),
    );

    final libro = xls.Excel.createExcel();
    final h1 = libro['Mapa_Ventas'];
    h1.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('Cliente'),
      xls.TextCellValue('Compañía'),
      xls.TextCellValue('Lada'),
      xls.TextCellValue('Ubicación (Maps)'),
      xls.TextCellValue('Colonia'),
    ]);

    for (var i = 0; i < mapaVentas.length; i++) {
      final v = mapaVentas[i];
      
      String colonia = '';
      try {
        final url = Uri.parse("https://nominatim.openstreetmap.org/reverse?format=json&lat=${v.lat}&lon=${v.lng}&zoom=14");
        final resp = await http.get(url, headers: {"User-Agent": "com.acc.admin"});
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final addr = data['address'];
          if (addr != null) {
             colonia = addr['suburb'] ?? addr['neighbourhood'] ?? addr['village'] ?? addr['town'] ?? addr['city'] ?? '';
          }
        }
        await Future.delayed(const Duration(milliseconds: 600)); // Límite de Nominatim
      } catch (_) {}

      h1.appendRow([
        xls.TextCellValue(v.fecha.toIso8601String().substring(0, 10)),
        xls.TextCellValue(v.clienteNombre),
        xls.TextCellValue(v.compania),
        xls.TextCellValue(v.lada),
        xls.FormulaCellValue('HYPERLINK("https://www.google.com/maps/search/?api=1&query=${v.lat},${v.lng}", "${v.lat}, ${v.lng}")'),
        xls.TextCellValue(colonia),
      ]);
    }
    libro.delete('Sheet1');
    final bytes = libro.encode();

    if (mounted) Navigator.pop(context); // cerrar dialog

    if (bytes == null) return;
    
    final ruta = await FilePicker.saveFile(
      dialogTitle: 'Guardar Mapa Ventas',
      fileName: 'mapa_ventas.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (ruta == null) return;
    await File(ruta).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exportado a $ruta')));
    }
  }

  Widget _buildTablaPedido(
      List<String> clientes,
      Map<String, Map<String, int>> activMax,
      Map<String, Map<String, int>> invPorId,
      Map<String, String> idPorNombre,
      int diasDelMes,
      Map<String, double?> tendencias,
      AdminState state) {
    final companias = SurtidoLogic.companiasSurtido;

    Widget celdaPedido(int max, int inv) {
      final p = SurtidoLogic.pedido(max, inv, diasDelMes);
      final color = Color(SurtidoLogic.colorPedido(p));
      final textStyle = TextStyle(
        fontWeight: FontWeight.bold,
        color: p < 0 ? Colors.white : Colors.black,
        fontSize: 13,
      );

      return Container(
        color: p == 0 ? null : color,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text("$p", textAlign: TextAlign.center, style: textStyle),
      );
    }

    Widget buildClasifStars(int totalMax) {
      final double rating = totalMax >= 30
          ? 5
          : (totalMax >= 20
          ? 4
          : (totalMax >= 10 ? 3 : (totalMax >= 5 ? 2 : 1)));
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (index) {
          return Icon(
            index < rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 14,
          );
        }),
      );
    }

    return _card(
      "Pedido Por Surtir",
      accion: IconButton(
        icon: const Icon(Icons.download, color: Colors.blue),
        tooltip: "Exportar a Excel",
        onPressed: _exportarPedidoPorSurtir,
      ),
      SizedBox(
        height: 280,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
          columnWidths: const {
            0: FixedColumnWidth(180),
            1: FixedColumnWidth(70),
            2: FixedColumnWidth(70),
            3: FixedColumnWidth(70),
            4: FixedColumnWidth(70),
            5: FixedColumnWidth(70),
            6: FixedColumnWidth(80),
            7: FixedColumnWidth(80),
            8: FixedColumnWidth(80),
          },
        border: TableBorder.all(color: Colors.grey.shade300),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F1E36)),
            children: [
              _headerCell("Nombre de Cliente", isSortable: true),
              ...companias.map((c) => _headerCell(c, isSortable: true)),
              _headerCell("Clasif"),
              _headerCell("Tendencia", isSortable: true),
            ],
          ),
          ...() {
            var list = clientes.toList();
            if (_sortCol != null) {
              list.sort((a, b) {
                final cidA = idPorNombre[a.trim().toLowerCase()] ?? "";
                final cidB = idPorNombre[b.trim().toLowerCase()] ?? "";
                int cmp = 0;
                if (_sortCol == "Nombre de Cliente") {
                  cmp = a.compareTo(b);
                } else if (_sortCol == "Tendencia") {
                  final pctA = tendencias[a] ?? -999.0;
                  final pctB = tendencias[b] ?? -999.0;
                  cmp = pctA.compareTo(pctB);
                } else {
                  // sorting by company
                  final mxA = activMax[a] ?? {};
                  final invA = invPorId[cidA] ?? {};
                  final pA = SurtidoLogic.pedido(mxA[_sortCol] ?? 0, invA[_sortCol] ?? 0, diasDelMes);
                  
                  final mxB = activMax[b] ?? {};
                  final invB = invPorId[cidB] ?? {};
                  final pB = SurtidoLogic.pedido(mxB[_sortCol] ?? 0, invB[_sortCol] ?? 0, diasDelMes);
                  cmp = pA.compareTo(pB);
                }
                return _sortAsc ? cmp : -cmp;
              });
            }
            return list;
          }().map((cli) {
            final cid = idPorNombre[cli.trim().toLowerCase()] ?? "";
            final mx = activMax[cli] ?? {};
            final inv = invPorId[cid] ?? {};
            final totalMax = (mx['AT&T'] ?? 0) +
                (mx['Movistar/Unefon'] ?? 0) +
                (mx['Telcel'] ?? 0);
            
            Color visitColor = Colors.transparent;
            if (cid.isNotEmpty) {
              final ultimaV = state.ultimaVisitaCliente(cid);
              if (ultimaV != null) {
                final days = DateTime.now().difference(ultimaV).inDays;
                if (days <= 7) visitColor = AppColors.exito;
                else if (days <= 21) visitColor = AppColors.amarillo;
                else visitColor = AppColors.alerta;
              } else {
                visitColor = AppColors.alerta;
              }
            }

            final pct = tendencias[cli];
            final sube = (pct ?? 0) >= 0;
            final colorTend = pct == null ? Colors.grey : (sube ? AppColors.exito : AppColors.alerta);
            final iconTend = pct == null ? Icons.remove : (sube ? Icons.arrow_upward : Icons.arrow_downward);

            return TableRow(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.store, color: visitColor, size: 16),
                      const SizedBox(width: 4),
                      Expanded(child: Text(cli, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                    ],
                  ),
                ),
                ...companias.map((c) {
                  final iVal = inv[c] ?? 0;
                  if (c == "Por definir") {
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      color: iVal > 0 ? Colors.orange.shade100 : null,
                      child: Text("$iVal", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: iVal > 0 ? Colors.orange.shade900 : Colors.black)),
                    );
                  }
                  final mVal = mx[c] ?? 0;
                  return celdaPedido(mVal, iVal);
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: buildClasifStars(totalMax),
                ),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconTend, color: colorTend, size: 14),
                      if (pct != null) Text(" ${pct.abs().toStringAsFixed(0)}%", style: TextStyle(color: colorTend, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
      ),
      ),
      ),
    );
  }

  Widget _buildTablaMaximas(
      List<String> clientes, Map<String, Map<String, int>> activMax, Map<String, Map<String, int>> invPorId, Map<String, String> idPorNombre) {
    final companias = SurtidoLogic.companiasSurtido;

    return _card(
      "Activaciones Máximas por Cliente (4 meses)",
      accion: IconButton(
        icon: const Icon(Icons.download, color: Colors.blue),
        tooltip: "Exportar a Excel",
        onPressed: _exportarActivacionMaxima,
      ),
      SizedBox(
        height: 280,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
          columnWidths: const {
            0: FixedColumnWidth(180),
            1: FixedColumnWidth(80),
            2: FixedColumnWidth(80),
            3: FixedColumnWidth(80),
            4: FixedColumnWidth(80),
            5: FixedColumnWidth(80),
            6: FixedColumnWidth(80),
          },
        border: TableBorder.all(color: Colors.grey.shade300),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F1E36)),
            children: [
              _headerCell("Nombre de Cliente"),
              ...companias.map((c) => _headerCell(c.toUpperCase())),
            ],
          ),
          ...clientes.map((cli) {
            final cid = idPorNombre[cli.trim().toLowerCase()] ?? "";
            final mx = activMax[cli] ?? {};
            final inv = invPorId[cid] ?? {};
            
            Color visitColor = Colors.transparent;
            if (cid.isNotEmpty) {
              final ultimaV = context.read<AdminState>().ultimaVisitaCliente(cid);
              if (ultimaV != null) {
                final days = DateTime.now().difference(ultimaV).inDays;
                if (days <= 7) visitColor = AppColors.exito;
                else if (days <= 21) visitColor = AppColors.amarillo;
                else visitColor = AppColors.alerta;
              } else {
                visitColor = AppColors.alerta;
              }
            }

            return TableRow(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.store, color: visitColor, size: 16),
                      const SizedBox(width: 4),
                      Expanded(child: Text(cli, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                    ],
                  ),
                ),
                ...companias.map((c) {
                  final val = mx[c] ?? 0;
                  final iVal = inv[c] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("$val",
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        const SizedBox(height: 4),
                        Text("Inv: $iVal",
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  );
                }),
              ],
            );
          }),
        ],
      ),
      ),
      ),
      ),
    );
  }

  Widget _buildTablaInventario(List<String> clientes,
      Map<String, Map<String, int>> invPorId, Map<String, String> idPorNombre) {
    final companias = _companias5;

    return _card(
      "Inventario QR por Cliente",
      accion: IconButton(
        icon: const Icon(Icons.download, color: Colors.blue),
        tooltip: "Exportar a Excel",
        onPressed: _exportarInventarioQR,
      ),
      SizedBox(
        height: 380,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
          columnWidths: const {
            0: FixedColumnWidth(180),
            1: FixedColumnWidth(80),
            2: FixedColumnWidth(80),
            3: FixedColumnWidth(80),
            4: FixedColumnWidth(80),
            5: FixedColumnWidth(80),
            6: FixedColumnWidth(80),
            7: FixedColumnWidth(80),
            8: FixedColumnWidth(80),
          },
        border: TableBorder.all(color: Colors.grey.shade300),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF0F1E36)),
            children: [
              _headerCell("Nombre de Cliente"),
              ...companias.map(_headerCell),
              _headerCell("Total"),
            ],
          ),
          ...clientes.map((cli) {
            final cid = idPorNombre[cli.trim().toLowerCase()] ?? "";
            final inv = invPorId[cid] ?? {};
            var total = 0;
            for (final c in companias) {
              total += inv[c] ?? 0;
            }

            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(cli, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                ...companias.map((c) {
                  final val = inv[c] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.pie_chart, size: 12, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text("$val", style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.pie_chart, size: 12, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text("$total",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
      ),
      ),
      ),
    );
  }

  Widget _buildMapa(List<VentaHist> conGpsList) {
    final conGps = conGpsList.where((v) => v.lat != 0 && v.lng != 0).toList();
    if (conGps.isEmpty) {
      return _card(
        "Ubicación de surtidos al cliente (0 con GPS)",
        const SizedBox(
          height: 380,
          child: Center(
            child: Text(
              "Sin coordenadas GPS para los filtros actuales.",
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
      );
    }
    final cLat =
        conGps.map((v) => v.lat).reduce((a, b) => a + b) / conGps.length;
    final cLng =
        conGps.map((v) => v.lng).reduce((a, b) => a + b) / conGps.length;
    final marcadores = conGps
        .map((v) => Marker(
              point: LatLng(v.lat, v.lng),
              width: 40,
              height: 40,
              child: Tooltip(
                message: v.clienteNombre,
                child: const Icon(Icons.location_on,
                    color: AppColors.alerta, size: 36),
              ),
            ))
        .toList();

    return _card(
      "Ubicación de surtidos al cliente (${conGps.length} con GPS)",
      SizedBox(
        height: 380,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FlutterMap(
            options: MapOptions(
                initialCenter: LatLng(cLat, cLng), initialZoom: 11),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.acc.admin",
              ),
              MarkerLayer(markers: marcadores),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution("OpenStreetMap contributors"),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, {bool isSortable = false}) {
    Widget content = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
    );
    
    if (isSortable) {
      IconData? icon;
      if (_sortCol == text) {
        icon = _sortAsc ? Icons.arrow_upward : Icons.arrow_downward;
      }
      content = InkWell(
        onTap: () {
          setState(() {
            if (_sortCol == text) {
              if (_sortAsc) {
                _sortAsc = false;
              } else {
                _sortCol = null;
              }
            } else {
              _sortCol = text;
              _sortAsc = false; // por defecto mayor a menor
            }
          });
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: content),
            if (icon != null) Icon(icon, color: Colors.white, size: 14),
          ],
        ),
      );
    }

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: content,
    );
  }

  Widget _card(String titulo, Widget hijo, {Widget? accion}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F1E36))),
                ),
                if (accion != null) accion,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: hijo,
          ),
        ],
      ),
    );
  }
}
