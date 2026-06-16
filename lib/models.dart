/// Modelos del panel admin. Iguales a los de la app móvil más Admin.

bool _bool(dynamic v) {
  final s = v?.toString().trim().toLowerCase();
  return s == 'true' || s == 'y' || s == 'yes' || s == '1';
}

/// Detecta la compañía a partir del texto del producto o del carrier del Excel.
/// Los valores devueltos coinciden exactamente con el Enum de AppSheet:
/// AT&T | UNEFON | MOVISTAR | TELCEL
String companiaDeProducto(String producto, {String carrier = ''}) {
  // Primero intentamos con el carrier (columna separada del Excel, p.ej. "ATT")
  final c = carrier.trim().toUpperCase();
  if (c == 'ATT' || c == 'AT&T') return 'AT&T';
  if (c.contains('UNE') || c == 'UNEFON') return 'UNEFON';
  if (c.contains('MOV') || c == 'MOVISTAR') return 'MOVISTAR';
  if (c.contains('TEL') || c == 'TELCEL') return 'TELCEL';

  // Si no hay carrier, detectamos por el nombre del producto
  final p = producto.trim().toUpperCase();
  // AT&T — variantes: ATT, AT&T, CHIP ATT, ACTIVA ATT
  if (p.contains('ATT') || p.contains('AT&T')) return 'AT&T';
  // UNEFON — variantes: UNE, UNEFON, ACTIVA UNE
  if (p.contains('UNE') || p.contains('UNEFON')) return 'UNEFON';
  // MOVISTAR — variantes: MOV, MOVISTAR
  if (p.contains('MOV') || p.contains('MOVISTAR')) return 'MOVISTAR';
  // TELCEL — variantes: TEL, TELCEL, EXPRESS (Chip Express es Telcel), Saldo Tel
  if (p.contains('TEL') || p.contains('TELCEL') ||
      p.contains('EXPRESS') || p.contains('SALDO')) return 'TELCEL';
  // BAIT
  if (p.contains('BAIT')) return 'BAIT';

  // Fallback: AT&T es el valor más común y siempre está en el Enum de AppSheet.
  // Evitamos mandar 'OTRO' que AppSheet rechaza.
  return 'AT&T';
}



class Admin {
  final String id;
  final String usuario;
  final String passwordHash;
  final String rol;
  final bool mfaHabilitado;
  final bool activo;
  Admin({
    required this.id,
    required this.usuario,
    required this.passwordHash,
    required this.rol,
    required this.mfaHabilitado,
    required this.activo,
  });
  factory Admin.fromJson(Map<String, dynamic> j) => Admin(
        id: (j['admin_id'] ?? '').toString(),
        usuario: (j['usuario'] ?? '').toString(),
        passwordHash: (j['password_hash'] ?? '').toString(),
        rol: (j['rol'] ?? '').toString(),
        mfaHabilitado: _bool(j['mfa_habilitado']),
        activo: _bool(j['activo']),
      );
}

class Vendedor {
  String id;
  String nombre;
  String usuario;
  String passwordHash;
  bool activo;
  Vendedor({
    required this.id,
    required this.nombre,
    required this.usuario,
    required this.passwordHash,
    required this.activo,
  });
  factory Vendedor.fromJson(Map<String, dynamic> j) => Vendedor(
        id: (j['vendedor_id'] ?? '').toString(),
        nombre: (j['nombre'] ?? '').toString(),
        usuario: (j['usuario'] ?? '').toString(),
        passwordHash: (j['password_hash'] ?? '').toString(),
        activo: _bool(j['activo']),
      );
}

class Cliente {
  String id;
  String nombre;
  String vendedorId;
  String rutaId;
  bool activo;
  DateTime? ultimaVisita;

  Cliente({
    required this.id,
    required this.nombre,
    required this.vendedorId,
    required this.rutaId,
    required this.activo,
    this.ultimaVisita,
  });
  factory Cliente.fromJson(Map<String, dynamic> j) => Cliente(
        id: (j['cliente_id'] ?? '').toString(),
        nombre: (j['nombre'] ?? '').toString(),
        vendedorId: (j['vendedor_id'] ?? 
            (j['cliente_vendedor'] != null && (j['cliente_vendedor'] as List).isNotEmpty 
                ? j['cliente_vendedor'][0]['vendedor_id'] 
                : '')).toString(),
        rutaId: (j['ruta_id'] ?? '').toString(),
        activo: _bool(j['activo']),
        ultimaVisita: j['ultima_visita'] != null ? DateTime.tryParse(j['ultima_visita'].toString()) : null,
      );
}

class Chip {
  String iccid;
  String dn;
  String producto;
  String compania;
  String estado;
  String vendedorId;
  String clienteId;
  final String lada;
  final DateTime? fechaAlta;
  final DateTime? fechaAsigVendedor;
  final DateTime? fechaAsigCliente;
  final DateTime? fechaVenta;
  final DateTime? fechaVinculadoCurp;

  Chip({
    required this.iccid,
    required this.dn,
    required this.producto,
    required this.compania,
    required this.estado,
    required this.vendedorId,
    required this.clienteId,
    required this.lada,
    this.fechaAlta,
    this.fechaAsigVendedor,
    this.fechaAsigCliente,
    this.fechaVenta,
    this.fechaVinculadoCurp,
  });
  factory Chip.fromJson(Map<String, dynamic> j) => Chip(
        iccid: (j['iccid'] ?? '').toString(),
        dn: (j['dn'] ?? '').toString(),
        producto: (j['producto'] ?? '').toString(),
        compania: (j['compania'] ?? '').toString(),
        estado: (j['estado'] ?? '').toString(),
        vendedorId: (j['vendedor_id'] ?? '').toString(),
        clienteId: (j['cliente_id'] ?? '').toString(),
        lada: (j['lada'] ?? '').toString(),
        fechaAlta: j['fecha_alta'] != null ? DateTime.tryParse(j['fecha_alta'].toString()) : null,
        fechaAsigVendedor: j['fecha_asig_vendedor'] != null ? DateTime.tryParse(j['fecha_asig_vendedor'].toString()) : null,
        fechaAsigCliente: j['fecha_asig_cliente'] != null ? DateTime.tryParse(j['fecha_asig_cliente'].toString()) : null,
        fechaVenta: j['fecha_venta'] != null ? DateTime.tryParse(j['fecha_venta'].toString()) : null,
        fechaVinculadoCurp: j['fecha_vinculado_curp'] != null ? DateTime.tryParse(j['fecha_vinculado_curp'].toString()) : null,
      );
}

class Escaneo {
  final String id;
  final String iccid;
  final String compania;
  final String vendedorId;
  final String clienteId;
  final double lat;
  final double lng;
  final DateTime? fechaHora;

  Escaneo({
    required this.id,
    required this.iccid,
    required this.compania,
    required this.vendedorId,
    required this.clienteId,
    required this.lat,
    required this.lng,
    this.fechaHora,
  });

  factory Escaneo.fromJson(Map<String, dynamic> j) => Escaneo(
        id: (j['id'] ?? '').toString(),
        iccid: (j['iccid'] ?? '').toString(),
        compania: (j['compania'] ?? '').toString(),
        vendedorId: (j['vendedor_id'] ?? '').toString(),
        clienteId: (j['cliente_id'] ?? '').toString(),
        lat: double.tryParse(j['lat']?.toString() ?? '0') ?? 0,
        lng: double.tryParse(j['lng']?.toString() ?? '0') ?? 0,
        fechaHora: j['fecha_hora'] != null ? DateTime.tryParse(j['fecha_hora'].toString()) : null,
      );
}

class Ruta {
  final String id;
  String nombre;
  String vendedorId;
  bool activa;

  Ruta({
    required this.id,
    required this.nombre,
    required this.vendedorId,
    required this.activa,
  });

  factory Ruta.fromJson(Map<String, dynamic> j) => Ruta(
        id: (j['id'] ?? '').toString(),
        nombre: (j['nombre'] ?? '').toString(),
        vendedorId: (j['vendedor_id'] ?? '').toString(),
        activa: j['activa'] == true || j['activa'] == 'true',
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'vendedor_id': vendedorId.isEmpty ? null : vendedorId,
        'activa': activa,
      };
}

/// Registro unificado de venta/activación que alimenta el dashboard.
/// Proviene tanto de 'escaneos' (app móvil) como de 'ventas' (Excel subidos).
class VentaHist {
  final DateTime fecha;
  final String vendedorId;
  final String clienteId;
  final String clienteNombre;
  final String compania; // AT&T, UNEFON, TELCEL, MOVISTAR
  final String lada;     // de 'plaza' o '' si no hay
  final double lat;
  final double lng;
  final String origen;   // "escaneo" | "venta"

  VentaHist({
    required this.fecha,
    required this.vendedorId,
    required this.clienteId,
    required this.clienteNombre,
    required this.compania,
    required this.lada,
    required this.lat,
    required this.lng,
    required this.origen,
  });

  int get anio => fecha.year;
  int get mes => fecha.month;
  String get periodo =>
      "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}";
}
