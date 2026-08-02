import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/auth/auth_state.dart';
import 'core/auth/verrou_local.dart';
import 'core/sync/sync_engine.dart';

/// Locale unique de l'application.
const kLocale = Locale('fr', 'FR');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  // Indispensable : sans cet appel, tout `DateFormat(..., 'fr_FR')` lève
  // LocaleDataException — les symboles de date ne sont pas chargés d'office.
  await initializeDateFormatting('fr_FR');
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const EasSarluApp(),
    ),
  );
}

class EasSarluApp extends ConsumerStatefulWidget {
  const EasSarluApp({super.key});

  @override
  ConsumerState<EasSarluApp> createState() => _EasSarluAppState();
}

class _EasSarluAppState extends ConsumerState<EasSarluApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // L'état du verrou doit être connu avant la première décision de routage,
    // sinon l'application s'ouvre une fraction de seconde sur le tableau de
    // bord avant de se refermer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(verrouProvider.notifier).charger();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(syncEngineProvider).onAppLifecycleChange(state);

    // Le verrou se referme dès que l'application quitte le premier plan, et
    // non au retour : la vignette affichée par Android dans la liste des
    // applications récentes montrerait sinon le dernier écran consulté —
    // chiffre d'affaires et créances compris.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(verrouProvider.notifier).verrouiller();
    }
  }

  @override
  Widget build(BuildContext context) {
    // `ref.listen` doit être appelé pendant le build (contrainte de Riverpod) :
    // démarre la synchronisation à la connexion, l'arrête à la déconnexion.
    ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, current) {
      final user = current.value?.user;
      if (user != null) {
        ref.read(syncEngineProvider).start();
      } else {
        ref.read(syncEngineProvider).stop();
      }
    });

    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'E.A.S Sarlu',
      debugShowCheckedModeBanner: false,
      // Sans ces délégués, les composants Material (sélecteur de date,
      // « Annuler »/« OK », etc.) restent en anglais.
      locale: kLocale,
      supportedLocales: const [kLocale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      // Garde-fou global : au-delà de ~1,3 la taille de police système fait
      // déborder les barres et les tuiles compactes, quelles que soient les
      // précautions prises dans les pages. On borne plutôt que de tronquer.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
