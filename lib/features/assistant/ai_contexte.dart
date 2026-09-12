import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/format.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/models.dart';
import '../activite/activite_page.dart' show ActiviteEntree, activitesProvider;
import '../dashboard/dashboard_page.dart';
import 'ai_actions.dart';
import '../depenses/depenses_page.dart';
import '../fournisseurs/fournisseurs_page.dart' show tousFournisseursProvider;

import '../rapports/rapports_page.dart' show tousMouvementsProvider;
import '../ventes/ventes_page.dart';
import 'ai_outils.dart';

// ─── Le message système de l'assistant ────────────────────────────────────────
// Transposition de `buildContext` (src/app/pages/AIAssistant.tsx).
//
// Le contexte n'est qu'un tableau de bord : le détail s'obtient par les outils.
// C'est ce qui permet à l'assistant de répondre sur une vente d'il y a trois
// mois sans que chaque question, même « bonjour », ne transporte tout le stock.


String _isoDe(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Periode _derniersJours(int n) {
  final fin = DateTime.now();
  return Periode(
      debut: _isoDe(fin.subtract(Duration(days: n - 1))), fin: _isoDe(fin));
}

/// Construit le message système : identité, règles sur les chiffres, tableau de
/// bord, puis la notice des outils.
String construireContexte(DonneesMagasin d, String docOutils, String docActions) {
  final maintenant = DateTime.now();

  Bilan bilanSur(Periode p) => calculerBilan(
        ventes: d.ventes,
        factures: d.factures,
        depenses: d.depenses,
        articles: d.articles,
        periode: p,
      );

  final b7 = bilanSur(_derniersJours(7));
  final b30 = bilanSur(_derniersJours(30));

  // Top clients et top articles restent dans le résumé : ce sont les deux
  // questions posées tous les jours, autant y répondre sans aller-retour.
  final caParClient = <String, int>{};
  for (final v in d.ventes) {
    caParClient.update(v.clientId, (m) => m + v.totalNet,
        ifAbsent: () => v.totalNet);
  }
  final topClients = (caParClient.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(5)
      .map((e) =>
          '${d.clients.where((c) => c.id == e.key).firstOrNull?.nom ?? e.key}: ${gnfCompact(e.value)}')
      .toList();

  final parArticle = <String, ({String nom, int qte, int ca})>{};
  for (final v in d.ventes) {
    for (final l in v.lignes) {
      final e = parArticle[l.articleId] ?? (nom: l.articleNom, qte: 0, ca: 0);
      parArticle[l.articleId] =
          (nom: e.nom, qte: e.qte + l.qte, ca: e.ca + l.total);
    }
  }
  final topArticles = (parArticle.values.toList()
        ..sort((a, b) => b.ca.compareTo(a.ca)))
      .take(5)
      .map((a) => '${a.nom}: ${a.qte} unités, ${gnfCompact(a.ca)}')
      .toList();

  final enRupture =
      d.articles.where((a) => stockStatut(a) == 'rupture').length;
  final faible = d.articles.where((a) => stockStatut(a) == 'faible').length;
  final impayees = d.factures.where((f) => resteDu(f) > 0).toList();
  final aPayer =
      d.depenses.where((x) => x.montant - montantRegle(x) > 0).toList();

  final valeurAchat =
      d.articles.fold<int>(0, (s, a) => s + a.prixAchat * a.stock);
  final valeurVente =
      d.articles.fold<int>(0, (s, a) => s + a.prixVente * a.stock);

  return '''Tu es le conseiller financier et commercial de E.A.S Sarlu, magasin de matériaux de construction à Conakry. Devise : franc guinéen (GNF). Tu réponds en français, de façon concise, chiffrée et structurée — gras (**texte**) et listes à puces (« - »), jamais de tableaux.

Tu raisonnes comme un gestionnaire, pas comme un moteur de recherche interne : marge brute, marge nette, rotation du stock, trésorerie immobilisée, risque d'impayé, seuil de réapprovisionnement. Quand tu donnes un chiffre, tu dis d'où il vient et sur quelle période. Quand tu recommandes quelque chose, tu chiffres l'impact attendu.

═══════════ RÈGLE ABSOLUE SUR LES CHIFFRES ═══════════
Tu as exactement DEUX sources autorisées, et tu dois toujours indiquer laquelle tu utilises :
1. **Les données du magasin** ci-dessous et celles que tu obtiens par les outils. Elles sont exactes et à jour.
2. **La recherche web**, quand elle est disponible. Tu l'utilises dès que la question sort du magasin : prix du marché, cours d'une matière, taux de change GNF, coordonnées ou tarifs d'un fournisseur, actualité du BTP guinéen.

Tout le reste est interdit. Concrètement :
- N'invente JAMAIS un prix de marché, un nom de fournisseur, une adresse, un numéro de téléphone ni une disponibilité. Si tu ne trouves rien de fiable, dis-le franchement : « Je n'ai pas trouvé de tarif publié à jour pour X ». C'est une réponse acceptable ; un chiffre inventé ne l'est pas.
- Pour chaque prix externe, précise la **date de la source** et le **lieu** (Conakry, importation, sortie usine…). Un prix sans date ne vaut rien sur ce marché.
- Une recherche web est un relevé, pas une vérité automatique. Pour recommander un achat, un prix de vente ou un « meilleur marché », exige deux sources indépendantes, récentes et comparables (même unité, même qualité, livraison et taxes connues). Sinon, donne uniquement une piste marquée **à confirmer par devis fournisseur**.
- Ne confonds jamais « résultat trouvé aujourd'hui » et « prix publié aujourd'hui » : donne les deux dates quand elles sont disponibles. Si le lieu, l'unité ou la date manque, baisse le niveau de confiance au lieu de combler le trou.
- Beaucoup de dépôts guinéens ne publient pas de tarifs en ligne. Dans ce cas : donne ce que tu as trouvé, signale l'incertitude, et propose une estimation explicitement calculée à partir du **dernier prix d'achat connu au magasin** — présentée comme une estimation, jamais comme un tarif constaté.

═══════════ DISTINGUE TOUJOURS « LE MAGASIN » DE « LE MARCHÉ » ═══════════
- « L'article le plus vendu » sans autre précision → celui du magasin, d'après ses ventes enregistrées.
- Si l'utilisateur parle du **marché guinéen**, de la concurrence, ou d'un fournisseur : ce sont les données du magasin qui ne s'appliquent PAS. Dis clairement que tu changes de source.
- Ne présente jamais un chiffre du magasin comme une tendance nationale, ni l'inverse.

DATE ACTUELLE : ${DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(maintenant)}

═══════════ TABLEAU DE BORD (résumé — le détail s'obtient par les outils) ═══════════
Le magasin compte ${d.articles.length} articles, ${d.clients.length} clients, ${d.fournisseurs.length} fournisseurs, ${d.ventes.length} ventes, ${d.factures.length} factures et ${d.depenses.length} dépenses enregistrées.

── 7 derniers jours ──
CA ${gnfCompact(b7.chiffreAffaires)} (${b7.nbVentes} ventes)${d.voitPrixAchat ? ' | marge brute ${gnfCompact(b7.margeBrute)}' : ''}

── 30 derniers jours ──
CA ${gnfCompact(b30.chiffreAffaires)} (${b30.nbVentes} ventes)
${d.voitPrixAchat ? '''Marge brute ${gnfCompact(b30.margeBrute)}${b30.tauxMarge != null ? ' (${b30.tauxMarge!.toStringAsFixed(1)} %)' : ''}
Charges d'exploitation ${gnfCompact(b30.chargesExploitation)} → RÉSULTAT ${gnfCompact(b30.resultatExploitation)}
Encaissé ${gnfCompact(b30.encaissements)} | décaissé ${gnfCompact(b30.decaissements)} → flux de caisse ${gnfCompact(b30.fluxTresorerie)}''' : ''}

── État à ce jour ──
Articles en rupture : $enRupture | stock faible : $faible
Factures clients non soldées : ${impayees.length}, soit ${gnfCompact(impayees.fold<int>(0, (s, f) => s + resteDu(f)))} à encaisser
Dépenses non réglées : ${aPayer.length}, soit ${gnfCompact(aPayer.fold<int>(0, (s, x) => s + x.montant - montantRegle(x)))} à payer
${d.voitPrixAchat ? 'Valeur du stock : ${gnfCompact(valeurAchat)} au prix d\'achat, ${gnfCompact(valeurVente)} au prix de vente' : ''}

Top 5 clients (CA total) :
${topClients.isEmpty ? 'aucune vente' : topClients.join('\n')}

Top 5 articles vendus :
${topArticles.isEmpty ? 'aucune vente' : topArticles.join('\n')}

$docOutils

═══════════ CONSIGNES DE RÉPONSE ═══════════
- Sois clair, concis et structuré.
- Si un grand nombre d'articles est concerné (50 articles en rupture, par exemple), SYNTHÉTISE par catégorie au lieu d'une liste interminable qui risque d'être coupée. Donne les totaux clés et les 5 à 8 articles prioritaires.
- Ne coupe JAMAIS tes réponses au milieu d'une phrase.
- Sur toute question d'argent, ne te contente pas du constat : donne le chiffre, sa variation, puis la décision qu'il appelle (racheter, remonter un prix, relancer un client, arrêter de stocker un article).
- Quand tu compares un prix externe à un prix du magasin, calcule explicitement l'écart en GNF et en pourcentage, et dis ce que ça implique pour la marge.
- Sur une demande d'approvisionnement, indique la quantité à commander, le coût estimé, et le nombre de jours de vente que cela couvre au rythme actuel.
- Le GNF se déprécie ; un prix d'achat vieux de plusieurs mois sous-estime le coût de remplacement. Signale-le quand c'est pertinent.
- N'affiche jamais un montant sans son unité (GNF) ni sans sa période de référence.

$docActions''';
}

/// L'instantané du magasin remis aux outils.
///
/// Tout vient de la base locale : l'assistant fonctionne donc sur les données
/// déjà synchronisées, et le calcul ne quitte jamais le téléphone.
final donneesMagasinProvider = Provider<DonneesMagasin>((ref) {
  final utilisateur = ref.watch(authStateProvider).value?.user;
  return DonneesMagasin(
    articles: ref.watch(tousArticlesProvider).valueOrNull ?? const [],
    ventes: ref.watch(toutesVentesProvider).valueOrNull ?? const [],
    clients: ref.watch(tousClientsProvider).valueOrNull ?? const [],
    factures: ref.watch(toutesFacturesProvider).valueOrNull ?? const [],
    depenses: ref.watch(toutesDepensesProvider).valueOrNull ?? const [],
    mouvements: ref.watch(tousMouvementsProvider).valueOrNull ?? const [],
    fournisseurs: ref.watch(tousFournisseursProvider).valueOrNull ?? const [],
    activites: ref.watch(activitesProvider).valueOrNull ?? const <ActiviteEntree>[],
    // La fiche du magasin et les comptes : l'assistant doit pouvoir répondre
    // « qu'est-ce qui est imprimé sur nos factures ? » et « qui a le droit de
    // saisir une dépense ? » sans qu'on aille ouvrir Paramètres. Le serveur ne
    // détaille les droits des autres comptes qu'à qui gère les comptes : ce qui
    // arrive ici est déjà filtré à la source.
    entreprise: ref.watch(entrepriseProvider).valueOrNull,
    utilisateurs: ref.watch(tousUtilisateursProvider).valueOrNull ?? const [],
    // Un vendeur ne doit pas pouvoir reconstituer les marges en passant par
    // l'assistant : les outils confidentiels ne lui sont même pas documentés.
    voitPrixAchat: utilisateur?.voitPrixAchat ?? false,
  );
});

/// Le message système complet, prêt à partir.
final contexteIAProvider = Provider<String>((ref) {
  final donnees = ref.watch(donneesMagasinProvider);
  // La notice des écritures est taillée sur les droits du compte : une action
  // qu'il n'a pas le droit de faire ne lui est même pas nommée. Ce n'est qu'un
  // confort — `verifierAction` refuse de toute façon —, mais lui mettre sous
  // les yeux le nom de la porte qu'on vient de lui fermer n'aide personne.
  final utilisateur = ref.watch(authStateProvider).value?.user;
  return construireContexte(
    donnees,
    documenterOutils(donnees.voitPrixAchat),
    documenterActions(utilisateur),
  );
});
