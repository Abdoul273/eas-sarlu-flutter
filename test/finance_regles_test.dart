// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/models/models.dart';
import 'fixtures.dart';

// Portage de `src/lib/__tests__/finance.test.ts` de l'application web.
//
// Les deux applications partagent le même serveur : un chiffre lu sur le
// téléphone doit être le même que celui lu au navigateur. Ces tests affirment
// les mêmes règles, sur les mêmes valeurs, que la suite web — c'est ce qui
// permet de constater une divergence au lieu de la découvrir dans un rapport
// remis à la banque.
//
// Attention à une différence de convention : `periodeMois` du web compte les
// mois à partir de zéro, `Periode.mois` ici à partir de un. Mars s'écrit donc
// `periodeMois(2026, 2)` là-bas et `Periode.mois(2026, 3)` ici.

void main() {
  group('montantPaye', () {
    test('additionne les versements', () {
      final f = facture(paiements: [
        paiement(montant: 30000),
        paiement(id: 'P2', montant: 20000),
      ]);
      expect(montantPaye(f), 50000);
    });

    test('vaut zéro sans versement', () {
      expect(montantPaye(facture()), 0);
    });
  });

  group('resteDu', () {
    test('retranche les versements du montant TTC', () {
      final f = facture(
          montantTTC: 130000, paiements: [paiement(montant: 50000)]);
      expect(resteDu(f), 80000);
    });

    test('tombe exactement à zéro quand la facture est soldée', () {
      final f = facture(
          montantTTC: 130000, paiements: [paiement(montant: 130000)]);
      expect(resteDu(f), 0);
    });

    test('ne descend jamais sous zéro en cas de trop-perçu', () {
      final f = facture(
          montantTTC: 100000, paiements: [paiement(montant: 150000)]);
      expect(resteDu(f), 0);
    });
  });

  group('tropPercu', () {
    test('expose le surplus versé au lieu de l\'absorber', () {
      final f = facture(
          montantTTC: 100000, paiements: [paiement(montant: 150000)]);
      expect(tropPercu(f), 50000);
    });

    test('vaut zéro tant que la facture n\'est pas dépassée', () {
      expect(
          tropPercu(facture(
              montantTTC: 100000, paiements: [paiement(montant: 100000)])),
          0);
      expect(tropPercu(facture(montantTTC: 100000)), 0);
    });
  });

  group('statutFacture', () {
    // Le statut est un getter dérivé : contrairement au web, il n'existe même
    // pas de champ « statut » à faire mentir. Ces tests verrouillent la règle.
    test('vaut « non payée » tant que rien n\'est versé', () {
      expect(facture(montantTTC: 130000).statut, 'non payée');
    });

    test('passe à payée dès que le reste dû est nul', () {
      expect(
          facture(montantTTC: 130000, paiements: [paiement(montant: 130000)])
              .statut,
          'payée');
    });

    test('reste non payée sur un versement partiel', () {
      expect(
          facture(montantTTC: 130000, paiements: [paiement(montant: 129999)])
              .statut,
          'non payée');
    });
  });

  group('enRetard', () {
    final maintenant = DateTime.parse('2026-05-01T00:00:00.000Z');

    test('signale une facture due dont l\'échéance est passée', () {
      expect(enRetard(facture(dateEcheance: '2026-04-15'), maintenant), isTrue);
    });

    test('ne signale pas une facture soldée, même en retard', () {
      final f = facture(
          dateEcheance: '2026-04-15',
          montantTTC: 130000,
          paiements: [paiement(montant: 130000)]);
      expect(enRetard(f, maintenant), isFalse);
    });

    test('ne signale pas une facture due dont l\'échéance est à venir', () {
      expect(enRetard(facture(dateEcheance: '2026-06-15'), maintenant), isFalse);
    });

    test('ne signale pas une échéance illisible plutôt que d\'inventer', () {
      expect(enRetard(facture(dateEcheance: ''), maintenant), isFalse);
    });
  });

  group('soldeClient / avoirClient', () {
    final factures = [
      facture(
          id: 'F1',
          clientId: 'C1',
          montantTTC: 100000,
          paiements: [paiement(montant: 40000)]),
      facture(id: 'F2', clientId: 'C1', montantTTC: 50000),
      facture(id: 'F3', clientId: 'C2', montantTTC: 900000),
      facture(
          id: 'F4',
          clientId: 'C1',
          montantTTC: 20000,
          paiements: [paiement(montant: 30000)]),
    ];

    test('cumule le dû du seul client demandé', () {
      expect(soldeClient(factures, 'C1'), 60000 + 50000);
      expect(soldeClient(factures, 'C2'), 900000);
    });

    test('ne laisse pas un trop-perçu effacer une créance', () {
      // F4 est excédentaire de 10 000 : cela ne doit pas réduire le dû sur
      // F1/F2.
      expect(soldeClient(factures, 'C1'), 110000);
      expect(avoirClient(factures, 'C1'), 10000);
    });

    test('vaut zéro pour un client inconnu', () {
      expect(soldeClient(factures, 'INEXISTANT'), 0);
      expect(avoirClient(factures, 'INEXISTANT'), 0);
    });
  });

  // ─── Dépenses ──────────────────────────────────────────────────────────────

  group('resteAPayer / tropVerse', () {
    test('retranche les règlements du montant dû', () {
      expect(
          resteAPayer(depense(
              montant: 500000, reglements: [reglement(montant: 200000)])),
          300000);
    });

    test('ne descend jamais sous zéro et expose le trop-versé', () {
      final d =
          depense(montant: 500000, reglements: [reglement(montant: 600000)]);
      expect(resteAPayer(d), 0);
      expect(tropVerse(d), 100000);
    });

    test('vaut le montant entier sans règlement', () {
      expect(resteAPayer(depense(montant: 500000)), 500000);
      expect(montantRegle(depense(montant: 500000)), 0);
    });
  });

  group('statutDepense', () {
    test('distingue non réglée, partielle et réglée', () {
      expect(depense(montant: 500000).statut, 'non réglée');
      expect(
          depense(montant: 500000, reglements: [reglement(montant: 1)]).statut,
          'partielle');
      expect(
          depense(montant: 500000, reglements: [reglement(montant: 500000)])
              .statut,
          'réglée');
    });

    test('considère réglée une dépense sur-payée', () {
      expect(
          depense(montant: 500000, reglements: [reglement(montant: 700000)])
              .statut,
          'réglée');
    });
  });

  group('depenseEnRetard', () {
    final maintenant = DateTime.parse('2026-05-01T00:00:00.000Z');

    test('signale une dépense due depuis plus de 30 jours', () {
      expect(depenseEnRetard(depense(date: '2026-03-01T00:00:00.000Z'), maintenant),
          isTrue);
    });

    test('ne signale pas une dépense récente', () {
      expect(depenseEnRetard(depense(date: '2026-04-25T00:00:00.000Z'), maintenant),
          isFalse);
    });

    test('ne signale jamais une dépense réglée, si ancienne soit-elle', () {
      final d = depense(
          date: '2024-01-01T00:00:00.000Z',
          montant: 500000,
          reglements: [reglement(montant: 500000)]);
      expect(depenseEnRetard(d, maintenant), isFalse);
    });
  });

  group('nature comptable', () {
    test('la nature se déduit de la catégorie, elle ne se saisit pas', () {
      expect(depense(categorie: 'Achat de marchandise').nature, 'marchandise');
      expect(depense(categorie: 'Véhicule').nature, 'investissement');
      expect(depense(categorie: 'Loyer').nature, 'exploitation');
    });

    test('une catégorie inconnue est traitée comme une charge d\'exploitation',
        () {
      // Le choix prudent : elle pèse sur le résultat plutôt que de l'embellir.
      expect(depense(categorie: "Catégorie d'une vieille sauvegarde").nature,
          'exploitation');
    });
  });

  // ─── Coût des marchandises vendues ─────────────────────────────────────────

  group('coutAchatVente', () {
    final catalogue = {
      'A1': article(id: 'A1', prixAchat: 100000),
      'A2': article(id: 'A2', prixAchat: 40000),
    };

    test('valorise chaque ligne au prix d\'achat actuel', () {
      final v = vente(lignes: [
        ligne(articleId: 'A1', qte: 3),
        ligne(articleId: 'A2', qte: 2),
      ]);
      expect(coutAchatVente(v, catalogue), 3 * 100000 + 2 * 40000);
    });

    test('compte pour zéro une ligne dont l\'article a disparu du catalogue',
        () {
      final v = vente(lignes: [ligne(articleId: 'SUPPRIME', qte: 5)]);
      expect(coutAchatVente(v, catalogue), 0);
    });

    test('vaut zéro pour une vente sans lignes', () {
      expect(coutAchatVente(vente(lignes: []), catalogue), 0);
    });
  });

  group('stockStatut', () {
    test('distingue rupture, faible et en stock', () {
      expect(stockStatut(article(stock: 0, stockMin: 20)), 'rupture');
      expect(stockStatut(article(stock: 5, stockMin: 20)), 'faible');
      expect(stockStatut(article(stock: 50, stockMin: 20)), 'en-stock');
    });

    test('un stock exactement au seuil n\'est pas encore faible', () {
      expect(stockStatut(article(stock: 20, stockMin: 20)), 'en-stock');
    });

    test('un stock négatif est une rupture, pas un stock faible', () {
      // Écart volontaire avec l'application web, qui ne teste que `stock === 0`
      // et classerait un stock de −5 en « faible ». Il n'y a rien à vendre.
      expect(stockStatut(article(stock: -5, stockMin: 20)), 'rupture');
    });
  });

  // ─── Bilan ─────────────────────────────────────────────────────────────────

  group('calculerBilan', () {
    final articles = [article(id: 'A1', prixAchat: 100000)];
    final mars = Periode.mois(2026, 3);

    Bilan bilan({
      List<Vente> ventes = const [],
      List<Facture> factures = const [],
      List<Depense> depenses = const [],
      Periode? periode,
    }) =>
        calculerBilan(
          ventes: ventes,
          factures: factures,
          depenses: depenses,
          articles: articles,
          periode: periode,
        );

    test('sépare résultat et trésorerie : bénéficiaire mais sans caisse', () {
      // Une vente de mars livrée mais jamais payée : la marge existe, la caisse
      // est vide. Additionner les deux lectures serait précisément l'erreur.
      final b = bilan(
        ventes: [
          vente(
              date: '2026-03-15T10:00:00.000Z',
              totalNet: 300000,
              lignes: [ligne(articleId: 'A1', qte: 1)])
        ],
        factures: [
          facture(dateEmission: '2026-03-15T10:00:00.000Z', montantTTC: 300000)
        ],
        periode: mars,
      );
      expect(b.chiffreAffaires, 300000);
      expect(b.coutMarchandises, 100000);
      expect(b.margeBrute, 200000);
      expect(b.resultatExploitation, 200000);
      expect(b.encaissements, 0);
      expect(b.fluxTresorerie, 0);
      expect(b.creancesClients, 300000);
    });

    test('rattache un versement au mois où l\'argent est entré', () {
      final factures = [
        facture(
            dateEmission: '2025-12-20T10:00:00.000Z',
            montantTTC: 300000,
            paiements: [
              paiement(date: '2026-03-05T10:00:00.000Z', montant: 300000)
            ])
      ];
      expect(bilan(factures: factures, periode: mars).encaissements, 300000);
      expect(
          bilan(factures: factures, periode: Periode.mois(2025, 12))
              .encaissements,
          0);
    });

    test('exclut du résultat les achats de marchandise et les investissements',
        () {
      final b = bilan(
        depenses: [
          depense(
              id: 'D1',
              date: '2026-03-02T00:00:00.000Z',
              categorie: 'Loyer',
              montant: 500000),
          depense(
              id: 'D2',
              date: '2026-03-03T00:00:00.000Z',
              categorie: 'Achat de marchandise',
              montant: 4000000),
          depense(
              id: 'D3',
              date: '2026-03-04T00:00:00.000Z',
              categorie: 'Véhicule',
              montant: 9000000),
        ],
        periode: mars,
      );
      expect(b.chargesExploitation, 500000);
      expect(b.achatsMarchandises, 4000000);
      expect(b.investissements, 9000000);
      // Seul le loyer pèse sur le résultat.
      expect(b.resultatExploitation, -500000);
      expect(b.nbDepenses, 3);
    });

    test('arrête les créances à la fin de la période, versements postérieurs exclus',
        () {
      // Un versement d'avril ne doit pas faire disparaître rétroactivement la
      // créance arrêtée au 31 mars.
      final factures = [
        facture(
            dateEmission: '2026-03-10T10:00:00.000Z',
            montantTTC: 300000,
            paiements: [
              paiement(date: '2026-04-05T10:00:00.000Z', montant: 300000)
            ])
      ];
      expect(bilan(factures: factures, periode: mars).creancesClients, 300000);
      expect(
          bilan(factures: factures, periode: Periode.mois(2026, 4))
              .creancesClients,
          0);
    });

    test('ignore les pièces émises après la fin de la période', () {
      final b = bilan(
        factures: [
          facture(dateEmission: '2026-04-10T10:00:00.000Z', montantTTC: 300000)
        ],
        periode: mars,
      );
      expect(b.creancesClients, 0);
    });

    test('calcule les dettes fournisseurs selon la même règle d\'arrêté', () {
      final depenses = [
        depense(date: '2026-03-10T00:00:00.000Z', montant: 500000, reglements: [
          reglement(date: '2026-04-02T00:00:00.000Z', montant: 500000)
        ])
      ];
      expect(bilan(depenses: depenses, periode: mars).dettesFournisseurs,
          500000);
      expect(bilan(depenses: depenses, periode: mars).decaissements, 0);
      expect(
          bilan(depenses: depenses, periode: Periode.mois(2026, 4))
              .decaissements,
          500000);
    });

    test('expose la position nette comme créances moins dettes', () {
      final b = bilan(
        factures: [
          facture(dateEmission: '2026-03-01T10:00:00.000Z', montantTTC: 300000)
        ],
        depenses: [depense(date: '2026-03-01T00:00:00.000Z', montant: 500000)],
        periode: mars,
      );
      expect(b.positionNette, 300000 - 500000);
    });

    test('laisse le taux de marge à null sans vente, plutôt que de diviser par zéro',
        () {
      final b = bilan(periode: mars);
      expect(b.tauxMarge, isNull);
      expect(b.chiffreAffaires, 0);
    });

    test('calcule le taux de marge en pourcentage du chiffre d\'affaires', () {
      final b = bilan(
        ventes: [
          vente(
              date: '2026-03-15T10:00:00.000Z',
              totalNet: 400000,
              lignes: [ligne(articleId: 'A1', qte: 1)])
        ],
        periode: mars,
      );
      expect(b.tauxMarge, closeTo(75, 1e-9));
    });

    test('ventile par catégorie, engagé et décaissé séparés, du plus gros au plus petit',
        () {
      final b = bilan(
        depenses: [
          depense(
              id: 'D1',
              date: '2026-03-02T00:00:00.000Z',
              categorie: 'Loyer',
              montant: 500000,
              reglements: [
                reglement(date: '2026-03-03T00:00:00.000Z', montant: 500000)
              ]),
          depense(
              id: 'D2',
              date: '2026-03-05T00:00:00.000Z',
              categorie: 'Carburant',
              montant: 900000),
        ],
        periode: mars,
      );
      expect(b.parCategorie.map((l) => l.categorie).toList(),
          ['Carburant', 'Loyer']);
      expect(b.parCategorie[0].engage, 900000);
      expect(b.parCategorie[0].decaisse, 0);
      expect(b.parCategorie[0].nombre, 1);
      expect(b.parCategorie[1].engage, 500000);
      expect(b.parCategorie[1].decaisse, 500000);
    });

    test('fait apparaître une catégorie décaissée sur la période même si la dépense est antérieure',
        () {
      final b = bilan(
        depenses: [
          depense(
              date: '2026-01-10T00:00:00.000Z',
              categorie: 'Loyer',
              montant: 500000,
              reglements: [
                reglement(date: '2026-03-03T00:00:00.000Z', montant: 500000)
              ])
        ],
        periode: mars,
      );
      expect(b.parCategorie.length, 1);
      expect(b.parCategorie[0].categorie, 'Loyer');
      expect(b.parCategorie[0].engage, 0);
      expect(b.parCategorie[0].decaisse, 500000);
      expect(b.parCategorie[0].nombre, 0);
    });

    test('sans période, prend tout l\'historique', () {
      final ventes = [
        vente(id: 'V1', date: '2024-01-01T10:00:00.000Z', totalNet: 100000, lignes: []),
        vente(id: 'V2', date: '2026-03-01T10:00:00.000Z', totalNet: 200000, lignes: []),
      ];
      expect(bilan(ventes: ventes).chiffreAffaires, 300000);
      expect(bilan(ventes: ventes).nbVentes, 2);
    });
  });

  // ─── Bornes de période ─────────────────────────────────────────────────────

  group('Periode.mois', () {
    test('borne un mois de 31 jours', () {
      final p = Periode.mois(2026, 3);
      expect(p.debut, '2026-03-01');
      expect(p.fin, '2026-03-31');
    });

    test('borne février d\'une année bissextile', () {
      expect(Periode.mois(2024, 2).fin, '2024-02-29');
    });

    test('borne février d\'une année non bissextile', () {
      expect(Periode.mois(2026, 2).fin, '2026-02-28');
    });

    test('complète les mois à un chiffre', () {
      final p = Periode.mois(2026, 1);
      expect(p.debut, '2026-01-01');
      expect(p.fin, '2026-01-31');
    });
  });

  group('Periode.annee', () {
    test('couvre l\'année civile entière', () {
      final p = Periode.annee(2026);
      expect(p.debut, '2026-01-01');
      expect(p.fin, '2026-12-31');
    });
  });

  group('Periode.derniersJours', () {
    test('inclut aujourd\'hui dans le compte', () {
      // 7 jours au 10 mars : du 4 au 10, bornes incluses.
      final p = Periode.derniersJours(7, DateTime(2026, 3, 10, 12));
      expect(p.debut, '2026-03-04');
      expect(p.fin, '2026-03-10');
    });

    test('ramène un jour unique à la date du jour', () {
      final p = Periode.derniersJours(1, DateTime(2026, 3, 10, 12));
      expect(p.debut, '2026-03-10');
      expect(p.fin, '2026-03-10');
    });

    test('traverse correctement un changement de mois', () {
      final p = Periode.derniersJours(5, DateTime(2026, 3, 2, 12));
      expect(p.debut, '2026-02-26');
      expect(p.fin, '2026-03-02');
    });
  });

  group('PlageDates', () {
    test('convertit un intervalle de dates en bornes ISO', () {
      final p =
          PlageDates(debut: DateTime(2026, 3, 4), fin: DateTime(2026, 3, 10));
      expect(p.periode.debut, '2026-03-04');
      expect(p.periode.fin, '2026-03-10');
    });

    test('cadre le mois civil du 1er au dernier jour', () {
      final p = PlageDates.mois(DateTime(2026, 2, 17));
      expect(p.periode.debut, '2026-02-01');
      expect(p.periode.fin, '2026-02-28');
    });

    test('une vente de fin de soirée reste dans son propre mois', () {
      // `toIso8601String()` bascule en UTC pour une date construite en UTC : une
      // vente encaissée à 23 h le 31 mars tomberait alors en avril, et
      // disparaîtrait de l'arrêté de mars.
      final p = PlageDates.mois(DateTime(2026, 3, 31, 23, 30));
      expect(p.periode.fin, '2026-03-31');
    });
  });
}
