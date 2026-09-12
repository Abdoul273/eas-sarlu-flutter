import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/auth/auth_state.dart';
import '../core/auth/verrou_local.dart';
import '../features/auth/verrou_page.dart';
import '../features/activite/activite_page.dart';
import '../features/assistant/assistant_page.dart';
import '../features/assistant/live/live_page.dart';
import '../features/auth/auth_gate_page.dart';
import '../features/bons/bons_livraison_page.dart';
import '../features/calculateur/calculateur_page.dart';
import '../features/clients/client_detail_page.dart';
import '../features/clients/clients_page.dart';
import '../features/fournisseurs/fournisseur_detail_page.dart';
import '../features/fournisseurs/fournisseurs_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/depenses/depense_form_page.dart';
import '../features/depenses/depenses_page.dart';
import '../features/factures/facture_detail_page.dart';
import '../features/factures/factures_page.dart';
import '../features/finances/finances_page.dart';
import '../features/parametres/parametres_page.dart';
import '../features/proformas/proformas_page.dart';
import '../features/rapports/rapports_page.dart';
import '../features/stock/article_detail_page.dart';
import '../features/stock/article_form_page.dart';
import '../features/stock/stock_page.dart';
import '../features/ventes/nouvelle_vente_page.dart';
import '../features/ventes/modifier_vente_page.dart';
import '../features/ventes/ventes_page.dart';
import '../shell/app_shell.dart';
import '../core/models/models.dart';

/// Les six onglets du shell : la barre du bas et le tiroir y mènent par `go`,
/// qui REMPLACE la pile — on change d'onglet, on ne s'empile pas.
const Set<String> kOngletsShell = {
  'accueil', 'ventes', 'stock', 'factures', 'clients', 'fournisseurs',
};

/// Ouvre une destination nommée en respectant sa nature.
///
/// Un onglet se rejoint par `go`. Tout le reste — Dépenses, Finances,
/// Rapports, Calculateur, Assistant, Paramètres, Activité, Bons — est une page
/// qui se POUSSE par-dessus l'onglet courant : « retour » y ramène. Ces pages
/// étaient ouvertes par `go`, qui vidait la pile ; leur bouton retour n'avait
/// plus rien à dépiler et renvoyait à l'accueil, d'où que l'on vienne.
///
/// Si la page demandée est déjà celle du dessus, on ne l'empile pas une
/// seconde fois.
void ouvrirRoute(BuildContext context, String nom,
    {Map<String, String> pathParameters = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? extra}) {
  if (kOngletsShell.contains(nom)) {
    context.goNamed(nom,
        pathParameters: pathParameters, queryParameters: queryParameters);
    return;
  }
  // Lu sur le routeur et non par `GoRouterState.of` : le tiroir appelle
  // ceci depuis le contexte du Navigator, qui n'est sous aucune route.
  final config = GoRouter.of(context).routerDelegate.currentConfiguration;
  final route = config.isEmpty ? null : config.last.route;
  if (route is GoRoute && route.name == nom) return;
  context.pushNamed(nom,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      extra: extra);
}

class RouterRefreshListenable extends ChangeNotifier {
  RouterRefreshListenable(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(verrouProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = RouterRefreshListenable(ref);
  ref.onDispose(() => refreshListenable.dispose());

  return GoRouter(
    initialLocation: '/accueil',
    refreshListenable: refreshListenable,
    // Deux portes successives, et une seule exige le réseau.
    //
    //   1. La connexion au compte (`/auth`) : uniquement à l'installation ou
    //      après une déconnexion volontaire. La session est ensuite conservée
    //      sur l'appareil, si bien qu'une panne de réseau ne renvoie plus ici.
    //   2. Le verrou local (`/verrou`) : à chaque ouverture, vérifié hors ligne.
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final verrou = ref.read(verrouProvider);

      final chemin = state.uri.path;
      final connecte = authState.value?.estConnecte ?? false;
      final surAuth = chemin.startsWith('/auth');
      final surVerrou = chemin == '/verrou';

      // Tant que la session et le verrou n'ont pas fini de se charger, on ne
      // redirige nulle part : rediriger sur un état inconnu ferait clignoter
      // l'écran de connexion à chaque démarrage.
      if (authState.isLoading || verrou.etat == EtatVerrou.inconnu) return null;

      if (!connecte) return surAuth ? null : '/auth';

      final ferme = verrou.etat == EtatVerrou.verrouille ||
          verrou.etat == EtatVerrou.aDefinir;
      if (ferme) return surVerrou ? null : '/verrou';

      // Session ouverte et verrou passé : les écrans d'entrée n'ont plus lieu
      // d'être.
      if (surAuth || surVerrou) return '/accueil';

      // Troisième porte : les droits du compte.
      final user = authState.value?.user;
      if (user != null && !routeAutorisee(chemin, user.aLeDroit)) {
        return '/accueil';
      }
      return null;
    },
    routes: [
      // Route de la porte d'authentification (sans shell)
      GoRoute(
        path: '/auth',
        name: 'auth-gate',
        builder: (context, state) => const AuthGatePage(),
      ),
      GoRoute(
        path: '/verrou',
        name: 'verrou',
        builder: (context, state) => const VerrouPage(),
      ),
      // Routes avec shell (accessibles seulement si connecté)
      ShellRoute(
        builder: (context, state, child) {
          final String title = _getTitle(state.name);
          return AppShell(title: title, child: child);
        },
        routes: [
          GoRoute(
            path: '/accueil',
            name: 'accueil',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardPage(),
            ),
          ),
          GoRoute(
            path: '/ventes',
            name: 'ventes',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: VentesPage(),
            ),
          ),
          GoRoute(
            path: '/stock',
            name: 'stock',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: StockPage(),
            ),
          ),
          GoRoute(
            path: '/factures',
            name: 'factures',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FacturesPage(),
            ),
          ),
          GoRoute(
            path: '/clients',
            name: 'clients',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ClientsPage(),
            ),
          ),
          GoRoute(
            path: '/fournisseurs',
            name: 'fournisseurs',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FournisseursPage(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/ventes/nouvelle',
        name: 'nouvelle-vente',
        builder: (context, state) {
          final clientId = state.uri.queryParameters['clientId'];
          final articleId = state.uri.queryParameters['articleId'];
          final quantite =
              int.tryParse(state.uri.queryParameters['quantite'] ?? '');
          final extraMap = state.extra as Map<String, dynamic>?;
          final articlesPreremplis =
              extraMap?['articles'] as List<Map<String, dynamic>>?;
          return NouvelleVentePage(
            clientId: clientId,
            articleId: articleId,
            quantite: quantite,
            articlesPreremplis: articlesPreremplis,
            proformaId: state.uri.queryParameters['proformaId'],
          );
        },
      ),
      GoRoute(
        path: '/ventes/:id/modifier',
        name: 'modifier-vente',
        builder: (context, state) => ModifierVenteParId(
          venteId: state.pathParameters['id']!,
          vente: state.extra is Vente ? state.extra as Vente : null,
        ),
      ),
      GoRoute(
        path: '/stock/article/nouveau',
        name: 'nouvel-article',
        builder: (context, state) => const ArticleFormPage(),
      ),
      GoRoute(
        path: '/stock/article/:id',
        name: 'detail-article',
        builder: (context, state) => ArticleDetailPage(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/factures/:id',
        name: 'detail-facture',
        builder: (context, state) => FactureDetailPage(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/clients/:id',
        name: 'detail-client',
        builder: (context, state) => ClientDetailPage(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/fournisseurs/:id',
        name: 'detail-fournisseur',
        builder: (context, state) => FournisseurDetailPage(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/proformas',
        name: 'proformas',
        builder: (context, state) => const ProformasPage(),
      ),
      GoRoute(
        path: '/bons',
        name: 'bons',
        builder: (context, state) => const BonsLivraisonPage(),
      ),
      GoRoute(
        path: '/depenses',
        name: 'depenses',
        builder: (context, state) => const DepensesPage(),
      ),
      GoRoute(
        path: '/depenses/nouvelle',
        name: 'nouvelle-depense',
        builder: (context, state) => const DepenseFormPage(),
      ),
      GoRoute(
        path: '/finances',
        name: 'finances',
        builder: (context, state) => const FinancesPage(),
      ),
      GoRoute(
        path: '/rapports',
        name: 'rapports',
        builder: (context, state) => const RapportsPage(),
      ),
      GoRoute(
        path: '/activite',
        name: 'activite',
        builder: (context, state) => const ActivitePage(),
      ),
      GoRoute(
        path: '/calculateur',
        name: 'calculateur',
        builder: (context, state) => const CalculateurPage(),
      ),
      GoRoute(
        path: '/assistant',
        name: 'assistant',
        builder: (context, state) => const AssistantPage(),
      ),
      // Le mode vocal se pousse par-dessus la discussion, en plein écran.
      GoRoute(
        path: '/assistant/vocal',
        name: 'assistant-vocal',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LivePage(),
          transitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (context, anim, _, child) {
            final courbe =
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: courbe,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(courbe),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: '/parametres',
        name: 'parametres',
        builder: (context, state) => const ParametresPage(),
      ),
    ],
  );
});

/// Titre affiché dans l'AppBar du shell selon la route active.
String _getTitle(String? routeName) {
  switch (routeName) {
    case 'accueil':
      return 'E.A.S Sarlu';
    case 'ventes':
      return 'Ventes';
    case 'stock':
      return 'Stock';
    case 'factures':
      return 'Factures';
    case 'clients':
      return 'Clients';
    case 'fournisseurs':
      return 'Fournisseurs';
    default:
      return 'E.A.S Sarlu';
  }
}
