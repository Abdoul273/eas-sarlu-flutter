// Vérifie la coque de l'application : barre de navigation basse, panneau
// hamburger et bouton flottant contextuel.
//
// Le cas dimensionnant est l'écran étroit avec la police système au maximum :
// c'est là que la barre du bas débordait.
import 'package:eas_sarlu/app/theme.dart';
import 'package:eas_sarlu/core/auth/auth_state.dart';
import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/core/sync/sync_state.dart';
import 'package:eas_sarlu/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notifier de synchronisation inerte : évite d'ouvrir la file d'attente
/// (et donc la base de données) dans un test d'interface.
class _SyncInerte extends SyncStateNotifier {
  _SyncInerte() : super(const Stream.empty());
}

/// Le gérant : propriétaire, donc toutes les entrées du menu lui sont ouvertes.
///
/// Le panneau masque désormais ce que le compte n'a pas le droit d'ouvrir ; un
/// compte sans droits n'y verrait ni Dépenses, ni Finances, ni Rapports.
class _AuthConnectee extends AuthNotifier {
  @override
  Future<AuthState> build() async => AuthState(
        user: Utilisateur(
          id: 'u1',
          nom: 'Abdoul Diallo',
          email: 'gerant@eas-sarlu.gn',
          proprietaire: true,
        ),
      );
}

/// Un vendeur : le comptoir, et rien de plus.
class _AuthVendeur extends AuthNotifier {
  @override
  Future<AuthState> build() async => AuthState(
        user: Utilisateur(
          id: 'u2',
          nom: 'Ibrahima Bah',
          email: 'ibrahima@eas-sarlu.gn',
          droits: const ['vendre'],
        ),
      );
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Monte la coque sur la route donnée, à la taille et à l'échelle de police
  /// demandées. `taille` est en pixels physiques (densité 2).
  Future<void> monterCoque(
    WidgetTester tester, {
    String route = '/ventes',
    double echelleTexte = 1.0,
    Size taille = const Size(824, 1600),
    AuthNotifier Function() compte = _AuthConnectee.new,
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: route,
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(title: 'E.A.S Sarlu', child: child),
          routes: [
            for (final chemin in const [
              '/accueil',
              '/ventes',
              '/stock',
              '/factures',
              '/clients',
            ])
              GoRoute(
                path: chemin,
                name: chemin.substring(1),
                builder: (context, state) => const SizedBox.expand(),
              ),
          ],
        ),
        // Cibles de navigation atteignables depuis la coque.
        for (final nom in const [
          'nouvelle-vente',
          'nouvel-article',
          'bons',
          'depenses',
          'finances',
          'rapports',
          'activite',
          'calculateur',
          'assistant',
          'parametres',
        ])
          GoRoute(
            path: '/cible-$nom',
            name: nom,
            builder: (context, state) => Scaffold(body: Text('page $nom')),
          ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(compte),
          syncStateProvider.overrideWith((ref) => _SyncInerte()),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(echelleTexte)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Barre de navigation basse', () {
    testWidgets('affiche les cinq destinations sans déborder', (tester) async {
      await monterCoque(tester);
      expect(tester.takeException(), isNull);
      for (final libelle in const [
        'Accueil',
        'Ventes',
        'Stock',
        'Factures',
        'Clients',
      ]) {
        expect(find.text(libelle), findsOneWidget);
      }
    });

    testWidgets('tient sur un écran étroit avec la police agrandie',
        (tester) async {
      // 320 dp de large — le plus petit écran Android courant.
      await monterCoque(
        tester,
        echelleTexte: 1.3,
        taille: const Size(640, 1280),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Factures'), findsOneWidget);
    });

    testWidgets('navigue vers la destination touchée', (tester) async {
      await monterCoque(tester, route: '/accueil');
      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Le bouton flottant du stock remplace celui de l'accueil.
      expect(find.byTooltip('Nouvel article'), findsOneWidget);
    });
  });

  group('Panneau hamburger', () {
    testWidgets('s\'ouvre et liste les destinations secondaires',
        (tester) async {
      await monterCoque(tester);
      await tester.tap(find.byTooltip('Ouvrir le menu'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Le panneau défile : ses entrées basses ne sont pas construites tant
      // qu'on n'a pas fait défiler jusqu'à elles. On les cherche donc comme le
      // ferait l'utilisateur. « Paramètres » et « Se déconnecter » sont dans le
      // pied fixe, toujours monté.
      for (final libelle in const [
        'Bons de livraison',
        'Dépenses',
        'Finances',
        'Rapports',
        'Activité',
        'Calculateur',
        'Assistant IA',
      ]) {
        await tester.scrollUntilVisible(
          find.text(libelle),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(libelle), findsOneWidget,
            reason: '« $libelle » doit figurer dans le panneau');
      }
      for (final libelle in const ['Paramètres', 'Se déconnecter']) {
        expect(find.text(libelle), findsOneWidget,
            reason: '« $libelle » doit figurer dans le pied du panneau');
      }
    });

    testWidgets('tient sur un écran étroit avec la police agrandie',
        (tester) async {
      await monterCoque(
        tester,
        echelleTexte: 1.3,
        taille: const Size(640, 1280),
      );
      await tester.tap(find.byTooltip('Ouvrir le menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('se referme et navigue quand on choisit une entrée',
        (tester) async {
      await monterCoque(tester);
      await tester.tap(find.byTooltip('Ouvrir le menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finances'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('page finances'), findsOneWidget);
      expect(find.text('Bons de livraison'), findsNothing); // panneau refermé
    });
  });

  group('Bouton flottant contextuel', () {
    testWidgets('la page Ventes porte un bouton « nouvelle vente » sans texte',
        (tester) async {
      await monterCoque(tester, route: '/ventes');

      final fab = find.byTooltip('Nouvelle vente');
      expect(fab, findsOneWidget);
      // Icône seule : pas de libellé dans le bouton.
      expect(
        find.descendant(of: fab, matching: find.byType(Text)),
        findsNothing,
      );
      expect(
        find.descendant(of: fab, matching: find.byIcon(Icons.add_shopping_cart_rounded)),
        findsOneWidget,
      );

      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('page nouvelle-vente'), findsOneWidget);
    });

    testWidgets('il n\'y a jamais deux boutons flottants à l\'écran',
        (tester) async {
      for (final route in const [
        '/accueil',
        '/ventes',
        '/stock',
        '/factures',
        '/clients',
      ]) {
        await monterCoque(tester, route: route);
        expect(
          tester.widgetList(find.byType(FloatingActionButton)).length,
          lessThanOrEqualTo(1),
          reason: 'route $route',
        );
      }
    });
  });

  group('Droits d\'accès', () {
    // Le panneau ne protège rien — le serveur refuse de toute façon — mais
    // proposer un écran qui ne donnera rien est une promesse qu'on ne tient pas.

    testWidgets('un vendeur ne voit pas les écrans qui lui sont fermés',
        (tester) async {
      await monterCoque(tester, compte: _AuthVendeur.new);
      await tester.tap(find.byTooltip('Ouvrir le menu'));
      await tester.pumpAndSettle();

      for (final libelle in const ['Dépenses', 'Finances', 'Rapports']) {
        expect(find.text(libelle), findsNothing, reason: libelle);
      }
      // Ce qui reste de son métier est bien là.
      expect(find.text('Clients'), findsWidgets);
    });

    testWidgets('les Paramètres restent ouverts à tous', (tester) async {
      // On y trouve son propre mot de passe, le code de déverrouillage, le
      // thème et l'assistant IA. Ce sont les sections sensibles de la page qui
      // sont gardées, pas la page.
      await monterCoque(tester, compte: _AuthVendeur.new);
      await tester.tap(find.byTooltip('Ouvrir le menu'));
      await tester.pumpAndSettle();

      expect(find.text('Paramètres'), findsWidgets);
      expect(find.text('Se déconnecter'), findsWidgets);
    });

    testWidgets('le propriétaire garde tout', (tester) async {
      await monterCoque(tester);
      await tester.tap(find.byTooltip('Ouvrir le menu'));
      await tester.pumpAndSettle();

      // Comme plus haut : le panneau défile, ses entrées basses ne sont
      // construites qu'une fois atteintes.
      for (final libelle in const ['Dépenses', 'Finances', 'Rapports']) {
        await tester.scrollUntilVisible(
          find.text(libelle),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      // Le pied est fixe, toujours monté.
      expect(find.text('Paramètres'), findsOneWidget);
    });
  });
}
