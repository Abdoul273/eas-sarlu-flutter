// Vérifie la couche « outils » de l'assistant : c'est elle qui décide des
// chiffres que le modèle recevra, et donc de ceux qu'il annoncera au gérant.
//
// Trois propriétés comptent plus que le reste :
//   — un vendeur ne doit jamais pouvoir atteindre une marge, même en nommant
//     l'outil lui-même ;
//   — le protocole d'appel doit résister à ce que les modèles écrivent
//     réellement (blocs ```, guillemets manquants, JSON invalide) ;
//   — les bornes de période doivent être justes : une erreur de mois fausse
//     silencieusement tout un bilan.
import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/features/assistant/ai_outils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

DonneesMagasin magasin({bool voitPrixAchat = true}) {
  final articles = [
    Article(
        id: 'a1',
        ref: 'TC-40',
        nom: 'Tube carré 40x40',
        categorie: 'Tube carré',
        unite: 'Barre',
        prixAchat: 60000,
        prixVente: 85000,
        stock: 12,
        stockMin: 20),
    Article(
        id: 'a2',
        ref: 'TG-2',
        nom: 'Tôle galvanisée 2mm',
        categorie: 'Tôle galvanisée',
        unite: 'Feuille',
        prixAchat: 50000,
        prixVente: 75000,
        stock: 0,
        stockMin: 10),
    Article(
        id: 'a3',
        ref: 'DORM-1',
        nom: 'Cornière oubliée',
        categorie: 'Cornière',
        unite: 'Barre',
        prixAchat: 30000,
        prixVente: 45000,
        stock: 40,
        stockMin: 5),
  ];
  final clients = [
    Client(id: 'c1', nom: 'SOGEC BTP', type: 'professionnel', telephone: '620'),
    Client(id: 'c2', nom: 'Mamadou Barry', type: 'particulier'),
  ];
  final ventes = [
    Vente(
        id: 'v1',
        numero: 'VTE-2026-0001',
        clientId: 'c1',
        date: '2026-07-10',
        totalHT: 850000,
        totalNet: 850000,
        lignes: [
          LigneVente(
              articleId: 'a1',
              articleRef: 'TC-40',
              articleNom: 'Tube carré 40x40',
              unite: 'Barre',
              qte: 10,
              prixUnitaire: 85000,
              total: 850000),
        ]),
    Vente(
        id: 'v2',
        numero: 'VTE-2026-0002',
        clientId: 'c2',
        date: '2026-07-20',
        totalHT: 375000,
        totalNet: 375000,
        lignes: [
          LigneVente(
              articleId: 'a2',
              articleRef: 'TG-2',
              articleNom: 'Tôle galvanisée 2mm',
              unite: 'Feuille',
              qte: 5,
              prixUnitaire: 75000,
              total: 375000),
        ]),
  ];
  final factures = [
    Facture(
        id: 'f1',
        numero: 'FAC-2026-0001',
        venteId: 'v1',
        clientId: 'c1',
        dateEmission: '2026-07-10',
        dateEcheance: '2026-07-20',
        montantTTC: 850000,
        paiements: [
          Paiement(id: 'p1', date: '2026-07-12', montant: 350000),
        ]),
  ];
  final depenses = [
    Depense(
        id: 'd1',
        numero: 'DEP-2026-0001',
        date: '2026-07-05',
        categorie: 'Loyer',
        libelle: 'Loyer du dépôt',
        beneficiaire: 'Propriétaire',
        montant: 2000000,
        reglements: [Reglement(id: 'r1', date: '2026-07-05', montant: 2000000)]),
    Depense(
        id: 'd2',
        numero: 'DEP-2026-0002',
        date: '2026-07-08',
        categorie: 'Achat de marchandise',
        libelle: 'Tubes',
        beneficiaire: 'Import Turquie',
        montant: 5000000),
  ];

  final fournisseurs = [
    Fournisseur(
        id: 'fo1',
        nom: 'Import Turquie',
        telephone: '622000001',
        quartier: 'Matoto',
        creeLe: '2026-01-10'),
    Fournisseur(
        id: 'fo2',
        nom: 'Aciérie de Conakry',
        telephone: '622000002',
        quartier: 'Kagbelen',
        creeLe: '2026-02-01'),
  ];
  final mouvements = [
    MouvementStock(
        id: 'mv1',
        articleId: 'a1',
        type: 'entrée',
        quantite: 100,
        date: '2026-07-01T09:00:00.000Z',
        fournisseurId: 'fo1',
        fournisseurNom: 'Import Turquie'),
    MouvementStock(
        id: 'mv2',
        articleId: 'a2',
        type: 'entrée',
        quantite: 40,
        date: '2026-07-15T09:00:00.000Z',
        fournisseurId: 'fo1',
        fournisseurNom: 'Import Turquie'),
    // Une entrée ancienne, sans fournisseur : elle ne doit être attribuée
    // à personne plutôt qu'au premier venu.
    MouvementStock(
        id: 'mv3',
        articleId: 'a3',
        type: 'entrée',
        quantite: 500,
        date: '2026-06-01T09:00:00.000Z'),
  ];

  return DonneesMagasin(
    articles: articles,
    ventes: ventes,
    clients: clients,
    factures: factures,
    depenses: depenses,
    mouvements: mouvements,
    fournisseurs: fournisseurs,
    voitPrixAchat: voitPrixAchat,
  );
}

/// Les montants sortent avec l'espace insécable fine d'`Intl` ; les comparer à
/// une chaîne tapée au clavier échouerait sur ce seul caractère invisible.
String sansEspacesFines(String s) => s.replaceAll(RegExp(r'[\s\u00A0\u202F]+'), ' ');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Protocole d\'appel', () {
    test('repère un appel simple', () {
      final r = extraireAppels(
          '<outil nom="bilan_financier">{"periode":"mois"}</outil>');
      expect(r.appels, hasLength(1));
      expect(r.appels.first.nom, 'bilan_financier');
      expect(r.appels.first.args['periode'], 'mois');
      expect(r.reste, isEmpty);
    });

    test('tolère les enrobages que produisent réellement les modèles', () {
      // Bloc ``` autour du JSON, guillemets absents autour du nom : deux
      // habitudes fréquentes qui, non tolérées, feraient répondre
      // « je n'ai pas cette information ».
      final r = extraireAppels('''Je consulte le bilan.
<outil nom=bilan_financier>```json
{"periode":"mois_dernier"}
```</outil>''');
      expect(r.appels, hasLength(1));
      expect(r.appels.first.nom, 'bilan_financier');
      expect(r.appels.first.args['periode'], 'mois_dernier');
      expect(r.reste, 'Je consulte le bilan.');
    });

    test('un JSON illisible n\'annule pas l\'appel', () {
      // L'outil tourne alors avec ses valeurs par défaut : mieux vaut une
      // réponse sur la période par défaut qu'aucune réponse.
      final r = extraireAppels('<outil nom="lister_articles">{oups}</outil>');
      expect(r.appels, hasLength(1));
      expect(r.appels.first.args, isEmpty);
    });

    test('repère plusieurs appels d\'un coup', () {
      final r = extraireAppels(
          '<outil nom="lister_clients">{}</outil>\n'
          '<outil nom="creances_et_dettes">{}</outil>');
      expect(r.appels.map((a) => a.nom),
          ['lister_clients', 'creances_et_dettes']);
    });
  });

  group('Périodes', () {
    final reference = DateTime(2026, 7, 15);

    test('« mois » borne le mois civil en cours', () {
      final r = resoudrePeriode({'periode': 'mois'}, reference);
      expect(r.periode!.debut, '2026-07-01');
      expect(r.periode!.fin, '2026-07-31');
    });

    test('« mois_dernier » ne déborde pas sur le mois courant', () {
      final r = resoudrePeriode({'periode': 'mois_dernier'}, reference);
      expect(r.periode!.debut, '2026-06-01');
      expect(r.periode!.fin, '2026-06-30');
    });

    test('« 30j » compte bornes incluses', () {
      final r = resoudrePeriode({'periode': '30j'}, reference);
      expect(r.periode!.fin, '2026-07-15');
      expect(r.periode!.debut, '2026-06-16');
    });

    test('« annee » couvre l\'année civile', () {
      final r = resoudrePeriode({'periode': 'annee'}, reference);
      expect(r.periode!.debut, '2026-01-01');
      expect(r.periode!.fin, '2026-12-31');
    });

    test('une période inconnue vaut « tout l\'historique »', () {
      // Rendre une période vide plutôt qu'un intervalle inventé : un bilan sur
      // de mauvaises bornes est pire qu'un bilan sur tout.
      expect(resoudrePeriode({'periode': 'la semaine du chef'}, reference).periode,
          isNull);
      expect(resoudrePeriode({}, reference).periode, isNull);
    });

    test('des bornes explicites priment sur le mot-clé', () {
      final r = resoudrePeriode(
          {'periode': 'mois', 'debut': '2026-03-01', 'fin': '2026-03-31'},
          reference);
      expect(r.periode!.debut, '2026-03-01');
      expect(r.periode!.fin, '2026-03-31');
    });
  });

  group('Cloisonnement des prix d\'achat', () {
    test('les outils confidentiels ne sont pas documentés au vendeur', () {
      final notice = documenterOutils(false);
      expect(notice, isNot(contains('bilan_financier')));
      expect(notice, isNot(contains('rentabilite_articles')));
      // Ceux qui ne révèlent aucune marge restent proposés.
      expect(notice, contains('fiche_client'));
      expect(notice, contains('lister_clients'));
    });

    test('un vendeur qui nomme l\'outil lui-même est refusé', () {
      // Ne pas documenter ne suffit pas : le modèle peut inventer le nom, ou
      // l'utilisateur le lui souffler. La barrière est aussi à l'exécution.
      final r = executerOutil(
          const AppelOutil('bilan_financier', {}), magasin(voitPrixAchat: false));
      expect(r, contains('Accès refusé'));
      expect(r, isNot(contains('RÉSULTAT')));
    });

    test('le gérant, lui, obtient le bilan', () {
      final r = executerOutil(const AppelOutil('bilan_financier', {}), magasin());
      expect(r, contains('RÉSULTAT D\'EXPLOITATION'));
    });

    test('la fiche article masque le prix d\'achat au vendeur', () {
      final r = executerOutil(const AppelOutil('fiche_article', {'terme': 'TC-40'}),
          magasin(voitPrixAchat: false));
      // fiche_article est confidentiel : il ne doit rien rendre du tout.
      expect(r, contains('Accès refusé'));
    });

    test('la fiche client masque la marge au vendeur mais garde le solde', () {
      final r = executerOutil(
          const AppelOutil('fiche_client', {'terme': 'SOGEC'}),
          magasin(voitPrixAchat: false));
      expect(r, contains('SOGEC BTP'));
      expect(r, contains('SOLDE IMPAYÉ'));
      expect(r, isNot(contains('marge dégagée')));
    });
  });

  group('Contenu des outils', () {
    test('le bilan sépare résultat et trésorerie', () {
      final r = executerOutil(
          const AppelOutil('bilan_financier', {'periode': 'tout'}), magasin());
      expect(r, contains('Résultat'));
      expect(r, contains('Trésorerie'));
      // L'achat de marchandise sort de la caisse mais n'est pas une charge :
      // c'est la confusion la plus coûteuse pour un commerçant.
      expect(r, contains('Sorties de caisse hors résultat'));
      expect(r, contains('n\'additionne jamais le résultat et le flux'));
    });

    test('le réapprovisionnement voit l\'article en rupture qui se vendait', () {
      final r = executerOutil(const AppelOutil('reapprovisionnement', {}), magasin());
      expect(r, contains('Tôle galvanisée 2mm'));
      expect(r, contains('COMMANDER'));
    });

    test('un article sous le seuil est proposé même sans vente récente', () {
      // Ne retenir que le rythme conseillerait « commander 0 » sur un article
      // en rupture depuis des mois — précisément celui dont l'absence explique
      // qu'il ne se vende plus.
      final r = executerOutil(const AppelOutil('reapprovisionnement', {}), magasin());
      expect(r, contains('Tube carré 40x40'));
    });

    test('les articles dormants sont ceux qui immobilisent sans tourner', () {
      final r = executerOutil(
          const AppelOutil('rentabilite_articles', {'tri': 'dormant'}), magasin());
      expect(r, contains('Cornière oubliée'));
      expect(r, isNot(contains('Tube carré 40x40')));
    });

    test('la fiche client donne le reste dû réel', () {
      final r = executerOutil(
          const AppelOutil('fiche_client', {'terme': 'SOGEC'}), magasin());
      // 850 000 facturés, 350 000 versés → 500 000 dus.
      expect(sansEspacesFines(r), contains('RESTE 500 000 GNF'));
    });

    test('chercher_ventes filtre par client et totalise TOUT le filtre', () {
      final r = executerOutil(
          const AppelOutil('chercher_ventes', {'client': 'Barry'}), magasin());
      expect(r, contains('1 vente·s'));
      expect(r, contains('Mamadou Barry'));
      expect(r, isNot(contains('SOGEC')));
    });

    test('chercher_depenses distingue engagé et réglé', () {
      final r = executerOutil(const AppelOutil('chercher_depenses', {}), magasin());
      expect(r, contains('RESTE À PAYER'));
      // 7 000 000 engagés, 2 000 000 réglés → 5 000 000 restants.
      expect(sansEspacesFines(r), contains('RESTE À PAYER 5 M GNF'));
    });

    test('creances_et_dettes classe les impayés par ancienneté', () {
      final r = executerOutil(const AppelOutil('creances_et_dettes', {}), magasin());
      expect(r, contains('Les clients nous doivent'));
      expect(r, contains('Nous devons aux fournisseurs'));
      expect(r, contains('Position nette'));
    });
  });

  group('Robustesse', () {
    test('un outil inconnu explique quoi appeler à la place', () {
      final r = executerOutil(const AppelOutil('inventer_chiffres', {}), magasin());
      expect(r, contains('inconnu'));
      expect(r, contains('bilan_financier'));
    });

    test('un terme introuvable oriente vers un autre outil', () {
      final r = executerOutil(
          const AppelOutil('fiche_article', {'terme': 'zzz'}), magasin());
      expect(r, contains('Aucun article'));
      expect(r, contains('lister_articles'));
    });

    test('un terme trop large demande de préciser plutôt que de tout vider', () {
      final beaucoup = List.generate(
          9,
          (i) => Article(
              id: 'x$i', ref: 'R$i', nom: 'Tube $i', unite: 'Barre', stock: 1));
      final d = DonneesMagasin(
        articles: beaucoup,
        ventes: const [],
        clients: const [],
        factures: const [],
        depenses: const [],
        mouvements: const [],
        voitPrixAchat: true,
      );
      final r = executerOutil(const AppelOutil('fiche_article', {'terme': 'tube'}), d);
      expect(r, contains('Précise'));
    });

    test('un magasin vide ne fait échouer aucun outil', () {
      const vide = DonneesMagasin(
        articles: [],
        ventes: [],
        clients: [],
        factures: [],
        depenses: [],
        mouvements: [],
        voitPrixAchat: true,
      );
      for (final outil in kOutils) {
        final r = executerOutil(AppelOutil(outil.nom, const {}), vide);
        expect(r, isNotEmpty, reason: '${outil.nom} doit rendre quelque chose');
        expect(r, isNot(contains('a échoué')),
            reason: '${outil.nom} ne doit pas lever d\'exception');
      }
    });
  });

  // ─── Trésorerie ─────────────────────────────────────────────────────────────
  // L'assistant doit pouvoir répondre à « combien j'ai en caisse ? » — et
  // surtout ne pas confondre l'argent reçu avec l'argent promis.

  group('tresorerie', () {
    test("compte l'argent reçu moins l'argent sorti", () {
      final r = sansEspacesFines(
          executerOutil(const AppelOutil('tresorerie', {}), magasin()));

      // Encaissé 350 000, décaissé 2 000 000 → solde négatif de 1 650 000.
      expect(r, contains('TRÉSORERIE'));
      expect(r, contains('350 000'));
      expect(r, contains('2 M'));
      // Le solde de tête est donné au franc près : « 2 M » couvrirait aussi
      // bien 1 650 000 que 2 400 000, et c'est sur ce chiffre qu'on décide.
      expect(r, contains('-1 650 000'));
    });

    test('sépare ce qui est en caisse de ce qui est encore dehors', () {
      final r = sansEspacesFines(
          executerOutil(const AppelOutil('tresorerie', {}), magasin()));

      // Reste à encaisser : 850 000 − 350 000 = 500 000.
      expect(r, contains('Reste à encaisser'));
      expect(r, contains('500 000'));
      // Reste à payer : la dépense de 5 000 000 non réglée.
      expect(r, contains('Reste à payer'));
      expect(r, contains('5 M'));
    });

    test('met en garde contre la lecture « solde du coffre »', () {
      // Ni le fonds de caisse d'origine ni les prélèvements du gérant ne sont
      // enregistrés : le modèle doit le savoir, sans quoi il présentera ce
      // cumul comme un solde vérifié.
      final r = executerOutil(const AppelOutil('tresorerie', {}), magasin());
      expect(r, contains('cumul de mouvements'));
    });

    test("reste accessible à un vendeur : ce n'est pas une marge", () {
      final r = executerOutil(
          const AppelOutil('tresorerie', {}), magasin(voitPrixAchat: false));
      expect(r, contains('TRÉSORERIE'));
      expect(documenterOutils(false), contains('tresorerie'));
    });
  });

  group('fournisseurs', () {
    test('classe les fournisseurs par ce qu\'on a reçu de chacun', () {
      final r = sansEspacesFines(
          executerOutil(const AppelOutil('fournisseurs', {}), magasin()));

      expect(r, contains('FOURNISSEURS — 2 au total'));
      // 100 + 40 = 140 unités reçues chez Import Turquie, sur 2 entrées.
      expect(r, contains('140 unités reçues sur 2 entrées'));
      expect(r, contains('Import Turquie'));
      expect(r, contains('Aciérie de Conakry'));
    });

    test('n\'attribue à personne une entrée sans fournisseur', () {
      // Les 500 unités de l'entrée « mv3 » ne portent aucun identifiant : les
      // rattacher au premier fournisseur venu inventerait un historique.
      final r = sansEspacesFines(
          executerOutil(const AppelOutil('fournisseurs', {}), magasin()));
      expect(r, isNot(contains('640')));
      expect(r, contains('aucune entrée enregistrée'),
          reason: 'le fournisseur sans achat doit être dit tel quel');
    });

    test('rend la fiche détaillée quand on nomme un fournisseur', () {
      final r = sansEspacesFines(executerOutil(
          const AppelOutil('fournisseurs', {'terme': 'turquie'}), magasin()));

      expect(r, contains('FOURNISSEUR — Import Turquie'));
      expect(r, contains('622000001'));
      expect(r, contains('Matoto'));
      // Le détail des entrées, avec l'article concerné.
      expect(r, contains('Tube carré 40x40'));
      expect(r, contains('Tôle galvanisée 2mm'));
    });

    test('oriente au lieu de rendre une liste vide sur un terme inconnu', () {
      final r = executerOutil(
          const AppelOutil('fournisseurs', {'terme': 'zzz'}), magasin());
      expect(r, contains('Aucun fournisseur'));
      expect(r, contains('sans terme'));
    });

    test('dit comment en créer un quand il n\'y en a aucun', () {
      const vide = DonneesMagasin(
        articles: [], ventes: [], clients: [], factures: [], depenses: [],
        mouvements: [], voitPrixAchat: true,
      );
      final r = executerOutil(const AppelOutil('fournisseurs', {}), vide);
      expect(r, contains('aucun fournisseur enregistré'));
      expect(r, contains('page Fournisseurs'));
    });

    test('reste accessible à un vendeur : ce n\'est pas un prix d\'achat', () {
      expect(documenterOutils(false), contains('fournisseurs'));
    });
  });

  group('equipe_et_parametres', () {
    test('rend la fiche du magasin telle qu\'elle est imprimée', () {
      final d = DonneesMagasin(
        articles: const [],
        ventes: const [],
        clients: const [],
        factures: const [],
        depenses: const [],
        mouvements: const [],
        entreprise: Entreprise(
          nom: 'E.A.S Sarlu',
          ville: 'Conakry',
          telephone: '+224 000 00 00 00',
          nif: 'NIF-123',
        ),
        voitPrixAchat: true,
      );
      final r = executerOutil(const AppelOutil('equipe_et_parametres', {}), d);

      expect(r, contains('E.A.S Sarlu'));
      expect(r, contains('Conakry'));
      expect(r, contains('NIF-123'));
    });

    test('nomme les droits en clair plutôt qu\'en codes internes', () {
      final d = DonneesMagasin(
        articles: const [],
        ventes: const [],
        clients: const [],
        factures: const [],
        depenses: const [],
        mouvements: const [],
        utilisateurs: [
          Utilisateur(
              id: 'u1', nom: 'Mamadou', email: 'm@x.gn', droits: const ['vendre']),
        ],
        voitPrixAchat: true,
      );
      final r = executerOutil(const AppelOutil('equipe_et_parametres', {}), d);

      expect(r, contains('Mamadou'));
      expect(r, contains('Vendre et encaisser'),
          reason: 'un modèle qui lit « vendre » le répétera tel quel au gérant');
    });

    test('dit pourquoi la liste est vide plutôt que de laisser un blanc', () {
      // Le serveur ne détaille les droits des autres comptes qu'à qui gère les
      // comptes : un silence ici se lit comme une panne.
      const d = DonneesMagasin(
        articles: [],
        ventes: [],
        clients: [],
        factures: [],
        depenses: [],
        mouvements: [],
        voitPrixAchat: true,
      );
      final r = executerOutil(const AppelOutil('equipe_et_parametres', {}), d);
      expect(r, contains('gérer les comptes'));
    });
  });
}
