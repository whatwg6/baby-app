import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const background = Color(0xFFFFF9F3);
  static const card = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF352F2B);
  static const secondaryText = Color(0xFF857B73);
  static const primaryAccent = Color(0xFFE58F78);
  static const border = Color(0xFFEDE2D8);
  static const danger = Color(0xFFB94747);

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primaryAccent,
      onPrimary: card,
      secondary: secondaryText,
      onSecondary: card,
      surface: card,
      onSurface: primaryText,
      error: danger,
      onError: card,
      outline: border,
    ),
    scaffoldBackgroundColor: background,
    cardTheme: const CardThemeData(
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: primaryText),
      bodyMedium: TextStyle(color: primaryText),
      bodySmall: TextStyle(color: secondaryText),
      titleLarge: TextStyle(color: primaryText),
    ),
  );
}
