import 'dart:async';

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
import 'core/services/notification_service.dart';
import 'core/sync/sync_engine.dart';
import 'features/activite/notifications_provider.dart';

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
  StreamSubscription<ClicNotification>? _abonnementClics;

  /// Compte pour lequel la permission de notification a déjà été demandée. Sans
  /// ce garde-fou, chaque revalidation de session en arrière-plan rouvrait la
  /// boîte de dialogue système.
  String? _permissionDemandeePour;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Un clic sur une bannière ouvre la page de l'objet concerné — la facture
    // encaissée, l'article dont le stock a bougé — et non l'accueil. La
    // souscription est posée avant tout affichage : le greffon rejoue le clic
    // qui a LANCÉ l'application, et il ne le rejoue qu'une fois.
    _abonnementClics =
        ref.read(notificationServiceProvider).clics.listen((clic) {
      final destination = clic.destination ?? '/activite';
      // `go` et non `push` : on arrive de l'extérieur, il n'y a pas de pile de
      // navigation à empiler par-dessus.
      ref.read(routerProvider).go(destination);
    });
    // L'état du verrou doit être connu avant la première décision de routage,
    // sinon l'application s'ouvre une fraction de seconde sur le tableau de
    // bord avant de se refermer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(verrouProvider.notifier).charger();
    });
  }

  @override
  void dispose() {
    _abonnementClics?.cancel();
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
        // La permission de notification se demande une fois connecté, pas au
        // premier écran : une boîte de dialogue système qui surgit avant qu'on
        // ait vu à quoi sert l'application se refuse par réflexe — et un refus
        // ne se redemande pas.
        if (_permissionDemandeePour != user.id) {
          _permissionDemandeePour = user.id;
          ref.read(notificationsProvider.notifier).demanderPermission();
        }
      } else {
        ref.read(syncEngineProvider).stop();
        // Les repères de lecture appartiennent au compte : les garder ferait
        // hériter le compte suivant de l'historique du précédent, et masquerait
        // pour lui des activités qu'il n'a jamais vues.
        _permissionDemandeePour = null;
        ref.read(notificationsProvider.notifier).reinitialiser();
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
