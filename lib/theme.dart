// theme.dart -- Catppuccin Mocha riced theme and button styles.
//
// Import this and use `AppTheme.colors` or `AppTheme.buttonStyles`
// anywhere in the app for consistent riced styling.
import 'package:flutter/material.dart';

/// Catppuccin Mocha palette for riced UI.
class AppColors {
  // Base colors
  static const Color base = Color(0xFF1e1e2e);       // canvas
  static const Color surface = Color(0xFF313244);   // cards, panels
  static const Color overlay = Color(0xFF45475a);     // status bar, dividers
  static const Color lighter = Color(0xFFcdd6f4);    // text primary

  // Accents (use for buttons, highlights)
  static const Color blue = Color(0xFF89b4fa);       // primary action
  static const Color green = Color(0xFFa6e3a1);      // success, positive
  static const Color yellow = Color(0xFFf9e2af);     // warning
  static const Color red = Color(0xFFf38ba8);        // danger, destructive

  // Functional
  static const Color textPrimary = Color(0xFFcdd6f4);
  static const Color textOnSurface = Color(0xFFa6adc5);
  static const Color disabled = Color(0xFF6c7086);
}

class AppTheme {
  /// Build a light theme using DynamicColor when available.
  static ThemeData lightTheme(ColorScheme? dynamic) {
    final scheme = dynamic ?? const ColorScheme.light(
      primary: AppColors.blue,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      onPrimary: AppColors.base,
      onSecondary: AppColors.base,
      onSurface: AppColors.textPrimary,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 2,
      ),
      scaffoldBackgroundColor: AppColors.base,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary, height: 1.5),
        bodyMedium: TextStyle(color: AppColors.textOnSurface, height: 1.5),
      ),
    );
  }

  /// Build a dark theme using DynamicColor when available.
  static ThemeData darkTheme(ColorScheme? dynamic) {
    final scheme = dynamic ?? const ColorScheme.dark(
      primary: AppColors.blue,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      onPrimary: AppColors.base,
      onSecondary: AppColors.base,
      onSurface: AppColors.textPrimary,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 2,
      ),
      scaffoldBackgroundColor: AppColors.base,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary, height: 1.5),
        bodyMedium: TextStyle(color: AppColors.textOnSurface, height: 1.5),
      ),
    );
  }

  /// Primary action button style - filled with blue accent.
  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: AppColors.blue,
    foregroundColor: AppColors.base,
    textStyle: const TextStyle(fontWeight: FontWeight.w600),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  /// Secondary action button style - outlined with blue border.
  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    foregroundColor: AppColors.blue,
    side: const BorderSide(color: AppColors.blue, width: 1.5),
    textStyle: const TextStyle(fontWeight: FontWeight.w500),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  /// Tonal button style - uses surface tint.
  static final ButtonStyle tonalButton = FilledButton.styleFrom(
    backgroundColor: AppColors.overlay,
    foregroundColor: AppColors.lighter,
    textStyle: const TextStyle(fontWeight: FontWeight.w500),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  /// Destructive button style - red filled.
  static final ButtonStyle dangerButton = ElevatedButton.styleFrom(
    backgroundColor: AppColors.red,
    foregroundColor: Colors.white,
    textStyle: const TextStyle(fontWeight: FontWeight.w600),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  /// Text button style - minimal, for links.
  static final ButtonStyle textButton = TextButton.styleFrom(
    foregroundColor: AppColors.blue,
    textStyle: const TextStyle(fontWeight: FontWeight.w500),
  );

  /// Small command button for terminal controls (replaces commandButtonStyle).
  static final ButtonStyle commandButtonStyle = OutlinedButton.styleFrom(
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(0, 0),
    padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
    side: const BorderSide(color: AppColors.overlay, width: 1),
  );

  /// Control button for workflow controls (replaces controlButtonStyle).
  static final ButtonStyle controlButtonStyle = OutlinedButton.styleFrom(
    textStyle: const TextStyle(fontWeight: FontWeight.w400),
    side: const BorderSide(color: AppColors.overlay, width: 1),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(0, 0),
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
  );
}