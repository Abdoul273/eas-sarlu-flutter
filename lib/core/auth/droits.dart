// lib/core/auth/droits.dart

// ─── Droits d'accès ───────────────────────────────────────────────────────────
// Transposition de `src/lib/droits.ts` de l'application web.
//
// Ce fichier ne protège RIEN : il sert à masquer ce qui n'est pas permis. La
// protection réelle est dans le serveur, qui vérifie les mêmes droits sur chaque
// route ET sur chaque opération rejouée par la file hors ligne — sans quoi il
// suffirait de couper le réseau pour tout contourner.
//
// Masquer un bouton est un confort d'usage, pas une serrure. Mais proposer une
// action que le serveur refusera est une promesse qu'on ne tient pas : c'est
// pour cela que l'écran suit les droits, lui aussi.
//
// La liste doit rester identique à celle du serveur et à celle du web ; un test
// le vérifie en lisant directement les deux fichiers.

/// Tout ce qui peut être accordé ou refusé, et ce que cela recouvre.
const Map<String, String> kDroits = {
  'vendre': 'enregistrer une vente et encaisser un versement',
  'depenses': 'saisir une dépense et la régler',
  'stock': 'entrer du stock et tenir le catalogue',
  'finances': 'consulter les pages Finances et Rapports',
  'prixAchat': "voir les prix d'achat et les marges",
  'supprimer': 'supprimer un enregistrement ou annuler un règlement',
  'entreprise': "modifier la fiche de l'entreprise",
  'utilisateurs': 'gérer les comptes et leurs droits',
  'appareils': 'gérer les appareils de confiance',
  'maintenance': 'sauvegarder, restaurer ou remettre à zéro',
};

/// Intitulé court, pour l'affichage.
const Map<String, String> kLibelleDroit = {
  'vendre': 'Vendre et encaisser',
  'depenses': 'Saisir les dépenses',
  'stock': 'Entrer du stock et tenir le catalogue',
  'finances': 'Voir Finances et Rapports',
  'prixAchat': "Voir les prix d'achat et les marges",
  'supprimer': 'Supprimer et annuler',
  'entreprise': 'Modifier la fiche entreprise',
  'utilisateurs': 'Gérer les comptes et les droits',
  'appareils': 'Gérer les appareils de confiance',
  'maintenance': 'Sauvegarder, restaurer, réinitialiser',
};

/// Ne retient que des droits connus, sans doublon — on n'invente rien.
List<String> normaliserDroits(dynamic liste) {
  if (liste is! List) return const [];
  return kDroits.keys.where(liste.contains).toList();
}

/// Les droits d'administration : en détenir un seul suffit à ouvrir Paramètres.
const List<String> kDroitsAdministration = [
  'entreprise',
  'utilisateurs',
  'appareils',
  'maintenance',
];

/// Cet écran est-il ouvert au compte connecté ?
///
/// [aLeDroit] est la règle du compte — passée plutôt qu'importée pour que ce
/// fichier reste au-dessus des modèles et donc testable seul.
///
/// Un chemin inconnu est ouvert : mieux vaut laisser passer un écran anodin
/// qu'enfermer quelqu'un dehors sur une route ajoutée plus tard et oubliée ici.
/// Les écrans qui comptent, eux, sont nommés.
///
/// C'est la transposition de `estPageAutorisee` (src/lib/droits.ts) du web.
bool routeAutorisee(String chemin, bool Function(String) aLeDroit) {
  bool sur(String prefixe) => chemin == prefixe || chemin.startsWith('$prefixe/');

  // Le catalogue se consulte librement — vérifier ce qu'il reste en stock est
  // le geste le plus courant du comptoir. Le formulaire de création, lui, exige
  // le droit d'écrire : le serveur refuse l'enregistrement sans lui, et ouvrir
  // un formulaire dont la sauvegarde échouera n'est une faveur pour personne.
  if (sur('/stock/article/nouveau')) return aLeDroit('stock');

  if (sur('/ventes') || sur('/bons')) return aLeDroit('vendre');
  if (sur('/depenses')) return aLeDroit('depenses');
  // Une facture se consulte aussi bien pour encaisser que pour suivre les
  // créances : l'un ou l'autre droit suffit.
  if (sur('/factures')) return aLeDroit('vendre') || aLeDroit('finances');
  if (sur('/finances') || sur('/rapports')) return aLeDroit('finances');

  // `/parametres` reste ouvert à tous, volontairement : la page contient aussi
  // le mot de passe du compte, le code de déverrouillage, le thème et la
  // configuration de l'assistant IA — des réglages personnels que chacun doit
  // pouvoir toucher. Ce sont ses SECTIONS sensibles qui sont gardées, une par
  // une (fiche entreprise, comptes, appareils, sauvegardes). Fermer la page
  // entière privait un vendeur de son propre mot de passe.
  return true;
}
