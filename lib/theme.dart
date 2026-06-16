import 'package:flutter/material.dart';

class AppColors {
  static const Color fondo = Color(0xFFEDF0F4);
  static const Color superficie = Color(0xFFFFFFFF);
  static const Color texto = Color(0xFF1A1D21);
  static const Color acento = Color(0xFF1F4E78);
  static const Color exito = Color(0xFF1B8A3A);
  static const Color alerta = Color(0xFFC62828);
  static const Color amarillo = Color(0xFFFFC400);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.acento,
      primary: AppColors.acento,
      surface: AppColors.superficie,
    ),
    scaffoldBackgroundColor: AppColors.fondo,
  );
  return base.copyWith(
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.superficie,
      isDense: true,
      border: OutlineInputBorder(),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.acento,
        foregroundColor: Colors.white,
      ),
    ),
  );
}
