import 'package:flutter/material.dart';

const bicimadSocialBlue = Color(0xFF0071CD);
const bicimadArcadeYellow = Color(0xFFFFD43B);
const bicimadArcadeRed = Color(0xFFFF3B30);

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: bicimadSocialBlue,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFEAF5FF),
    textTheme: const TextTheme().apply(
      bodyColor: Color(0xFF102033),
      displayColor: Color(0xFF102033),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: bicimadSocialBlue,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      margin: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFBFDFF5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: bicimadSocialBlue,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: bicimadSocialBlue,
        side: const BorderSide(color: bicimadSocialBlue, width: 1.5),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: bicimadArcadeYellow.withValues(alpha: 0.52),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? bicimadSocialBlue
            : const Color(0xFF526170);
        return TextStyle(color: color, fontWeight: FontWeight.w700);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? bicimadSocialBlue
            : const Color(0xFF526170);
        return IconThemeData(color: color);
      }),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: bicimadSocialBlue, width: 2),
      ),
    ),
  );
}
