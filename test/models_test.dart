import 'package:flutter_test/flutter_test.dart';
import 'package:eas_sarlu/core/models/models.dart';

void main() {
  group('Modèles - JSON aller-retour', () {
    test('Article', () {
      final json = {
        'id': 'art1',
        'ref': 'TC-001',
        'nom': 'Tube carré 40x40',
        'categorie': 'Tube carré',
        'description': 'Tube en acier',
        'unite': 'Barre',
        'prixAchat': 120000,
        'prixVente': 150000,
        'stock': 50,
        'stockMin': 10,
        'fournisseur': 'Fournisseur A',
        'photo': '',
        'longueur': 6.0,
        'epaisseur': 2.5,
        'provenance': 'Turquie',
        '_rev': 1,
        '_updatedAt': '2026-07-29T10:00:00Z',
        '_updatedBy': 'admin',
      };
      final article = Article.fromJson(json);
      expect(article.id, 'art1');
      expect(article.prixAchat, 120000);
      expect(article.longueur, 6.0);
      expect(article.rev, 1);
      final output = article.toJson();
      expect(output['id'], 'art1');
      expect(output['_rev'], 1);
    });

    test('Vente avec lignes', () {
      final json = {
        'id': 'v1',
        'numero': 'VTE-2026-0001',
        'clientId': 'c1',
        'vendeur': 'Mamadou',
        'date': '2026-07-29T14:00:00Z',
        'lignes': [
          {
            'articleId': 'art1',
            'articleRef': 'TC-001',
            'articleNom': 'Tube carré 40x40',
            'unite': 'Barre',
            'qte': 2,
            'prixUnitaire': 150000,
            'remise': 0,
            'total': 300000,
          }
        ],
        'remiseGlobale': 5000,
        'totalHT': 295000,
        'totalNet': 295000,
        'note': 'Client pressé',
        '_rev': 2,
      };
      final vente = Vente.fromJson(json);
      expect(vente.lignes.length, 1);
      expect(vente.lignes.first.articleNom, 'Tube carré 40x40');
      expect(vente.totalNet, 295000);
      final output = vente.toJson();
      expect(output['lignes'], isA<List>());
    });

    test('Facture avec paiements', () {
      final json = {
        'id': 'f1',
        'numero': 'FAC-2026-0001',
        'venteId': 'v1',
        'clientId': 'c1',
        'dateEmission': '2026-07-29T14:00:00Z',
        'dateEcheance': '2026-08-29',
        'montantHT': 250000,
        'tauxTVA': 0.18,
        'montantTVA': 45000,
        'montantTTC': 295000,
        'remise': 0,
        'note': '',
        'statut': 'non payée',
        'paiements': [
          {
            'id': 'p1',
            'date': '2026-07-29T15:00:00Z',
            'montant': 100000,
            'mode': 'espèces',
            'note': '',
            'utilisateur': 'admin',
          }
        ],
        'creePar': 'admin',
      };
      final facture = Facture.fromJson(json);
      expect(facture.paiements.length, 1);
      expect(montantPaye(facture), 100000);
      expect(resteDu(facture), 195000);
      expect(statutFacture(facture), 'non payée');
      // Ajoute un second paiement pour solder
      final nouvelle = Facture(
        id: facture.id,
        venteId: facture.venteId,
        clientId: facture.clientId,
        dateEmission: facture.dateEmission,
        montantTTC: facture.montantTTC,
        paiements: [
          ...facture.paiements,
          Paiement(
            id: 'p2',
            date: '2026-07-30',
            montant: 195000,
            mode: 'mobile money',
          ),
        ],
      );
      expect(montantPaye(nouvelle), 295000);
      expect(statutFacture(nouvelle), 'payée');
    });

    test('Dépense avec règlements partiels', () {
      final json = {
        'id': 'd1',
        'numero': 'DEP-2026-0001',
        'date': '2026-07-29',
        'categorie': 'Transport',
        'nature': 'exploitation',
        'libelle': 'Livraison',
        'beneficiaire': 'Transporteur',
        'montant': 500000,
        'reference': '',
        'note': '',
        'reglements': [
          {
            'id': 'r1',
            'date': '2026-07-29',
            'montant': 200000,
            'mode': 'virement',
            'note': '',
            'utilisateur': 'admin',
          }
        ],
        'statut': 'partielle',
        'creePar': 'admin',
      };
      final depense = Depense.fromJson(json);
      expect(montantRegle(depense), 200000);
      expect(statutDepense(depense), 'partielle');
      // Règlement complet
      final reglee = Depense(
        id: depense.id,
        date: depense.date,
        montant: depense.montant,
        reglements: [
          ...depense.reglements,
          Reglement(
              id: 'r2', date: '2026-07-30', montant: 300000, mode: 'espèces'),
        ],
      );
      expect(statutDepense(reglee), 'réglée');
    });

    test('valeurStock', () {
      final articles = [
        Article(
            id: 'a1',
            nom: 'A',
            unite: 'Barre',
            prixAchat: 100,
            prixVente: 150,
            stock: 10),
        Article(
            id: 'a2',
            nom: 'B',
            unite: 'Plaque',
            prixAchat: 500,
            prixVente: 700,
            stock: 3),
      ];
      expect(valeurStockAchat(articles), 10 * 100 + 3 * 500); // 1000 + 1500 = 2500
    });

    test('margeVente', () {
      final articlesMap = {
        'a1': Article(
            id: 'a1', nom: 'A', unite: 'Barre', prixAchat: 100, prixVente: 150),
        'a2': Article(
            id: 'a2',
            nom: 'B',
            unite: 'Plaque',
            prixAchat: 500,
            prixVente: 700),
      };
      final vente = Vente(
        id: 'v1',
        clientId: 'c1',
        date: '2026-07-29',
        totalNet: 1500,
        lignes: [
          LigneVente(articleId: 'a1', qte: 2, prixUnitaire: 150, total: 300),
          LigneVente(articleId: 'a2', qte: 1, prixUnitaire: 700, total: 700),
        ],
      );
      final marge = margeVente(vente, articlesMap);
      // coût: 2*100 + 1*500 = 700, marge = 1500 - 700 = 800
      expect(marge, 800);
    });

    test('Champs absents tolérés', () {
      final jsonVide = <String, dynamic>{};
      final article = Article.fromJson(jsonVide);
      expect(article.id, '');
      expect(article.prixAchat, 0);
      expect(article.longueur, null);
    });
  });
}
