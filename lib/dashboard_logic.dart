import 'dart:math' as math;
import 'package:flutter/material.dart' hide Chip;
import 'models.dart';

/// Toda la lógica de cálculo del dashboard, a partir del histórico en vivo.
/// Nada hardcodeado: recibe la lista de VentaHist y la agrega según filtros.
class DashboardLogic {
  final List<VentaHist> _todo;
  final List<Chip> _chips;
  DashboardLogic(this._todo, [this._chips = const []]);

  static const companias = ["AT&T", "UNEFON", "MOVISTAR", "TELCEL", "BAIT"];

  static String agrupa(String c) {
    final u = c.toUpperCase();
    if (u == "AT&T" || u == "UNEFON" || u == "MOVISTAR" || u == "TELCEL" || u == "BAIT") {
      return u;
    }
    if (u.contains("UNE")) return "UNEFON";
    if (u.contains("MOV")) return "MOVISTAR";
    if (u.contains("TELCEL")) return "TELCEL";
    if (u.contains("ATT") || u.contains("AT&T")) return "AT&T";
    if (u.contains("BAIT")) return "BAIT";
    return c;
  }

  List<int> get aniosDisponibles =>
      (_todo.map((v) => v.anio).toSet().toList()..sort());

  /// Meses (1-12) presentes para los años dados (o todos si no se pasan).
  List<int> mesesDisponibles(Set<int>? anios) {
    return (_todo
        .where((v) => anios == null || anios.isEmpty || anios.contains(v.anio))
        .map((v) => v.mes)
        .toSet()
        .toList()
      ..sort());
  }

  List<String> ladasDisponibles(Set<String>? vendedores) {
    final s1 = _todo
        .where((v) => vendedores == null || vendedores.isEmpty || vendedores.contains(v.vendedorId))
        .map((v) => v.lada);
    final s2 = _chips
        .where((c) => vendedores == null || vendedores.isEmpty || vendedores.contains(c.vendedorId))
        .map((c) => c.lada);
    return {...s1, ...s2}.where((s) => s.isNotEmpty).toList()..sort();
  }

  List<String> clientesDisponibles(Set<String>? vendedores) => (_todo
      .where((v) => vendedores == null || vendedores.isEmpty || vendedores.contains(v.vendedorId))
      .map((v) => v.clienteNombre)
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList()
    ..sort());

  List<VentaHist> filtrar({
    Set<int>? anios,
    Set<int>? meses,
    Set<String>? vendedores,
    Set<String>? ladas,
    Set<String>? clientes,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _todo.where((v) {
      if (anios != null && anios.isNotEmpty && !anios.contains(v.anio)) {
        return false;
      }
      if (meses != null && meses.isNotEmpty && !meses.contains(v.mes)) {
        return false;
      }
      if (vendedores != null && vendedores.isNotEmpty && !vendedores.contains(v.vendedorId)) {
        return false;
      }
      if (ladas != null && ladas.isNotEmpty && !ladas.contains(v.lada)) {
        return false;
      }
      if (clientes != null && clientes.isNotEmpty && !clientes.contains(v.clienteNombre)) {
        return false;
      }
      
      if (startDate != null && v.fecha.isBefore(startDate)) return false;
      if (endDate != null && v.fecha.isAfter(endDate.add(const Duration(days: 1)))) return false;

      return true;
    }).toList();
  }

  /// Tendencia por compañía: total del último periodo (mes) vs el anterior,
  /// respetando el vendedor seleccionado. Devuelve, por compañía:
  /// (actual, anterior, variacionPorcentaje).
  /// La variación es null si no hay periodo anterior con que comparar.
  Map<String, ({int actual, int anterior, double? pct})> tendencias(
      {String? vendedorId}) {
    final base = _todo.where((v) {
      if (vendedorId != null && v.vendedorId != vendedorId) return false;
      return true;
    }).toList();

    final periodos = base.map((v) => v.periodo).toSet().toList()..sort();
    final out = <String, ({int actual, int anterior, double? pct})>{};
    if (periodos.isEmpty) {
      for (final c in companias) {
        out[c] = (actual: 0, anterior: 0, pct: null);
      }
      return out;
    }
    final pActual = periodos.last;
    final pPrev = periodos.length >= 2 ? periodos[periodos.length - 2] : null;

    for (final c in companias) {
      final act = base
          .where((v) => v.periodo == pActual && agrupa(v.compania) == c)
          .length;
      final ant = pPrev == null
          ? 0
          : base
              .where((v) => v.periodo == pPrev && agrupa(v.compania) == c)
              .length;
      double? pct;
      if (pPrev != null && ant > 0) {
        pct = (act - ant) / ant * 100;
      } else if (pPrev != null && ant == 0 && act > 0) {
        pct = 100; // de 0 a algo: subida total
      }
      out[c] = (actual: act, anterior: ant, pct: pct);
    }
    return out;
  }

  /// Tendencia por compañía desglosada por estado (en_cliente vs vendido).
  /// Compara el periodo [startDate, endDate] contra el periodo previo de misma duración.
  Map<String, Map<String, ({int actual, int anterior, double? pct})>> tendenciasPorEstado({
    String? vendedorId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final out = <String, Map<String, ({int actual, int anterior, double? pct})>>{};
    
    // Periodo actual
    final sDate = startDate ?? DateTime(2000);
    final eDate = endDate ?? DateTime.now();
    final duration = eDate.difference(sDate);
    
    // Periodo anterior
    final prevEndDate = sDate.subtract(const Duration(days: 1));
    final prevStartDate = prevEndDate.subtract(duration);

    for (final c in companias) {
      out[c] = {};
      for (final estado in ["en_cliente", "vendido"]) {
        final esVendido = estado == "vendido";
        
        final act = _todo.where((v) {
          if (vendedorId != null && v.vendedorId != vendedorId) return false;
          if (agrupa(v.compania) != c) return false;
          if ((v.origen == 'venta') != esVendido) return false;
          if (v.fecha.isBefore(sDate) || v.fecha.isAfter(eDate.add(const Duration(days: 1)))) return false;
          return true;
        }).length;

        final ant = _todo.where((v) {
          if (vendedorId != null && v.vendedorId != vendedorId) return false;
          if (agrupa(v.compania) != c) return false;
          if ((v.origen == 'venta') != esVendido) return false;
          if (v.fecha.isBefore(prevStartDate) || v.fecha.isAfter(prevEndDate.add(const Duration(days: 1)))) return false;
          return true;
        }).length;

        double? pct;
        if (ant > 0) {
          pct = (act - ant) / ant * 100;
        } else if (ant == 0 && act > 0) {
          pct = 100;
        }
        
        out[c]![estado] = (actual: act, anterior: ant, pct: pct);
      }
    }
    return out;
  }

  /// Contador total por compañía (los gauges = total del periodo filtrado).
  Map<String, int> totalesPorCompania(List<VentaHist> data) {
    final m = {for (final c in companias) c: 0};
    for (final v in data) {
      final g = agrupa(v.compania);
      m[g] = (m[g] ?? 0) + 1;
    }
    return m;
  }

  Map<String, Map<String, int>> totalesPorCompaniaYEstado(List<VentaHist> data) {
    final m = {for (final c in companias) c: {"en_cliente": 0, "vendido": 0}};
    for (final v in data) {
      final g = agrupa(v.compania);
      if (!companias.contains(g)) continue;
      final estado = v.origen == 'venta' ? 'vendido' : 'en_cliente';
      m[g]![estado] = (m[g]![estado] ?? 0) + 1;
    }
    return m;
  }

  /// Total general que suma SÓLO AT&T y Unefon
  int totalGeneral(List<VentaHist> data) {
    return data.where((v) {
      final g = agrupa(v.compania);
      return g == "AT&T" || g == "UNEFON";
    }).length;
  }

  Map<String, int> totalGeneralPorEstado(List<VentaHist> data) {
    int enCliente = 0;
    int vendido = 0;
    for (final v in data) {
      final g = agrupa(v.compania);
      if (g == "AT&T" || g == "UNEFON") {
        if (v.origen == 'venta') {
          vendido++;
        } else {
          enCliente++;
        }
      }
    }
    return {"en_cliente": enCliente, "vendido": vendido};
  }

  /// Tabla por vendedor -> total por compañía (con + expandible por lada).
  Map<String, Map<String, int>> porVendedorCompania(List<VentaHist> data) {
    final out = <String, Map<String, int>>{};
    for (final v in data) {
      final g = agrupa(v.compania);
      out.putIfAbsent(v.vendedorId, () => {for (final c in companias) c: 0});
      out[v.vendedorId]![g] = (out[v.vendedorId]![g] ?? 0) + 1;
    }
    return out;
  }

  /// Desglose por cliente de un vendedor (para la fila expandible).
  Map<String, Map<String, int>> clientesDeVendedor(
      List<VentaHist> data, String vendedorId) {
    final out = <String, Map<String, int>>{};
    for (final v in data.where((x) => x.vendedorId == vendedorId)) {
      final cli = v.clienteNombre.isEmpty ? "—" : v.clienteNombre;
      final g = agrupa(v.compania);
      out.putIfAbsent(cli, () => {for (final c in companias) c: 0});
      out[cli]![g] = (out[cli]![g] ?? 0) + 1;
    }
    return out;
  }

  /// Activación máxima por (cliente, compañía) = mayor venta mensual en los
  /// últimos [meses] meses presentes en los datos.
  Map<String, Map<String, int>> activacionMaxima(List<VentaHist> data,
      {int meses = 4}) {
    final periodos = data.map((v) => v.periodo).toSet().toList()..sort();
    final ultimos = periodos.length <= meses
        ? periodos.toSet()
        : periodos.sublist(periodos.length - meses).toSet();
    // conteo[cliente][compania][periodo]
    final conteo = <String, Map<String, Map<String, int>>>{};
    for (final v in data.where((x) => ultimos.contains(x.periodo))) {
      final g = agrupa(v.compania);
      conteo.putIfAbsent(v.clienteNombre, () => {});
      conteo[v.clienteNombre]!.putIfAbsent(g, () => {});
      final mp = conteo[v.clienteNombre]![g]!;
      mp[v.periodo] = (mp[v.periodo] ?? 0) + 1;
    }
    final out = <String, Map<String, int>>{};
    conteo.forEach((cli, porComp) {
      out[cli] = {};
      porComp.forEach((comp, porPer) {
        out[cli]![comp] =
            porPer.values.fold(0, (a, b) => a > b ? a : b); // máximo
      });
    });
    return out;
  }

  /// Fórmula validada contra el Power BI:
  /// pedido = ceil((maxima - inventario) * semanasASurtir / semanasRestantes)
  static int pedidoPorSurtir(int maxima, int inventario,
      {int semanasASurtir = 2, int semanasRestantes = 3}) {
    final deficit = maxima - inventario;
    final factor = semanasASurtir / semanasRestantes;
    if (deficit >= 0) return (deficit * factor).ceil();
    return -((deficit.abs() * factor).ceil());
  }

  /// Color de celda del pedido: amarillo si hay que surtir, rojo si sobra.
  static int colorPedido(int pedido) {
    if (pedido > 0) return 0xFFFFF200; // amarillo
    if (pedido < 0) return 0xFFFF4D4D; // rojo
    return 0x00000000; // sin color
  }
}

/// Color estable y "aleatorio" por vendedor (mismo id -> mismo color siempre).
Color colorDeVendedor(String vendedorId) {
  final h = vendedorId.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xffffff);
  final rng = math.Random(h);
  // Tonos vivos pero legibles (HSV con saturación/valor medio-altos).
  final hue = rng.nextDouble() * 360;
  return HSVColor.fromAHSV(1, hue, 0.55, 0.85).toColor();
}

/// --------------------------------------------------------------------------
/// Lógica del panel de Surtido (por cliente). Combina ventas (activación
/// máxima) con chips (inventario del cliente no vendido) para calcular cuánto
/// hay que surtir, replicando el Power BI.
/// --------------------------------------------------------------------------
class SurtidoLogic {
  final List<VentaHist> ventas;
  final List<Chip> chips;
  SurtidoLogic(this.ventas, this.chips);

  static const companiasSurtido = ["AT&T", "Unefon", "Movistar", "Telcel", "Bait"];
  static const companiasInv = ["AT&T", "Fieldway", "Movistar", "Telcel", "Telcel Porta", "Unefon", "Bait"];

  /// Normaliza los nombres de compañía viniendo de la BD / Excel
  static String normalizarComp(String c, {bool upper = false}) {
    final norm = c.trim().toUpperCase();
    if (norm.contains("ATT") || norm.contains("AT&T")) return "AT&T";
    if (norm.contains("UNE")) return upper ? "UNEFON" : "Unefon";
    if (norm.contains("MOV")) return "Movistar";
    if (norm.contains("TELCEL") && norm.contains("PORTA")) return "Telcel Porta";
    if (norm.contains("TELCEL")) return "Telcel";
    if (norm.contains("BAIT")) return "Bait";
    if (norm.contains("FIELD") || norm.contains("WAY")) return "Fieldway";
    if (norm.contains("POR DEFINIR")) return "Por definir";
    return c;
  }

  /// Arreglo de burbuja para ordenar y obtener el valor máximo
  static int bubbleSortMax(List<int> list) {
    if (list.isEmpty) return 0;
    final arr = List<int>.from(list);
    final n = arr.length;
    for (var i = 0; i < n - 1; i++) {
      for (var j = 0; j < n - i - 1; j++) {
        if (arr[j] > arr[j + 1]) {
          final temp = arr[j];
          arr[j] = arr[j + 1];
          arr[j + 1] = temp;
        }
      }
    }
    return arr.last;
  }

  /// Activación máxima por (cliente, compañía) = mayor venta mensual del
  /// cliente en los últimos [meses] meses. Usa ordenamiento de burbuja.
  /// Solo se cuentan registros de origen "venta" (Excel), NO escaneos de la app.
  Map<String, Map<String, int>> activacionMaximaPorCliente(
      List<VentaHist> data,
      {int meses = 4}) {
    // Filtrar solo las ventas reales (Excel), excluir escaneos de la app
    final soloVentas = data.where((v) => v.origen == 'venta').toList();

    final periodos = soloVentas.map((v) => v.periodo).toSet().toList()..sort();
    final ultimos = periodos.length <= meses
        ? periodos.toSet()
        : periodos.sublist(periodos.length - meses).toSet();
    
    // conteo[cliente][compania][periodo] = #ventas
    final conteo = <String, Map<String, Map<String, int>>>{};
    for (final v in soloVentas.where((x) => ultimos.contains(x.periodo))) {
      if (v.clienteNombre.isEmpty) continue;
      final normComp = normalizarComp(v.compania);
      final finalComp = normComp; 
      conteo.putIfAbsent(v.clienteNombre, () => {});
      conteo[v.clienteNombre]!.putIfAbsent(finalComp, () => {});
      final mp = conteo[v.clienteNombre]![finalComp]!;
      mp[v.periodo] = (mp[v.periodo] ?? 0) + 1;
    }

    final out = <String, Map<String, int>>{};
    conteo.forEach((cli, porComp) {
      out[cli] = {};
      porComp.forEach((comp, porPer) {
        final list = porPer.values.toList();
        out[cli]![comp] = bubbleSortMax(list);
      });
    });
    return out;
  }

  /// Calcula la tendencia (crecimiento %) por cliente comparando el último periodo (mes) con el anterior.
  Map<String, double?> tendenciaTotalPorCliente(List<VentaHist> data) {
    final soloVentas = data.where((v) => v.origen == 'venta').toList();
    final periodos = soloVentas.map((v) => v.periodo).toSet().toList()..sort();
    final out = <String, double?>{};
    if (periodos.length < 2) return out;
    
    final pActual = periodos.last;
    final pPrev = periodos[periodos.length - 2];
    
    final clientes = soloVentas.map((v) => v.clienteNombre).toSet();
    for (final cli in clientes) {
      final act = soloVentas.where((v) => v.periodo == pActual && v.clienteNombre == cli).length;
      final ant = soloVentas.where((v) => v.periodo == pPrev && v.clienteNombre == cli).length;
      if (ant > 0) {
        out[cli] = (act - ant) / ant * 100;
      } else if (act > 0) {
        out[cli] = 100.0;
      } else {
        out[cli] = null;
      }
    }
    return out;
  }

  /// Inventario del cliente = chips con su cliente_id y estado NO vendido.
  /// Devuelve: clienteId -> compañía -> cantidad.
  Map<String, Map<String, int>> inventarioPorCliente() {
    final out = <String, Map<String, int>>{};
    for (final c in chips) {
      if (c.clienteId.isEmpty) continue;
      if (c.estado.toLowerCase() == "vendido") continue;
      final normComp = normalizarComp(c.compania);
      out.putIfAbsent(c.clienteId, () => {});
      out[c.clienteId]![normComp] = (out[c.clienteId]![normComp] ?? 0) + 1;
    }
    return out;
  }

  /// Pedido por surtir según fórmula especificada:
  /// pedido = ceil((deficit / semanasRestantes) * 2.0).
  /// semanasRestantes = (diasDelMes / 7.0) - 1.0.
  static int pedido(int maxima, int inventario, int diasDelMes) {
    final deficit = maxima - inventario;
    final semanasTotales = diasDelMes / 7.0;
    final semanasRestantes = semanasTotales - 1.0;
    if (semanasRestantes <= 0) return deficit;
    final factor = 2.0 / semanasRestantes;
    if (deficit >= 0) {
      return (deficit * factor).ceil();
    } else {
      return -((deficit.abs() * factor).ceil());
    }
  }

  static int colorPedido(int pedido) {
    if (pedido <= -3) return 0xFFFF4D4D; // rojo
    if (pedido >= 1) return 0xFF4CAF50; // verde
    return 0x00000000;
  }
}
