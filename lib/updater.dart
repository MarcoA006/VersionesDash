import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoUpdater {
  static const String _githubRepo = 'MarcoA006/VersionesDash';

  /// Convierte un string "v1.0.1" a "1.0.1"
  static String _cleanVersion(String v) => v.toLowerCase().replaceAll('v', '').trim();

  static Future<void> checkForUpdates(BuildContext context) async {
    // Solo actualizar en Windows
    if (!Platform.isWindows) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _cleanVersion(packageInfo.version);

      final uri = Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestTag = _cleanVersion(data['tag_name'] ?? '');
        
        if (latestTag.isNotEmpty && latestTag != currentVersion) {
          // Compara de forma muy sencilla (1.0.1 != 1.0.0). Para comparaciones
          // semánticas más avanzadas habría que separar por puntos, pero
          // si son distintos y estamos en latest, asumimos que es nuevo.
          
          final assets = data['assets'] as List<dynamic>?;
          if (assets != null && assets.isNotEmpty) {
            // Buscamos el primer zip
            final zipAsset = assets.firstWhere(
              (a) => a['name'].toString().toLowerCase().endsWith('.zip'),
              orElse: () => null,
            );

            if (zipAsset != null) {
              final downloadUrl = zipAsset['browser_download_url'];
              if (context.mounted) {
                _showUpdateDialog(context, latestTag, downloadUrl);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error verificando actualización: $e");
    }
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Actualización disponible"),
        content: Text("Hay una nueva versión disponible (v$newVersion).\n¿Deseas actualizar ahora?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Más tarde"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadAndInstall(context, downloadUrl);
            },
            child: const Text("Actualizar y Reiniciar"),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstall(BuildContext context, String url) async {
    // Diálogo de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        title: Text("Descargando actualización"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Por favor, no cierres la aplicación..."),
          ],
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}\\acc_admin_update');
      
      if (await updateDir.exists()) {
        await updateDir.delete(recursive: true);
      }
      await updateDir.create();

      final zipPath = '${updateDir.path}\\update.zip';

      // Descargar archivo
      final request = await http.get(Uri.parse(url));
      final file = File(zipPath);
      await file.writeAsBytes(request.bodyBytes);

      // Extraer
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final archiveFile in archive) {
        final filename = archiveFile.name;
        if (archiveFile.isFile) {
          final data = archiveFile.content as List<int>;
          final outFile = File('${updateDir.path}\\$filename');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory('${updateDir.path}\\$filename').create(recursive: true);
        }
      }

      await file.delete(); // borrar el zip temporal

      // Obtener ruta de instalación actual (directorio del ejecutable)
      final exePath = Platform.resolvedExecutable;
      final installDir = File(exePath).parent.path;
      final exeName = exePath.split(Platform.pathSeparator).last;

      // Crear archivo bat para la transición
      final batPath = '${updateDir.path}\\update.bat';
      final batContent = '''
@echo off
echo Esperando a que la aplicacion se cierre...
timeout /t 3 /nobreak > nul

echo Copiando archivos nuevos...
xcopy /s /y /q "${updateDir.path}\\*" "$installDir\\"

echo Reiniciando aplicacion...
start "" "$exePath"

echo Limpiando archivos temporales...
rmdir /s /q "${updateDir.path}"
''';
      
      final batFile = File(batPath);
      await batFile.writeAsString(batContent);

      // Lanzar el script en modo detached
      await Process.start(
        'cmd',
        ['/c', batPath],
        mode: ProcessStartMode.detached,
      );

      // Cerrar la aplicación para liberar los archivos
      exit(0);

    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // cerrar dialogo progreso
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al actualizar: $e")),
        );
      }
    }
  }
}
