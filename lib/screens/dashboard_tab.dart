import 'dart:io';
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
import 'package:fl_chart/fl_chart.dart';
import 'multi_select_dialog.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<VentaHist> _historico = [];
  bool _cargando = true;
  String? _error;

  // filtros
  final Set<String> _vendedoresSel = {};
  final Set<String> _ladasSel = {};
  final Set<String> _clientesSel = {};
  String? _expandido; // vendedor expandido en la tabla

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
      // Primero recargamos el estado global (chips, clientes, vendedores)
      await context.read<AdminState>().recargarTodo();
      if (!mounted) return;
      final h = await context.read<AdminState>().backend.historicoVentas();
      if (!mounted) return;
      setState(() {
        _historico = h;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = "No se pudo cargar el histórico: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final state = context.watch<AdminState>();
    final logic = DashboardLogic(_historico, state.chips);
    final data = logic.filtrar(
      vendedores: _vendedoresSel,
      ladas: _ladasSel,
      clientes: _clientesSel,
      startDate: state.filtroFechaInicio,
      endDate: state.filtroFechaFin,
    );
    final totalesPorEstado = logic.totalesPorCompaniaYEstado(data);
    final totalGen = logic.totalGeneralPorEstado(data);
    final porVend = logic.porVendedorCompania(data);
    final tendenciasState = logic.tendenciasPorEstado(
      vendedorId: _vendedoresSel.length == 1 ? _vendedoresSel.first : null,
      startDate: state.filtroFechaInicio,
      endDate: state.filtroFechaFin,
    );

    DateTime? ultimaFechaRegistro;
    for (final v in logic.filtrar()) {
      if (ultimaFechaRegistro == null || v.fecha.isAfter(ultimaFechaRegistro)) {
        ultimaFechaRegistro = v.fecha;
      }
    }

    return Column(
      children: [
        _barraFiltros(logic, state),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _contadores(totalGen, totalesPorEstado, logic, tendenciasState, ultimaFechaRegistro),
                const SizedBox(height: 16),
                _graficoComportamiento(logic, data),
                const SizedBox(height: 16),
                _tablaPedidoPorSurtir(logic, data, porVend, state),
                const SizedBox(height: 16),
                _bloqueUbicacion(data),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----- Filtros -----
  Widget _barraFiltros(DashboardLogic logic, AdminState state) {
    return Material(
      color: AppColors.superficie,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text("Dashboard de ventas",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _btnDateRange(state),
                _dropVendedor(state),
                _dropLada(logic),
                _dropCliente(logic),
              ],
            ),
            if (_vendedoresSel.isNotEmpty ||
                _ladasSel.isNotEmpty ||
                _clientesSel.isNotEmpty ||
                state.filtroFechaInicio != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  state.setFiltroFechas(null, null);
                  _vendedoresSel.clear();
                  _ladasSel.clear();
                  _clientesSel.clear();
                  _expandido = null;
                }),
                icon: const Icon(Icons.clear),
                label: const Text("Limpiar"),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text("Actualizar"),
            ),
            ElevatedButton.icon(
              onPressed: () => _exportar(logic),
              icon: const Icon(Icons.download),
              label: const Text("Exportar Excel"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btnDateRange(AdminState state) {
    final start = state.filtroFechaInicio;
    final end = state.filtroFechaFin;
    final txt = (start != null && end != null) 
        ? "${start.day.toString().padLeft(2,'0')}/${start.month.toString().padLeft(2,'0')}/${start.year} - ${end.day.toString().padLeft(2,'0')}/${end.month.toString().padLeft(2,'0')}/${end.year}" 
        : "Todas";
    return InkWell(
      onTap: () async {
        final res = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: (start != null && end != null) ? DateTimeRange(start: start, end: end) : null,
        );
        if (res != null) {
          state.setFiltroFechas(res.start, res.end);
        }
      },
      child: _chipFiltro("Fecha", txt),
    );
  }

  Widget _dropVendedor(AdminState state) {
    return InkWell(
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
            _expandido = null;
          });
        }
      },
      child: _chipFiltro("Vendedor", _vendedoresSel.isEmpty ? "Todos" : "${_vendedoresSel.length} sel."),
    );
  }

  Widget _dropLada(DashboardLogic logic) {
    return InkWell(
      onTap: () async {
        final res = await showDialog<Set<String>>(
          context: context,
          builder: (_) => MultiSelectSearchDialog<String>(
            title: "Seleccionar Lada",
            items: logic.ladasDisponibles(_vendedoresSel),
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
      child: _chipFiltro("Lada", _ladasSel.isEmpty ? "Todas" : "${_ladasSel.length} sel."),
    );
  }

  Widget _dropCliente(DashboardLogic logic) {
    return InkWell(
      onTap: () async {
        final res = await showDialog<Set<String>>(
          context: context,
          builder: (_) => MultiSelectSearchDialog<String>(
            title: "Seleccionar Cliente",
            items: logic.clientesDisponibles(_vendedoresSel),
            initialSelected: _clientesSel,
            itemLabel: (c) => c,
          ),
        );
        if (res != null) {
          setState(() {
            _clientesSel.clear();
            _clientesSel.addAll(res);
          });
        }
      },
      child: _chipFiltro("Cliente", _clientesSel.isEmpty ? "Todos" : "${_clientesSel.length} sel."),
    );
  }

  Widget _chipFiltro(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.acento),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ",
              style: const TextStyle(
                  color: AppColors.acento, fontWeight: FontWeight.bold)),
          Text(valor),
          const Icon(Icons.arrow_drop_down, color: AppColors.acento),
        ],
      ),
    );
  }

  // ----- Contadores -----
  Widget _contadores(Map<String, int> totalGen, Map<String, Map<String, int>> totales, DashboardLogic logic, Map<String, Map<String, ({int actual, int anterior, double? pct})>> tendenciasState, DateTime? ultimaFecha) {
    final ambito = _vendedoresSel.isEmpty ? "Global" : "Vendedores seleccionados";
    final lastDateStr = ultimaFecha != null ? "${ultimaFecha.day.toString().padLeft(2, '0')}/${ultimaFecha.month.toString().padLeft(2, '0')}/${ultimaFecha.year}" : "N/A";
    
    // Calcular tendencia total sumando AT&T y Unefon
    double? pctTotalVendido;
    final actVendidoTotal = (tendenciasState["AT&T"]?["vendido"]?.actual ?? 0) + (tendenciasState["UNEFON"]?["vendido"]?.actual ?? 0);
    final antVendidoTotal = (tendenciasState["AT&T"]?["vendido"]?.anterior ?? 0) + (tendenciasState["UNEFON"]?["vendido"]?.anterior ?? 0);
    if (antVendidoTotal > 0) {
      pctTotalVendido = (actVendidoTotal - antVendidoTotal) / antVendidoTotal * 100;
    } else if (antVendidoTotal == 0 && actVendidoTotal > 0) {
      pctTotalVendido = 100;
    }

    final tendenciaTotal = {
      "vendido": (actual: actVendidoTotal, anterior: antVendidoTotal, pct: pctTotalVendido),
    };
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Activaciones — $ambito",
                style: const TextStyle(fontSize: 14, color: Colors.black54)),
            Text("Último registro global: $lastDateStr",
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _cardContadorDoble("TOTAL (AT&T + Unefon)", totalGen, AppColors.acento, logic, tendenciaTotal),
            ...totales.entries.map((e) =>
                _cardContadorDoble(e.key, e.value, _colorComp(e.key), logic, tendenciasState[e.key])),
          ],
        ),
      ],
    );
  }

  Widget _cardContadorDoble(String titulo, Map<String, int> valores, Color color, DashboardLogic logic, Map<String, ({int actual, int anterior, double? pct})>? tendencias) {
    final enCliente = valores["en_cliente"] ?? 0;
    final vendido = valores["vendido"] ?? 0;
    final pctVendido = tendencias?["vendido"]?.pct;
    
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 6)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Inventario (Más pequeño)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$enCliente",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  const Text("En Cliente", style: TextStyle(fontSize: 10, color: Colors.black54)),
                ],
              ),
              // Vendidos (Más grande) + Tendencia
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Icon(
                        pctVendido == null || pctVendido == 0 ? Icons.remove : (pctVendido > 0 ? Icons.arrow_upward : Icons.arrow_downward),
                        color: pctVendido == null || pctVendido == 0 ? Colors.grey : (pctVendido > 0 ? AppColors.exito : AppColors.alerta),
                        size: 14,
                      ),
                      Text(
                        pctVendido == null ? " 0%" : " ${pctVendido.abs().toStringAsFixed(1)}%",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pctVendido == null || pctVendido == 0 ? Colors.grey : (pctVendido > 0 ? AppColors.exito : AppColors.alerta),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text("$vendido",
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.exito)),
                    ],
                  ),
                  const Text("Vendido", style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _cardContador(String titulo, int valor, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 6)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Text("$valor",
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Color _colorComp(String c) => switch (c) {
        "AT&T" => const Color(0xFF00A8E0),
        "UNEFON" => const Color(0xFFFFCC00),
        "MOVISTAR" => const Color(0xFF4CAF50), // Verde
        "TELCEL" => const Color(0xFF000080),   // Azul Marino
        "BAIT" => const Color(0xFF000000),     // Negro
        _ => Colors.grey,
      };

  // ----- Gráfico Comportamiento -----
  Widget _graficoComportamiento(DashboardLogic logic, List<VentaHist> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    // Extraer datos por periodo (mes)
    final periodos = data.map((v) => v.periodo).toSet().toList()..sort();
    
    // Preparar series (Barras por compañia por periodo)
    List<BarChartGroupData> barGroups = [];
    int xIndex = 0;
    
    for (final p in periodos) {
      List<BarChartRodData> rods = [];
      int idxComp = 0;
      for (final comp in DashboardLogic.companias) {
        final count = data.where((v) => v.periodo == p && DashboardLogic.agrupa(v.compania) == comp).length;
        rods.add(BarChartRodData(
          toY: count.toDouble(),
          color: _colorComp(comp),
          width: 14,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
        ));
        idxComp++;
      }
      barGroups.add(BarChartGroupData(
        x: xIndex,
        barRods: rods,
      ));
      xIndex++;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Comportamiento (Entregas y Activaciones)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                barGroups: barGroups,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        if (val.toInt() >= 0 && val.toInt() < periodos.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(periodos[val.toInt()], style: const TextStyle(fontSize: 10)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true, drawVerticalLine: false),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            children: DashboardLogic.companias.map((c) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 12, height: 12, color: _colorComp(c)),
                const SizedBox(width: 4),
                Text(c, style: const TextStyle(fontSize: 12)),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }



  // ----- Tabla Pedido por Surtir (expandible + colores) -----
  Widget _tablaPedidoPorSurtir(
    DashboardLogic logic,
    List<VentaHist> data,
    Map<String, Map<String, int>> porVend,
    AdminState state,
  ) {
    final companias = DashboardLogic.companias;
    final filas = <Widget>[];

    porVend.forEach((vendId, mapaComp) {
      final color = colorDeVendedor(vendId);
      final expandido = _expandido == vendId;
      filas.add(
        InkWell(
          onTap: () => setState(() {
            if (expandido) {
              _expandido = null;
              _vendedoresSel.remove(vendId);
            } else {
              _expandido = vendId;
              _vendedoresSel.clear();
              _vendedoresSel.add(vendId);
              _clientesSel.clear();
            }
          }),
          child: Container(
            color: color.withValues(alpha: 0.18),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Icon(expandido ? Icons.remove : Icons.add, size: 18),
                const SizedBox(width: 6),
                Container(width: 12, height: 12, color: color),
                const SizedBox(width: 8),
                Expanded(
                    flex: 3,
                    child: Text(state.nombreVendedor(vendId),
                        style:
                            const TextStyle(fontWeight: FontWeight.bold))),
                ...companias.map((c) => Expanded(
                    child: Text("${mapaComp[c] ?? 0}",
                        textAlign: TextAlign.center))),
              ],
            ),
          ),
        ),
      );

      if (expandido) {
        final porCliente = logic.clientesDeVendedor(data, vendId);
        porCliente.forEach((cli, mapaC) {
          final isCliSel = _clientesSel.contains(cli);
          filas.add(InkWell(
            onTap: () => setState(() {
              if (isCliSel) {
                _clientesSel.remove(cli);
              } else {
                _clientesSel.clear();
                _clientesSel.add(cli);
              }
            }),
            child: Container(
              color: isCliSel ? Colors.blue.withOpacity(0.1) : Colors.white,
              padding:
                  const EdgeInsets.only(left: 44, top: 6, bottom: 6, right: 8),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text("Cliente: $cli",
                          style: TextStyle(fontSize: 12, fontWeight: isCliSel ? FontWeight.bold : null))),
                  ...companias.map((c) => Expanded(
                      child: Text("${mapaC[c] ?? 0}",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, fontWeight: isCliSel ? FontWeight.bold : null)))),
                ],
              ),
            ),
          ));
        });
      }
    });

    return _card(
      "Ventas por vendedor (clic en + para ver por lada)",
      accion: IconButton(
        icon: const Icon(Icons.download, color: Colors.blue),
        tooltip: "Exportar a Excel",
        onPressed: () => _exportarVentasPorVendedor(logic, data, porVend, state),
      ),
      Column(
        children: [
          Container(
            color: AppColors.acento,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                    flex: 3,
                    child: Text("Vendedor",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold))),
                ...companias.map((c) => Expanded(
                    child: Text(c,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
          SizedBox(
            height: 250,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...filas,
                  if (filas.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16), child: Text("Sin datos.")),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Ubicación: mapa OpenStreetMap con marcadores -----
  Widget _bloqueUbicacion(List<VentaHist> data) {
    final conGps = data.where((v) => v.lat != 0 && v.lng != 0).toList();
    if (conGps.isEmpty) {
      return _card(
        "Ubicación de ventas (0 con GPS)",
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              "Aún no hay coordenadas. Los escaneos de la app registran GPS."),
        ),
      );
    }

    // Centro del mapa = promedio de las coordenadas.
    final centroLat =
        conGps.map((v) => v.lat).reduce((a, b) => a + b) / conGps.length;
    final centroLng =
        conGps.map((v) => v.lng).reduce((a, b) => a + b) / conGps.length;

    final marcadores = conGps.map((v) {
      return Marker(
        point: LatLng(v.lat, v.lng),
        width: 40,
        height: 40,
        child: Tooltip(
          message:
              "${v.clienteNombre}\n${v.compania} · ${v.fecha.toString().split(' ').first}",
          child: Icon(Icons.location_on,
              color: _colorComp(DashboardLogic.agrupa(v.compania)), size: 36),
        ),
      );
    }).toList();

    return _card(
      "Ubicación de ventas (${conGps.length} con GPS)",
      SizedBox(
        height: 420,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(centroLat, centroLng),
              initialZoom: 11,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.acc.admin",
              ),
              MarkerLayer(markers: marcadores),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution("OpenStreetMap contributors"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String titulo, Widget hijo, {Widget? accion}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (accion != null) accion,
              ],
            ),
          ),
          hijo,
          const SizedBox(height: 8),
        ],
      ),
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

  Future<void> _exportarVentasPorVendedor(DashboardLogic logic, List<VentaHist> data, Map<String, Map<String, int>> porVend, AdminState state) async {
    final companias = DashboardLogic.companias;
    final libro = xls.Excel.createExcel();
    final sheet = libro['Ventas_Por_Vendedor'];
    
    sheet.appendRow([xls.TextCellValue('Vendedor'), ...companias.map(xls.TextCellValue.new)]);
    _colorCell(sheet, 0, 0, bgHex: '#0F1E36', fontHex: '#FFFFFF', bold: true);
    for (int i = 0; i < companias.length; i++) {
      _colorCell(sheet, 0, i + 1, bgHex: '#0F1E36', fontHex: '#FFFFFF', bold: true);
    }

    int rowIdx = 1;
    porVend.forEach((vendId, mapaComp) {
      final color = colorDeVendedor(vendId);
      final bgHex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
      
      sheet.appendRow([
        xls.TextCellValue(state.nombreVendedor(vendId)),
        ...companias.map((c) => xls.IntCellValue(mapaComp[c] ?? 0)),
      ]);
      _colorCell(sheet, rowIdx, 0, bgHex: bgHex, bold: true);
      for (int i = 0; i < companias.length; i++) {
        _colorCell(sheet, rowIdx, i + 1, bgHex: bgHex);
      }
      rowIdx++;
      
      // Expandido por cliente
      final porCliente = logic.clientesDeVendedor(data, vendId);
      porCliente.forEach((cli, mapaC) {
        sheet.appendRow([
          xls.TextCellValue("   Cliente: $cli"),
          ...companias.map((c) => xls.IntCellValue(mapaC[c] ?? 0)),
        ]);
        rowIdx++;
      });
    });

    libro.delete('Sheet1');
    final bytes = libro.encode();
    if (bytes == null) return;
    final ruta = await FilePicker.saveFile(
      dialogTitle: 'Guardar tabla',
      fileName: 'ventas_por_vendedor.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (ruta == null) return;
    await File(ruta).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exportado a $ruta')));
    }
  }

  // ----- Export a Excel -----
  Future<void> _exportar(DashboardLogic logic) async {
    final state = context.read<AdminState>();
    final data = logic.filtrar(
        vendedores: _vendedoresSel, 
        ladas: _ladasSel, 
        clientes: _clientesSel,
        startDate: state.filtroFechaInicio,
        endDate: state.filtroFechaFin);
    final libro = xls.Excel.createExcel();

    // Hoja 1: totales por vendedor x compañía
    final h1 = libro['Por_Vendedor'];
    h1.appendRow([
      xls.TextCellValue("Vendedor"),
      ...DashboardLogic.companias.map(xls.TextCellValue.new)
    ]);
    logic.porVendedorCompania(data).forEach((vid, m) {
      h1.appendRow([
        xls.TextCellValue(state.nombreVendedor(vid)),
        ...DashboardLogic.companias.map((c) => xls.IntCellValue(m[c] ?? 0)),
      ]);
    });

    // Hoja 2: pedido por surtir (activación máxima vs inventario real)
    final h2 = libro['Pedido_por_Surtir'];
    h2.appendRow([
      xls.TextCellValue("Cliente"),
      ...DashboardLogic.companias.map(xls.TextCellValue.new)
    ]);

    // Calcular inventario por cliente (estado = en_cliente)
    final invPorId = <String, Map<String, int>>{};
    for (final c in state.chips.where((x) => x.estado == 'en_cliente')) {
      final cid = c.clienteId;
      if (cid.isEmpty) continue;
      final comp = SurtidoLogic.normalizarComp(c.compania);
      final finalComp = (comp == "Movistar" || comp == "Unefon" || comp == "UNEFON") 
          ? "Movistar/Unefon" 
          : comp;
      invPorId.putIfAbsent(cid, () => {});
      invPorId[cid]![finalComp] = (invPorId[cid]![finalComp] ?? 0) + 1;
    }

    final idPorNombreCli = {
      for (final c in state.clientes) c.nombre.trim().toLowerCase(): c.id
    };

    final surtidoLogic = SurtidoLogic(data, state.chips);
    surtidoLogic.activacionMaximaPorCliente(data).forEach((cli, m) {
      final cid = idPorNombreCli[cli.trim().toLowerCase()] ?? "";
      final inv = invPorId[cid] ?? {};

      h2.appendRow([
        xls.TextCellValue(cli),
        ...DashboardLogic.companias.map((c) {
          final maxVal = m[c] ?? 0;
          final invVal = inv[c] ?? 0;
          final pedido = DashboardLogic.pedidoPorSurtir(maxVal, invVal);
          return xls.IntCellValue(pedido);
        }),
      ]);
    });

    // Hoja 3: Datos crudos / Histórico
    final h3 = libro['Base_Datos_Historico'];
    h3.appendRow([
      xls.TextCellValue("Fecha"),
      xls.TextCellValue("Vendedor"),
      xls.TextCellValue("Cliente"),
      xls.TextCellValue("Compañía"),
      xls.TextCellValue("Lada"),
      xls.TextCellValue("Origen"),
    ]);
    for (final v in data) {
      h3.appendRow([
        xls.TextCellValue(v.fecha.toString().split(' ')[0]),
        xls.TextCellValue(state.nombreVendedor(v.vendedorId)),
        xls.TextCellValue(v.clienteNombre.isNotEmpty ? v.clienteNombre : v.clienteId),
        xls.TextCellValue(v.compania),
        xls.TextCellValue(v.lada),
        xls.TextCellValue(v.origen),
      ]);
    }

    // Hoja 4: Inventario Actual
    final h4 = libro['Inventario_Actual'];
    h4.appendRow([
      xls.TextCellValue("ICCID"),
      xls.TextCellValue("DN"),
      xls.TextCellValue("Compañía"),
      xls.TextCellValue("Lada"),
      xls.TextCellValue("Estado"),
      xls.TextCellValue("Vendedor"),
      xls.TextCellValue("Cliente"),
    ]);
    for (final c in state.chips) {
      h4.appendRow([
        xls.TextCellValue(c.iccid),
        xls.TextCellValue(c.dn),
        xls.TextCellValue(c.compania),
        xls.TextCellValue(c.lada),
        xls.TextCellValue(c.estado),
        xls.TextCellValue(state.nombreVendedor(c.vendedorId)),
        xls.TextCellValue(state.nombreCliente(c.clienteId)),
      ]);
    }

    libro.delete('Sheet1');
    final bytes = libro.encode();
    if (bytes == null) return;

    final ruta = await FilePicker.saveFile(
      dialogTitle: "Guardar reporte",
      fileName: "dashboard_ventas.xlsx",
      type: FileType.custom,
      allowedExtensions: ["xlsx"],
    );
    if (ruta == null) return;
    await File(ruta).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Exportado a $ruta")));
    }
  }
}
