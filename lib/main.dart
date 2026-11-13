import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'features/auth/login_screen.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(MaterialApp(theme: buildTheme(Brightness.light), home: const SetupNeededScreen()));
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );
  final savedTheme = await loadSavedThemeMode();
  final savedAccent = await loadSavedAccent();
  runApp(ProviderScope(
    overrides: [
      initialThemeModeProvider.overrideWithValue(savedTheme),
      initialAccentProvider.overrideWithValue(savedAccent),
    ],
    child: const SareeDeskApp(),
  ));
}

class SareeDeskApp extends ConsumerStatefulWidget {
  const SareeDeskApp({super.key});
  @override
  ConsumerState<SareeDeskApp> createState() => _SareeDeskAppState();
}

class _SareeDeskAppState extends ConsumerState<SareeDeskApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Always refetch on foreground; realtime alone is never trusted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      theme: buildTheme(Brightness.light, seed: accent.color),
      darkTheme: buildTheme(Brightness.dark, seed: accent.color),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
