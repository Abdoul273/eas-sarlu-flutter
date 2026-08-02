// Le cycle complet d'un achat de marchandise, du camion du fournisseur jusqu'au
// résultat du mois.
//
// C'est LA question du gérant : « j'ai payé cinq millions de fer à mon
// fournisseur — où est-ce que ça apparaît ? » La réponse tient en trois
// endroits différents, et les confondre est la faute la plus coûteuse qu'on
// puisse faire sur ces chiffres :
//
//   — la CAISSE baisse le jour où l'on paie le fournisseur ;
//   — le RÉSULTAT ne bouge pas ce jour-là : la marchandise n'est pas perdue,
//     elle est en dépôt. Elle n'entre au résultat qu'à la revente, par le coût
//     d'achat des marchandises vendues ;
//   — la DETTE fournisseur existe dès la livraison, et s'éteint au règlement.
//
// Un magasin peut donc être bénéficiaire et sans un franc, ou plein d'argent et
// en train de perdre. Ces tests vérifient que l'application sait dire lequel.

// ignore_for_file: avoid_relative_lib_imports
import '../lib/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  // Août 2026. Le magasin achète, paie, puis revend.
  const aout = Periode(debut: '2026-08-01', fin: '2026-08-31');
  const septembre = Periode(debut: '2026-09-01', fin: '2026-09-30');

  // 100 barres à 60 000 = 6 000 000 GNF d'achat.
  final unArticle = article(prixAchat: 60000, prixVente: 85000, stock: 100);

  Depense achatFer({List<Reglement> reglements = const []}) => depense(
        id: 'd-fer',
        date: '2026-08-05T09:00:00.000Z',
        categorie: 'Achat de marchandise',
        montant: 6000000,
        reglements: reglements,
      );

  group('À la livraison, avant tout paiement', () {
    test('la caisse ne bouge pas, le résultat non plus, la dette apparaît', () {
      final b = calculerBilan(
        ventes: const [],
        factures: const [],
        depenses: [achatFer()],
        articles: [unArticle],
        periode: aout,
      );

      expect(b.decaissements, 0, reason: 'rien n\'est encore sorti de la caisse');
      expect(b.dettesFournisseurs, 6000000,
          reason: 'le magasin doit six millions à son fournisseur');

      // Et surtout : le résultat est intact. C'est le point le plus
      // contre-intuitif de toute l'application, et le plus important.
      expect(b.chargesExploitation, 0,
          reason: 'un achat de marchandise n\'est PAS une charge du mois');
      expect(b.resultatExploitation, 0);
      expect(b.achatsMarchandises, 6000000,
          reason: 'il doit être visible quelque part, sinon on le croit oublié');
    });
  });

  group('Au paiement du fournisseur', () {
    final regle = achatFer(reglements: [
      reglement(id: 'r1', date: '2026-08-20T09:00:00.000Z', montant: 6000000),
    ]);

    test('la caisse baisse de six millions, le résultat reste à zéro', () {
      final b = calculerBilan(
        ventes: const [],
        factures: const [],
        depenses: [regle],
        articles: [unArticle],
        periode: aout,
      );

      expect(b.decaissements, 6000000);
      expect(b.fluxTresorerie, -6000000,
          reason: 'la caisse est vidée de six millions');
      expect(b.dettesFournisseurs, 0, reason: 'la dette est éteinte');

      // Le magasin n'a rien perdu : il a échangé de l'argent contre du fer.
      expect(b.resultatExploitation, 0);
    });

    test('un paiement partiel laisse le reste en dette', () {
      final partiel = achatFer(reglements: [
        reglement(id: 'r1', date: '2026-08-20T09:00:00.000Z', montant: 2000000),
      ]);
      final b = calculerBilan(
        ventes: const [],
        factures: const [],
        depenses: [partiel],
        articles: [unArticle],
        periode: aout,
      );

      expect(b.decaissements, 2000000);
      expect(b.dettesFournisseurs, 4000000);
    });

    test('payé en septembre, l\'achat reste une dette au 31 août', () {
      // Le point qui fait diverger tous les arrêtés mal faits : c'est la date
      // du MOUVEMENT D'ARGENT qui compte pour la caisse, et l'état à la date
      // de clôture qui compte pour la dette.
      final tardif = achatFer(reglements: [
        reglement(id: 'r1', date: '2026-09-10T09:00:00.000Z', montant: 6000000),
      ]);

      final enAout = calculerBilan(
        ventes: const [], factures: const [], depenses: [tardif],
        articles: [unArticle], periode: aout,
      );
      expect(enAout.decaissements, 0);
      expect(enAout.dettesFournisseurs, 6000000);

      final enSeptembre = calculerBilan(
        ventes: const [], factures: const [], depenses: [tardif],
        articles: [unArticle], periode: septembre,
      );
      expect(enSeptembre.decaissements, 6000000);
      expect(enSeptembre.dettesFournisseurs, 0);
      expect(enSeptembre.achatsMarchandises, 0,
          reason: 'l\'achat a été ENGAGÉ en août, pas en septembre');
    });
  });

  group('À la revente', () {
    // 40 barres vendues à 85 000 = 3 400 000 de chiffre d'affaires.
    final venteFer = vente(
      id: 'v1',
      date: '2026-08-25T10:00:00.000Z',
      totalNet: 3400000,
      lignes: [ligne(articleId: 'A1', qte: 40, prixUnitaire: 85000, total: 3400000)],
    );

    test('seules les barres VENDUES entrent au résultat', () {
      final b = calculerBilan(
        ventes: [venteFer],
        factures: const [],
        depenses: [achatFer()],
        articles: [unArticle],
        periode: aout,
      );

      expect(b.chiffreAffaires, 3400000);
      // 40 barres × 60 000 = 2 400 000, et non les 6 000 000 achetés.
      expect(b.coutMarchandises, 2400000,
          reason: 'les 60 barres encore en dépôt ne coûtent rien au résultat');
      expect(b.margeBrute, 1000000);
      expect(b.resultatExploitation, 1000000);
      expect(b.tauxMarge, closeTo(29.4, 0.1));
    });

    test('le chiffre d\'affaires ignore complètement les achats', () {
      final sansAchat = calculerBilan(
        ventes: [venteFer], factures: const [], depenses: const [],
        articles: [unArticle], periode: aout,
      );
      final avecAchat = calculerBilan(
        ventes: [venteFer], factures: const [],
        depenses: [achatFer(reglements: [
          reglement(id: 'r1', date: '2026-08-20T09:00:00.000Z', montant: 6000000),
        ])],
        articles: [unArticle], periode: aout,
      );

      expect(sansAchat.chiffreAffaires, avecAchat.chiffreAffaires,
          reason: 'acheter n\'a jamais fait vendre');
    });
  });

  group('Le mois entier, vu des deux côtés', () {
    test('bénéficiaire ET à découvert : les deux lectures se contredisent',
        () {
      // Le cas qui décide de la survie du magasin. Sur le mois :
      //   — on a payé 6 000 000 au fournisseur ;
      //   — on a vendu 3 400 000, dont le client n'a réglé que 1 000 000.
      final b = calculerBilan(
        ventes: [
          vente(
            id: 'v1',
            date: '2026-08-25T10:00:00.000Z',
            totalNet: 3400000,
            lignes: [ligne(articleId: 'A1', qte: 40, prixUnitaire: 85000, total: 3400000)],
          ),
        ],
        factures: [
          facture(
            id: 'f1',
            dateEmission: '2026-08-25T10:00:00.000Z',
            montantTTC: 3400000,
            paiements: [
              paiement(id: 'p1', date: '2026-08-26T10:00:00.000Z', montant: 1000000),
            ],
          ),
        ],
        depenses: [
          achatFer(reglements: [
            reglement(id: 'r1', date: '2026-08-20T09:00:00.000Z', montant: 6000000),
          ]),
          // Et le loyer, lui, EST une charge du mois.
          depense(
            id: 'd-loyer',
            date: '2026-08-01T09:00:00.000Z',
            categorie: 'Loyer',
            montant: 500000,
            reglements: [
              reglement(id: 'r2', date: '2026-08-01T09:00:00.000Z', montant: 500000),
            ],
          ),
        ],
        articles: [unArticle],
        periode: aout,
      );

      // Côté RÉSULTAT : le commerce gagne de l'argent.
      expect(b.margeBrute, 1000000);
      expect(b.chargesExploitation, 500000,
          reason: 'le loyer est une charge, l\'achat de fer non');
      expect(b.resultatExploitation, 500000);

      // Côté CAISSE : le magasin est très en dessous de zéro sur le mois.
      expect(b.encaissements, 1000000);
      expect(b.decaissements, 6500000);
      expect(b.fluxTresorerie, -5500000);

      // Et ce qui reste dehors explique l'écart.
      expect(b.creancesClients, 2400000, reason: '3 400 000 − 1 000 000 encaissé');
      expect(b.dettesFournisseurs, 0);

      // La vérification qui compte : les deux lectures ne s'additionnent pas et
      // ne se contredisent pas — elles répondent à deux questions différentes.
      expect(b.resultatExploitation, isPositive);
      expect(b.fluxTresorerie, isNegative);
    });

    test('les sorties de caisse hors résultat sont toutes visibles', () {
      // Sinon le gérant cherche où sont passés ses millions et conclut que
      // l'application les a perdus.
      final b = calculerBilan(
        ventes: const [],
        factures: const [],
        depenses: [
          achatFer(),
          depense(
            id: 'd-camion',
            date: '2026-08-10T09:00:00.000Z',
            categorie: 'Véhicule',
            montant: 40000000,
          ),
        ],
        articles: [unArticle],
        periode: aout,
      );

      expect(b.achatsMarchandises, 6000000);
      expect(b.investissements, 40000000);
      expect(b.chargesExploitation, 0);
      expect(b.resultatExploitation, 0,
          reason: 'ni le fer ni le camion ne s\'imputent au résultat du mois');
    });

    test('la ventilation par catégorie sépare engagé et décaissé', () {
      final b = calculerBilan(
        ventes: const [],
        factures: const [],
        depenses: [
          achatFer(reglements: [
            reglement(id: 'r1', date: '2026-08-20T09:00:00.000Z', montant: 2000000),
          ]),
        ],
        articles: [unArticle],
        periode: aout,
      );

      final fer = b.parCategorie
          .firstWhere((c) => c.categorie == 'Achat de marchandise');
      expect(fer.nature, 'marchandise');
      expect(fer.engage, 6000000, reason: 'ce que le fournisseur a livré');
      expect(fer.decaisse, 2000000, reason: 'ce qu\'on lui a effectivement versé');
      expect(fer.nombre, 1);
    });
  });

  group('Trésorerie depuis l\'origine', () {
    test('« En caisse » compte le paiement du fournisseur', () {
      // Le chiffre du tableau de bord doit refléter l'argent réellement sorti,
      // sans quoi le gérant croit disposer de six millions qu'il a déjà versés.
      final factures = [
        facture(
          id: 'f1',
          montantTTC: 3400000,
          paiements: [paiement(id: 'p1', montant: 3400000)],
        ),
      ];
      final depenses = [
        achatFer(reglements: [
          reglement(id: 'r1', date: '2026-08-20T09:00:00.000Z', montant: 6000000),
        ]),
      ];

      expect(tresorerieNette(factures: factures, depenses: depenses),
          3400000 - 6000000);
    });
  });
}
