// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/models/models.dart';

// Ce que valent les données à leur ENTRÉE dans l'application.
//
// Tout arrive par `fromJson` — synchronisation, cache local, restauration de
// sauvegarde — donc c'est là que la normalisation doit se faire, et nulle part
// ailleurs. Ces tests portent les règles de `normaliserFacture`,
// `normaliserDepense` et `normaliserArticle` de l'application web
// (`src/lib/finance.ts`, `src/lib/inventaire.ts`).
//
// Ils comptent double : chacune de ces règles manquait, et chacune faisait
// afficher au téléphone un chiffre différent de celui du navigateur.

void main() {
  group('Facture — reprise des factures antérieures au suivi des versements',
      () {
    test('une ancienne facture marquée payée reçoit un versement de migration',
        () {
      // Sans cette reprise, une facture soldée depuis des mois redevenait une
      // créance sur le téléphone : le solde du client ne disait plus la même
      // chose que sur le navigateur.
      final f = Facture.fromJson({
        'id': 'F1',
        'venteId': 'V1',
        'clientId': 'C1',
        'dateEmission': '2026-03-15T10:00:00.000Z',
        'montantTTC': 130000,
        'statut': 'payée',
        'creePar': 'Mamadou',
      });

      expect(f.paiements, hasLength(1));
      expect(f.paiements.first.id, 'PAY_MIGR_F1');
      expect(f.paiements.first.montant, 130000);
      expect(f.paiements.first.date, '2026-03-15T10:00:00.000Z');
      expect(f.paiements.first.utilisateur, 'Mamadou');
      expect(f.statut, 'payée');
      expect(resteDu(f), 0);
    });

    test('une ancienne facture qui n\'était pas marquée payée reste due', () {
      final f = Facture.fromJson({
        'id': 'F1',
        'venteId': 'V1',
        'clientId': 'C1',
        'dateEmission': '2026-03-15T10:00:00.000Z',
        'montantTTC': 130000,
        'statut': 'non payée',
      });

      expect(f.paiements, isEmpty);
      expect(f.statut, 'non payée');
      expect(resteDu(f), 130000);
    });

    test('aucun versement n\'est fabriqué quand il en existe déjà', () {
      // Le statut enregistré dit « payée », les versements disent le contraire :
      // ce sont les versements qui font foi.
      final f = Facture.fromJson({
        'id': 'F1',
        'venteId': 'V1',
        'clientId': 'C1',
        'dateEmission': '2026-03-15T10:00:00.000Z',
        'montantTTC': 130000,
        'statut': 'payée',
        'paiements': [
          {'id': 'P1', 'date': '2026-03-15T10:00:00.000Z', 'montant': 40000},
        ],
      });

      expect(f.paiements, hasLength(1));
      expect(f.paiements.first.id, 'P1');
      expect(f.statut, 'non payée');
      expect(resteDu(f), 90000);
    });

    test('les statuts abandonnés « en attente » et « en retard » restent dus',
        () {
      for (final ancien in ['en attente', 'en retard']) {
        final f = Facture.fromJson({
          'id': 'F1',
          'venteId': 'V1',
          'clientId': 'C1',
          'montantTTC': 130000,
          'statut': ancien,
        });
        expect(f.paiements, isEmpty, reason: 'statut « $ancien »');
        expect(f.statut, 'non payée', reason: 'statut « $ancien »');
      }
    });

    test('le statut déduit repart bien vers le serveur', () {
      final f = Facture.fromJson({
        'id': 'F1',
        'venteId': 'V1',
        'clientId': 'C1',
        'montantTTC': 130000,
        'statut': 'payée',
      });
      expect(f.toJson()['statut'], 'payée');
    });
  });

  group('Depense — la nature se recalcule, elle ne se lit pas', () {
    test('la nature enregistrée est ignorée au profit de la catégorie', () {
      // La dépense prétend être une charge ; le catalogue dit « marchandise »,
      // et c'est lui qui fait autorité.
      final d = Depense.fromJson({
        'id': 'D1',
        'date': '2026-03-10T08:00:00.000Z',
        'categorie': 'Achat de marchandise',
        'nature': 'exploitation',
        'montant': 500000,
      });
      expect(d.nature, 'marchandise');
    });

    test('une catégorie inconnue est traitée comme une charge d\'exploitation',
        () {
      final d = Depense.fromJson({
        'id': 'D1',
        'date': '2026-03-10T08:00:00.000Z',
        'categorie': "Catégorie d'une vieille sauvegarde",
        'montant': 500000,
      });
      expect(d.nature, 'exploitation');
    });

    test('une catégorie absente devient « Divers »', () {
      final d = Depense.fromJson({
        'id': 'D1',
        'date': '2026-03-10T08:00:00.000Z',
        'categorie': '',
        'montant': 500000,
      });
      expect(d.categorie, 'Divers');
      expect(d.nature, 'exploitation');
    });

    test('le statut se recalcule depuis les règlements', () {
      final d = Depense.fromJson({
        'id': 'D1',
        'date': '2026-03-10T08:00:00.000Z',
        'categorie': 'Loyer',
        'montant': 500000,
        'statut': 'non réglée',
        'reglements': [
          {'id': 'R1', 'date': '2026-03-20T10:00:00.000Z', 'montant': 500000},
        ],
      });
      expect(d.statut, 'réglée');
    });

    test('nature et statut déduits repartent bien vers le serveur', () {
      final d = Depense.fromJson({
        'id': 'D1',
        'date': '2026-03-10T08:00:00.000Z',
        'categorie': 'Véhicule',
        'nature': 'exploitation',
        'montant': 500000,
      });
      expect(d.toJson()['nature'], 'investissement');
      expect(d.toJson()['statut'], 'non réglée');
    });
  });

  group('Article — épaisseur des articles antérieurs au suivi', () {
    test('une épaisseur absente vaut zéro et jamais null', () {
      // Sans cela, l'écran affichait « null mm » sur tout l'ancien stock.
      final a = Article.fromJson({'id': 'A1', 'nom': 'Tube', 'unite': 'Barre'});
      expect(a.epaisseur, 0);
    });

    test('le poids de barre des anciens articles n\'est pas pris pour une épaisseur',
        () {
      // 31,4 kg n'est pas une épaisseur : le champ est abandonné, pas converti.
      final a = Article.fromJson({
        'id': 'A1',
        'nom': 'Tube',
        'unite': 'Barre',
        'poidsBarre': 31.4,
      });
      expect(a.epaisseur, 0);
    });

    test('une épaisseur renseignée est conservée telle quelle', () {
      final a = Article.fromJson({
        'id': 'A1',
        'nom': 'Tôle',
        'unite': 'Feuille',
        'epaisseur': 0.45,
      });
      expect(a.epaisseur, 0.45);
    });
  });

  group('Montants — arrondi et non troncature', () {
    // L'application web ne stocke pas des entiers : un total de ligne y vaut
    // `prixVente × qte × (1 − remise/100)` sans arrondi, et c'est à l'affichage
    // qu'elle arrondit. Tronquer ici ferait afficher 128 333 au téléphone là où
    // le navigateur affiche 128 334.
    test('un montant de facture fractionnaire est arrondi, pas tronqué', () {
      final f = Facture.fromJson({
        'id': 'F1',
        'venteId': 'V1',
        'clientId': 'C1',
        'montantTTC': 130000.6,
      });
      expect(f.montantTTC, 130001);
    });

    test('un total de vente fractionnaire est arrondi', () {
      final v = Vente.fromJson({
        'id': 'V1',
        'clientId': 'C1',
        'date': '2026-03-15T10:00:00.000Z',
        'totalHT': 128333.7,
        'totalNet': 128333.7,
      });
      expect(v.totalNet, 128334);
    });

    test('un versement fractionnaire est arrondi', () {
      final p = Paiement.fromJson(
          {'id': 'P1', 'date': '2026-03-15', 'montant': 49999.5});
      expect(p.montant, 50000);
    });

    test('une facture soldée au franc près tombe bien à zéro', () {
      // Le reste dû ne doit jamais valoir « 0,4 GNF » : une facture doit
      // pouvoir se solder exactement.
      final f = Facture.fromJson({
        'id': 'F1',
        'venteId': 'V1',
        'clientId': 'C1',
        'montantTTC': 130000.4,
        'paiements': [
          {'id': 'P1', 'date': '2026-03-15', 'montant': 130000.4},
        ],
      });
      expect(resteDu(f), 0);
      expect(f.statut, 'payée');
    });
  });

  group('Remises venues de l\'application web', () {
    // Le magasin n'accorde pas de remise et l'application Android n'en fait pas
    // saisir, mais une vente enregistrée au navigateur peut en porter une : elle
    // doit s'afficher telle qu'elle a été faite.
    test('une remise fractionnaire est conservée', () {
      final l = LigneVente.fromJson(
          {'articleId': 'A1', 'qte': 1, 'prixUnitaire': 130000, 'remise': 15.5});
      expect(l.remise, 15.5);
    });

    test('une remise aberrante est ramenée dans les bornes', () {
      expect(
          LigneVente.fromJson({'articleId': 'A1', 'remise': 150}).remise, 100.0);
      expect(
          LigneVente.fromJson({'articleId': 'A1', 'remise': -10}).remise, 0.0);
    });

    test('une remise absente vaut zéro', () {
      expect(LigneVente.fromJson({'articleId': 'A1'}).remise, 0.0);
    });
  });
}
