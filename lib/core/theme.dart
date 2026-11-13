import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A selectable accent. Material 3 derives the full light and dark palettes from the seed.
class AccentOption {
  const AccentOption(this.id, this.name, this.color);
  final String id;
  final String name;
  final Color color;
}

/// Brand colors live here only. Replace [brandSeed] once the real logo palette is known.
class Brand {
  /// Default accent: blue.
  static const brandSeed = Color(0xFF1565C0);
  static const sold = Color(0xFF8A8A8A);
  static const available = Color(0xFF2E7D32);
  static const warning = Color(0xFFB26A00);
}

const accentOptions = <AccentOption>[
  AccentOption('blue', 'Blue', Brand.brandSeed),
  AccentOption('indigo', 'Indigo', Color(0xFF3949AB)),
  AccentOption('teal', 'Teal', Color(0xFF00796B)),
  AccentOption('green', 'Green', Color(0xFF2E7D32)),
  AccentOption('maroon', 'Maroon', Color(0xFF8C2F4B)),
  AccentOption('purple', 'Purple', Color(0xFF6A1B9A)),
  AccentOption('orange', 'Orange', Color(0xFFE65100)),
];

AccentOption accentById(String? id) => accentOptions.firstWhere((a) => a.id == id, orElse: () => accentOptions.first);

ThemeData buildTheme(Brightness brightness, {Color seed = Brand.brandSeed}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
  );
}

// ---------------------------------------------------------------- theme mode (light / dark / system)
const _kThemeMode = 'theme_mode';

/// Read once in main() so the first frame already uses the saved choice (no flash).
Future<ThemeMode> loadSavedThemeMode() async {
  final p = await SharedPreferences.getInstance();
  return switch (p.getString(_kThemeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ---------------------------------------------------------------- accent color
const _kAccent = 'accent_color';

Future<AccentOption> loadSavedAccent() async {
  final p = await SharedPreferences.getInstance();
  return accentById(p.getString(_kAccent));
}

final initialAccentProvider = Provider<AccentOption>((ref) => accentOptions.first);

class AccentNotifier extends Notifier<AccentOption> {
  @override
  AccentOption build() => ref.read(initialAccentProvider);

  Future<void> set(AccentOption a) async {
    state = a;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccent, a.id);
  }
}

final accentProvider = NotifierProvider<AccentNotifier, AccentOption>(AccentNotifier.new);
