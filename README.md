# ACC Admin — Panel de administración (Flutter Desktop)

CRUD de vendedores, clientes e inventario; asignar ICCID a vendedor; reasignar
clientes; cargar los reportes Excel; y control del killswitch. Compila a `.exe`
para Windows y a binario para Linux.

## Probar en Fedora (modo mock)

```bash
flutter config --enable-linux-desktop      # una sola vez
flutter pub get
flutter run -d linux
```

Viene con `Config.usarMock = true`. Login de prueba:
- Usuario: **superadmin**
- Contraseña: **admin**
- MFA (simulado): **000000**

## Secciones

- **Dashboard** — réplica del Power BI, en vivo desde la API (combina la tabla
  `escaneos` de la app + la tabla `ventas` de los Excel). Contadores por
  compañía (total del periodo filtrado), tabla por vendedor con `+` expandible
  por lada y color aleatorio estable por vendedor, ubicación GPS y export a
  Excel. Filtros de año / vendedor / lada: al elegir un vendedor, los
  contadores se reajustan a ese vendedor; al limpiar, vuelven a global. Botón
  "Actualizar" para re-leer la API.
- **Vendedores** — alta/modificar/eliminar. Contraseña con bcrypt. No deja
  eliminar a un vendedor que tiene clientes (primero reasígnalos/elimínalos).
- **Clientes** — alta/modificar/eliminar, filtro en vivo, reasignar a otro
  vendedor (botón ⇄).
- **Inventario** — lista de chips con filtro; marca varios ICCID y asígnalos a
  un vendedor de golpe.
- **Cargar Excel** — sube los tres reportes (ventas, inv. vendedor, inv.
  cliente); lee el archivo y muestra vista previa. El mapeo a la BD se ejecuta
  al conectar AppSheet.
- **Configuración** — killswitch global (con confirmación al bloquear) y los
  parámetros de la fórmula de surtido.

## Conectar a AppSheet

Igual que la app móvil: en `lib/config.dart` pon `usarMock = false` y llena
`appId` + `accessKey`. Un panel de escritorio que corre en una PC controlada es
un lugar mucho más razonable para la access key que el APK; aun así, lo ideal en
producción es un proxy del lado servidor.

> **Por qué el dashboard es una app de escritorio y no una web:** la API de
> AppSheet bloquea las llamadas directas desde un navegador (CORS) y expondría
> la access key en el JS del cliente. Una app Flutter de escritorio llama a la
> API en vivo sin ese problema, por eso el dashboard vive aquí y no como HTML
> estático. Para el dashboard necesitas crear en tu BD una tabla `ventas` con
> las columnas de tus Excel (fecha, vendedor/vendedor_id, cliente, producto,
> plaza, lat, lng); el código ya la lee y la combina con `escaneos`.

## Compilar a .exe (Windows)

Desde una máquina Windows con Flutter:
```bash
flutter config --enable-windows-desktop
flutter build windows
```
El ejecutable queda en `build\windows\x64\runner\Release\`. Esa carpeta
completa (con los .dll de al lado) es lo que se distribuye.

> Flutter no permite cross-compilar Windows desde Linux: el `.exe` se genera en
> Windows. Si solo tienes Fedora, usa una VM o GitHub Actions con un runner
> `windows-latest` (como ya hiciste para el .exe de PyInstaller).

## Estructura

```
lib/
  config.dart            credenciales + flag mock
  theme.dart             tema de escritorio
  models.dart            Admin, Vendedor, Cliente, Chip
  admin_backend.dart     interfaz CRUD + AppSheet + Mock
  admin_state.dart       sesión + cachés (Provider)
  main.dart              entrada
  screens/
    login_admin_screen.dart   login + MFA
    home_admin_screen.dart    navegación lateral
    vendedores_tab.dart
    clientes_tab.dart
    inventario_tab.dart
    cargar_tab.dart
    config_tab.dart           killswitch
```
