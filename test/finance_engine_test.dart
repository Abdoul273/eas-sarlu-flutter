// ignore_for_file: avoid_relative_lib_imports
import '../lib/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('FinanceEngine - Core Math Tests', () {
    test('borneRemise clamps between 0 and 100', () {
      expect(borneRemise(-5), 0.0);
      expect(borneRemise(0), 0.0);
      expect(borneRemise(15.5), 15.5);
      expect(borneRemise(120), 100.0);
      expect(borneRemise(null), 0.0);
    });

    test('natureDe categorizes expenses accurately matching web app', () {
      expect(natureDe('Achat de marchandise'), 'marchandise');
      expect(natureDe('Équipement & outillage'), 'investissement');
      expect(natureDe('Loyer'), 'exploitation');
      expect(natureDe('Autre inconnue'), 'exploitation');
    });

    test('dansPeriode handles string ISO dates safely without timezone bugs', () {
      const p = Periode(debut: '2026-07-01', fin: '2026-07-31');
      expect(dansPeriode('2026-07-01T08:30:00Z', p), isTrue);
      expect(dansPeriode('2026-07-31T23:59:59Z', p), isTrue);
      expect(dansPeriode('2026-06-30T23:59:59Z', p), isFalse);
      expect(dansPeriode('2026-08-01T00:00:00Z', p), isFalse);
    });

    test('calculerBilan computes accurate accounting metrics', () {
      final articles = [
        Article(
          id: 'art1',
          nom: 'Ciment CPJ 42.5',
          unite: 'sac',
          prixVente: 85000,
          prixAchat: 65000,
          stock: 100,
          stockMin: 10,
        ),
      ];

      final ventes = [
        Vente(
          id: 'v1',
          numero: 'VNT-001',
          date: '2026-07-15T10:00:00Z',
          clientId: 'c1',
          lignes: [
            LigneVente(
              articleId: 'art1',
              qte: 10,
              prixUnitaire: 85000,
              total: 850000,
            ),
          ],
          totalHT: 850000,
          totalNet: 850000,
        ),
      ];

      final factures = [
        Facture(
          id: 'f1',
          numero: 'FAC-001',
          venteId: 'v1',
          clientId: 'c1',
          dateEmission: '2026-07-15T10:00:00Z',
          dateEcheance: '2026-07-30',
          montantHT: 850000,
          montantTTC: 850000,
          paiements: [
            Paiement(
              id: 'p1',
              date: '2026-07-15T10:00:00Z',
              montant: 850000,
              mode: 'espèce',
            ),
          ],
        ),
      ];

      final depenses = [
        Depense(
          id: 'd1',
          numero: 'DEP-001',
          date: '2026-07-10T09:00:00Z',
          categorie: 'Loyer',
          libelle: 'Loyer dépôt',
          beneficiaire: 'Bailleur',
          montant: 100000,
          reglements: [
            Reglement(
              id: 'r1',
              date: '2026-07-10T09:00:00Z',
              montant: 100000,
              mode: 'virement',
            ),
          ],
        ),
      ];

      const pJul = Periode(debut: '2026-07-01', fin: '2026-07-31');
      final bilan = calculerBilan(
        ventes: ventes,
        factures: factures,
        depenses: depenses,
        articles: articles,
        periode: pJul,
      );

      expect(bilan.chiffreAffaires, 850000);
      expect(bilan.coutMarchandises, 650000); // 10 * 65000
      expect(bilan.margeBrute, 200000); // 850000 - 650000
      expect(bilan.chargesExploitation, 100000);
      expect(bilan.resultatExploitation, 100000); // 200000 - 100000
      expect(bilan.encaissements, 850000);
      expect(bilan.decaissements, 100000);
      expect(bilan.fluxTresorerie, 750000); // 850000 - 100000
    });
  });

  group('stockApresMouvement', () {
    test('une entrée ajoute, une sortie retranche', () {
      expect(stockApresMouvement(10, 'entrée', 5), 15);
      expect(stockApresMouvement(10, 'sortie', 5), 5);
    });

    test('un ajustement REMPLACE le stock, il ne s\'y ajoute pas', () {
      // C'est le sens d'un inventaire : on ne dit pas de combien on s'est
      // trompé, on dit ce qu'il y a réellement en dépôt. Le serveur applique la
      // même règle (mode « absolu » de applyStock).
      expect(stockApresMouvement(10, 'ajustement', 3), 3);
      expect(stockApresMouvement(0, 'ajustement', 42), 42);
    });

    test('jamais de stock négatif', () {
      // Le serveur borne aussi à zéro : laisser passer un négatif à l'écran
      // ferait diverger les deux affichages sans que rien ne le signale.
      expect(stockApresMouvement(3, 'sortie', 10), 0);
    });

    test('une quantité négative est lue en valeur absolue', () {
      expect(stockApresMouvement(10, 'entrée', -5), 15);
      expect(stockApresMouvement(10, 'sortie', -5), 5);
    });
  });

  // ─── Trésorerie ─────────────────────────────────────────────────────────────
  // Le chiffre affiché sous « En caisse » sur le tableau de bord. Les mêmes
  // affirmations existent mot pour mot dans `src/lib/__tests__/finance.test.ts`
  // de l'application web : les deux applications regardent le même magasin et
  // ne peuvent pas en annoncer deux états différents.

  group('tresorerieNette', () {
    test("compte l'argent entré moins l'argent sorti", () {
      final f = facture(
        montantTTC: 500000,
        paiements: [paiement(montant: 300000)],
      );
      final d = depense(
        montant: 500000,
        reglements: [reglement(montant: 120000)],
      );

      expect(tresorerieNette(factures: [f], depenses: [d]), 180000);
    });

    test("ignore ce qui n'a pas bougé : le dû n'est pas de l'encaissé", () {
      // Être bénéficiaire et sans un franc est un état parfaitement possible :
      // c'est exactement ce que cette lecture doit savoir dire.
      final f = facture(montantTTC: 500000);
      final d = depense(montant: 500000);

      expect(tresorerieNette(factures: [f], depenses: [d]), 0);
    });

    test("devient négatif quand on a plus payé qu'encaissé", () {
      final f = facture(paiements: [paiement(montant: 50000)]);
      final d = depense(reglements: [reglement(montant: 200000)]);

      expect(tresorerieNette(factures: [f], depenses: [d]), -150000);
    });

    test('se restreint à une période sur la date du MOUVEMENT, pas de la pièce',
        () {
      // Un versement de mars sur une facture de février est une recette de mars.
      final f = facture(
        dateEmission: '2026-02-10T10:00:00.000Z',
        paiements: [paiement(date: '2026-03-05T10:00:00.000Z', montant: 90000)],
      );

      expect(
          tresorerieNette(
              factures: [f], depenses: [], periode: Periode.mois(2026, 2)),
          0);
      expect(
          tresorerieNette(
              factures: [f], depenses: [], periode: Periode.mois(2026, 3)),
          90000);
    });

    test('dit la même chose que le flux de trésorerie du bilan', () {
      final factures = [
        facture(paiements: [paiement(montant: 300000)])
      ];
      final depenses = [
        depense(reglements: [reglement(montant: 120000)])
      ];
      final bilan = calculerBilan(
        ventes: const [],
        factures: factures,
        depenses: depenses,
        articles: const [],
      );

      expect(tresorerieNette(factures: factures, depenses: depenses),
          bilan.fluxTresorerie);
    });
  });
}
