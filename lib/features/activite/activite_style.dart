// lib/features/activite/activite_style.dart

import 'package:flutter/material.dart';

import '../../core/models/activite.dart';

// ─── Habillage commun des activités ───────────────────────────────────────────
// L'icône et la couleur d'un type d'activité sont décidées ici, une fois. La
// page Activité et le menu du badge tenaient chacun son propre `switch` : le
// menu peignait un type « stock » que le serveur n'émet jamais, et ignorait les
// dépenses, qu'il émet six fois. Deux listes séparées finissent toujours par
// dire deux choses différentes du même événement.

IconData iconeActivite(String type) {
  switch (type) {
    case 'vente':
      return Icons.point_of_sale_rounded;
    case 'facture':
      return Icons.receipt_long_rounded;
    case 'depense':
      return Icons.money_off_rounded;
    case 'article':
      return Icons.inventory_2_rounded;
    case 'prix':
      return Icons.sell_rounded;
    case 'mouvement':
      return Icons.swap_vert_rounded;
    case 'client':
      return Icons.person_rounded;
    case 'utilisateur':
      return Icons.manage_accounts_rounded;
    case 'appareil':
      return Icons.phone_android_rounded;
    case 'parametres':
      return Icons.storefront_rounded;
    case 'sauvegarde':
      return Icons.backup_rounded;
    default:
      return Icons.history_rounded;
  }
}

/// Couleur d'accent d'un type d'activité.
///
/// Les teintes sont prises dans le schéma quand elles existent : une couleur
/// écrite en dur reste lisible en clair et illisible en sombre.
Color couleurActivite(BuildContext context, String type) {
  final scheme = Theme.of(context).colorScheme;
  switch (type) {
    case 'vente':
      return scheme.primary;
    case 'facture':
      return Colors.amber.shade800;
    case 'depense':
      return scheme.error;
    case 'article':
      return Colors.teal.shade600;
    case 'prix':
      return Colors.deepOrange.shade600;
    case 'mouvement':
      return Colors.purple.shade400;
    case 'client':
      return Colors.green.shade600;
    case 'utilisateur':
      return Colors.indigo.shade400;
    case 'appareil':
      return Colors.blueGrey;
    case 'parametres':
      return Colors.brown.shade400;
    case 'sauvegarde':
      return Colors.cyan.shade700;
    default:
      return scheme.onSurfaceVariant;
  }
}

/// Les filtres proposés sur la page Activité : « Tous », puis un par type
/// réellement émis par le serveur ([kTypesActivite]).
const List<(String, String)> kFiltresActivite = [
  ('', 'Tous'),
  ('vente', 'Ventes'),
  ('facture', 'Factures'),
  ('depense', 'Dépenses'),
  ('article', 'Catalogue'),
  ('prix', 'Prix'),
  ('mouvement', 'Mouvements'),
  ('client', 'Clients'),
  ('utilisateur', 'Comptes'),
  ('appareil', 'Appareils'),
  ('parametres', 'Paramètres'),
  ('sauvegarde', 'Sauvegardes'),
];
