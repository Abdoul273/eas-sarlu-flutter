import '../../app/format.dart';
import '../models/models.dart';

// ─── Les règles d'une vente ───────────────────────────────────────────────────
// Une seule source pour ce qu'une vente a le droit de faire. Les deux écrans
// (nouvelle vente, modification) et l'assistant s'y réfèrent AVANT d'écrire :
// le stock ne descend jamais sous zéro, une quantité est au moins de un, un
// prix est positif, et un article qui a disparu du catalogue ne se vend pas.
//
// Ces règles tiennent lieu de dernier rempart. Les écrans bornent déjà ce
// que l'on peut saisir, mais un panier pré-rempli depuis un devis, un stock
// qui a bougé par synchronisation entre l'ouverture de la page et
// l'encaissement, ou une quantité tapée au clavier passaient à côté — et le
// magasin affichait « −1 barre ».

/// Ce qu'une ligne demande : indépendant de la classe `LignePanier` de chaque
/// écran, qui n'est pas partagée.
class DemandeLigne {
  final String articleId;
  final int quantite;
  final int prixUnitaire;
  const DemandeLigne(this.articleId, this.quantite, this.prixUnitaire);
}

/// Une règle enfreinte, dite au commerçant.
class ProblemeVente {
  final String articleId;
  final String message;

  /// Ce qu'on peut vendre au plus, quand c'est une question de stock ;
  /// `null` sinon. Sert à l'écran pour proposer la correction.
  final int? quantiteMax;

  const ProblemeVente(this.articleId, this.message, {this.quantiteMax});
}

/// Passe un panier au crible des stocks courants.
///
/// [credit] : pour une MODIFICATION, les quantités que cette même vente a déjà
/// sorties, par article. Elles reviennent au pot avant qu'on retranche le
/// nouveau panier — sans cela, corriger une vente qui avait vidé le stock
/// serait impossible.
List<ProblemeVente> problemesVente(
  List<DemandeLigne> lignes,
  Map<String, Article> articles, {
  Map<String, int> credit = const {},
}) {
  final problemes = <ProblemeVente>[];
  final demandeParArticle = <String, int>{};

  for (final l in lignes) {
    final a = articles[l.articleId];
    if (a == null) {
      problemes.add(ProblemeVente(
          l.articleId, 'Un article du panier n\'existe plus au catalogue.'));
      continue;
    }
    if (l.quantite <= 0) {
      problemes.add(ProblemeVente(
          a.id, '${a.nom} : la quantité doit être d\'au moins 1.'));
    }
    if (l.prixUnitaire <= 0) {
      problemes.add(
          ProblemeVente(a.id, '${a.nom} : le prix unitaire doit être positif.'));
    }
    demandeParArticle.update(a.id, (q) => q + l.quantite,
        ifAbsent: () => l.quantite);
  }

  for (final e in demandeParArticle.entries) {
    final a = articles[e.key];
    if (a == null) continue;
    final disponible = a.stock + (credit[a.id] ?? 0);
    if (e.value > disponible) {
      problemes.add(ProblemeVente(
        a.id,
        disponible <= 0
            ? '${a.nom} : plus rien en stock.'
            : '${a.nom} : il ne reste que ${fmtNombre(disponible)} ${a.unite}, '
                'le panier en demande ${fmtNombre(e.value)}.',
        quantiteMax: disponible < 0 ? 0 : disponible,
      ));
    }
  }
  return problemes;
}

/// Le stock après une sortie de [quantite] : jamais négatif.
///
/// Un négatif ne peut venir que d'une écriture qui a contourné les règles ou
/// d'un serveur qui a tranché autrement ; à l'écran, on le borne, et le
/// serveur borne de même.
int stockApresSortie(int stock, int quantite) {
  final apres = stock - quantite;
  return apres < 0 ? 0 : apres;
}

/// Le stock après un retour de [quantite] au dépôt.
int stockApresRetour(int stock, int quantite) => stock + quantite;
