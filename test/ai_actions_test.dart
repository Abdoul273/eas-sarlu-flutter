// Ce que l'assistant a le droit d'écrire, et ce qu'aucune formulation ne lui
// obtiendra.
//
// Miroir de `src/lib/__tests__/ai-actions.test.ts` de l'application web. Les
// deux applications parlent au même serveur : elles doivent refuser les mêmes
// choses aux mêmes personnes, et un test qui passerait d'un côté seulement
// signalerait que les deux serrures ont divergé.

import 'package:eas_sarlu/core/models/models.dart';
import 'package:eas_sarlu/features/assistant/ai_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Utilisateur _compte({List<String> droits = const [], bool proprietaire = false}) =>
    Utilisateur(
      id: 'u1',
      email: 'x@y.gn',
      nom: 'Compte',
      actif: true,
      droits: droits,
      proprietaire: proprietaire,
    );

final _patron = _compte(proprietaire: true);
final _magasinier = _compte(droits: const ['stock']);
final _vendeur = _compte(droits: const ['vendre', 'finances']);
final _comptable = _compte(droits: const ['depenses', 'finances']);
final _sansRien = _compte();

final _ctx = ContexteResume(
  articles: [
    Article(
      id: 'A001',
      ref: 'COR-30',
      nom: 'Cornière 30×30×3',
      categorie: 'Profilés',
      unite: 'barre',
      stock: 24,
      stockMin: 5,
      prixAchat: 40000,
      prixVente: 55000,
    ),
  ],
  clients: [Client(id: 'C001', nom: 'Mamadou Diallo')],
);

/// Les actions qui écrivent réellement — « naviguer » n'en fait pas partie.
final _ecritures = kActions.where((a) => a.droit != null).toList();

void main() {
  group('le catalogue lui-même', () {
    test('ne contient aucun geste irréversible', () {
      // La sûreté ne vient pas d'un refus à écrire : elle vient de l'absence.
      // Ajouter ici une suppression rendrait ce test rouge, et c'est le but.
      final interdit =
          RegExp(r'supprim|delete|annul|efface|reset|restaur|reinitialis',
              caseSensitive: false);
      for (final a in kActions) {
        expect(interdit.hasMatch(a.type), isFalse,
            reason: '${a.type} ressemble à un geste irréversible');
      }
    });

    test('n\'exige que des droits qui existent réellement', () {
      for (final a in _ecritures) {
        expect(kDroits.keys, contains(a.droit));
      }
    });

    test('ne laisse que « naviguer » sans droit exigé', () {
      // Toute action qui écrit doit nommer son droit. Une écriture posée à
      // `droit: null` traverserait la serrure sans même être vue.
      expect(
          kActions.where((a) => a.droit == null).map((a) => a.type).toList(),
          ['naviguer']);
    });

    test('donne à chaque action au moins un champ obligatoire', () {
      // Une action sans champ obligatoire partirait sur un simple « oui »,
      // sans que rien n'ait été vérifié.
      for (final a in kActions) {
        expect(a.champs.any((c) => c.requis), isTrue, reason: a.type);
      }
    });
  });

  group('verifierAction — la serrure', () {
    test('refuse une action qui n\'existe pas, même au propriétaire', () {
      final v = verifierAction('supprimerTout', const {}, _patron);
      expect(v.ok, isFalse);
      expect(v.motif, contains('n\'existe pas'));
    });

    test('refuse au magasinier de vendre ou d\'encaisser', () {
      for (final type in const [
        'createVente',
        'enregistrerPaiement',
        'createClient'
      ]) {
        final v = verifierAction(type, const {}, _magasinier);
        expect(v.ok, isFalse, reason: type);
        expect(v.motif, contains(kDroits['vendre']!));
      }
    });

    test('refuse au vendeur de toucher au catalogue et au stock', () {
      for (final type in const [
        'addStock',
        'removeStock',
        'createArticle',
        'updateArticle'
      ]) {
        final v = verifierAction(type, const {}, _vendeur);
        expect(v.ok, isFalse, reason: type);
        expect(v.motif, contains(kDroits['stock']!));
      }
    });

    test('refuse la dépense à qui n\'a pas le droit de la saisir', () {
      final v = verifierAction(
          'createDepense', const {'libelle': 'Carburant'}, _vendeur);
      expect(v.ok, isFalse);
      expect(v.motif, contains(kDroits['depenses']!));
      expect(
          verifierAction('createDepense',
              const {'libelle': 'x', 'montant': 1, 'categorie': 'Carburant'},
              _comptable).ok,
          isTrue);
    });

    test('refuse toute écriture à un compte sans aucun droit', () {
      for (final a in _ecritures) {
        expect(verifierAction(a.type, const {}, _sansRien).ok, isFalse,
            reason: a.type);
      }
    });

    test('refuse toute écriture à un compte inconnu ou pas encore chargé', () {
      // Pendant le chargement, mieux vaut refuser une action permise que d'en
      // laisser passer une qui ne l'était pas.
      for (final a in _ecritures) {
        expect(verifierAction(a.type, const {}, null).ok, isFalse,
            reason: a.type);
      }
    });

    test('laisse « naviguer » à tous — ouvrir un écran n\'écrit nulle part', () {
      expect(verifierAction('naviguer', const {'page': 'stock'}, _sansRien).ok,
          isTrue);
      expect(
          verifierAction('naviguer', const {'page': 'stock'}, null).ok, isTrue);
    });

    test('laisse passer ce que le droit couvre, et seulement cela', () {
      expect(
          verifierAction('addStock',
              const {'articleId': 'A001', 'quantite': 10}, _magasinier).ok,
          isTrue);
      expect(
          verifierAction('createVente',
              const {'clientId': 'C001', 'lignes': [{}]}, _vendeur).ok,
          isTrue);
    });

    test('accorde tout au propriétaire, quoi que dise sa liste de droits', () {
      for (final a in kActions) {
        expect(verifierAction(a.type, const {}, _patron).ok, isTrue,
            reason: a.type);
      }
    });

    test('applique la même serrure aux noms alternatifs', () {
      // `ajouterPaiement` et `enregistrerPaiement` désignent le même geste : le
      // second serait une porte dérobée si seul le premier était gardé.
      expect(verifierAction('ajouterPaiement', const {}, _magasinier).ok,
          isFalse);
      expect(verifierAction('addDepense', const {}, _vendeur).ok, isFalse);
      expect(verifierAction('ouvrirPage', const {'page': 'stock'}, _sansRien).ok,
          isTrue);
      expect(canoniser('ajouterPaiement'), 'enregistrerPaiement');
      expect(trouverAction('addDepense')?.type, 'createDepense');
    });

    test('ne se fie pas à ce que le message système a documenté', () {
      // Le cœur de l'affaire : même si le modèle est persuadé d'avoir le droit
      // — parce qu'on l'en a convaincu, ou parce qu'il a inventé la notice —
      // la décision se prend ici, sur la liste de droits du compte.
      expect(documenterActions(_vendeur), isNot(contains('addStock')));
      expect(
          verifierAction('addStock',
              const {'articleId': 'A001', 'quantite': 5}, _vendeur).ok,
          isFalse);
    });

    test('réclame les champs obligatoires absents plutôt que de les inventer',
        () {
      final v =
          verifierAction('addStock', const {'articleId': 'A001'}, _magasinier);
      expect(v.ok, isTrue);
      expect(v.manquants.map((c) => c.nom).toList(), ['quantite']);
    });

    test('ne considère pas un champ vide ou blanc comme renseigné', () {
      final v = verifierAction(
          'addStock', const {'articleId': '  ', 'quantite': ''}, _magasinier);
      expect(v.ok, isTrue);
      expect(v.manquants.map((c) => c.nom).toList()..sort(),
          ['articleId', 'quantite']);
    });
  });

  group('actionsPermises', () {
    test('ne rend à chacun que ce que ses droits couvrent', () {
      expect(actionsEcriture(_magasinier).map((a) => a.type).toList(),
          ['addStock', 'removeStock', 'createArticle', 'updateArticle',
            'createFournisseur']);
      expect(actionsEcriture(_vendeur).map((a) => a.type).toList(),
          ['createClient', 'createVente', 'enregistrerPaiement']);
      expect(actionsEcriture(_comptable).map((a) => a.type).toList(),
          ['createDepense', 'reglerDepense']);
      expect(actionsEcriture(_sansRien), isEmpty);
      expect(actionsEcriture(null), isEmpty);
      expect(actionsEcriture(_patron).length, _ecritures.length);
    });

    test('laisse « naviguer » à tous, y compris sans aucun droit', () {
      expect(
          actionsPermises(_sansRien).map((a) => a.type).toList(), ['naviguer']);
    });
  });

  group('documenterActions', () {
    test('ne documente à chacun que ce qu\'il peut faire', () {
      final pourMagasinier = documenterActions(_magasinier);
      expect(pourMagasinier, contains('addStock'));
      expect(pourMagasinier, isNot(contains('createVente')));
      expect(pourMagasinier, isNot(contains('createDepense')));
    });

    test('dit clairement à un compte sans droit qu\'il ne peut rien écrire',
        () {
      final notice = documenterActions(_sansRien);
      for (final a in _ecritures) {
        expect(notice, isNot(contains('- ${a.type} —')));
      }
      expect(notice, contains('AUCUNE ÉCRITURE'));
    });

    test('ne cite en exemple qu\'une action réellement permise', () {
      // Un exemple figé citerait `addStock` à un vendeur qui n'y a pas droit :
      // on lui mettrait sous les yeux, en toutes lettres, le nom de la porte
      // qu'on vient de lui fermer.
      final cite = RegExp(r'\{"type":"(\w+)"')
          .firstMatch(documenterActions(_vendeur))
          ?.group(1);
      expect(actionsEcriture(_vendeur).map((a) => a.type), contains(cite));
    });

    test('interdit au modèle de prétendre avoir agi', () {
      expect(documenterActions(_patron), contains('Ne dis JAMAIS'));
    });
  });

  group('extraireActions', () {
    test('repère une action et sépare le texte qui l\'entoure', () {
      final r = extraireActions('Je te prépare ça.\n'
          '```action\n{"type":"addStock","articleId":"COR-30","quantite":10}\n```');
      expect(r.texte, 'Je te prépare ça.');
      expect(r.actions.length, 1);
      expect(r.actions.first.type, 'addStock');
      expect(r.actions.first.params['quantite'], 10);
    });

    test('accepte les champs groupés sous « params » comme à plat', () {
      final r = extraireActions(
          '```action\n{"type":"addStock","params":{"quantite":3}}\n```');
      expect(r.actions.first.params['quantite'], 3);
      expect(r.actions.first.params.containsKey('params'), isFalse);
    });

    test('lit une liste d\'actions à confirmer d\'un coup', () {
      final r = extraireActions('```action\n{"actions":['
          '{"type":"createClient","nom":"SODEC"},'
          '{"type":"naviguer","page":"clients"}]}\n```');
      expect(r.actions.map((a) => a.type).toList(),
          ['createClient', 'naviguer']);
    });

    test('ne se noie pas sur un bloc illisible', () {
      final r = extraireActions('```action\npas du json\n```');
      expect(r.actions, isEmpty);
    });

    test('ne voit pas d\'action là où il n\'y en a pas', () {
      expect(extraireActions('Le stock tient trois jours.').actions, isEmpty);
    });
  });

  group('la serrure anti-doublon', () {
    // Le droit de créer un article ne protège de rien ici : c'est le patron
    // lui-même qui, en dictant « ajoute 10 barres de cornière 30 », obtenait une
    // deuxième cornière 30 à côté de la première.
    test('refuse de créer ce qui existe déjà sous un autre libellé', () {
      final motif = motifDoublonArticle(_ctx.articles, 'cornière 30');
      expect(motif, isNotNull);
      expect(motif, contains('COR-30'));
      expect(motif, contains('entrée de stock'));
    });

    test('laisse passer une marchandise réellement nouvelle', () {
      expect(motifDoublonArticle(_ctx.articles, 'Ciment Diamond 42,5'), isNull);
    });

    test('laisse passer quand le commerçant a confirmé malgré l\'avertissement',
        () {
      expect(
          motifDoublonArticle(_ctx.articles, 'cornière 30', confirme: true),
          isNull);
    });

    test('n\'accepte comme confirmation qu\'un accord franc', () {
      expect(confirmationNouvelArticle(const {'confirmerNouveau': 'oui'}),
          isTrue);
      expect(confirmationNouvelArticle(const {'confirmerNouveau': 'non'}),
          isFalse);
      // Le silence du modèle n'est pas un accord du commerçant.
      expect(confirmationNouvelArticle(const {}), isFalse);
      expect(confirmationNouvelArticle(const {'confirmerNouveau': 'peut-être'}),
          isFalse);
    });

    test('la notice impose de passer par resoudre_article', () {
      final notice = documenterActions(_magasinier);
      expect(notice, contains('resoudre_article'));
      expect(notice, contains('confirmerNouveau'));
      expect(notice, contains('galva'));
    });

    test('ne nomme pas les actions de stock à qui n\'y a pas droit', () {
      final notice = documenterActions(_vendeur);
      expect(notice, contains('resoudre_article'));
      expect(notice, isNot(contains('addStock')));
      expect(notice, isNot(contains('createArticle')));
    });
  });

  group('le résumé de confirmation', () {
    String resumer(String type, Map<String, dynamic> args) =>
        trouverAction(type)!.resume(args, _ctx).join('\n');

    test('dit ce qui va changer, chiffres à l\'appui', () {
      final r = resumer('addStock', const {'articleId': 'A001', 'quantite': 10});
      expect(r, contains('Cornière 30×30×3'));
      expect(r, contains('de 24 à 34'));
    });

    test('retrouve l\'article par sa référence comme par son nom', () {
      expect(resumer('addStock', const {'articleId': 'COR-30', 'quantite': 1}),
          contains('Cornière 30×30×3'));
      expect(resumer('addStock', const {'articleId': 'cornière', 'quantite': 1}),
          contains('Cornière 30×30×3'));
    });

    test('avertit quand une sortie ferait passer le stock sous zéro', () {
      expect(
          resumer('removeStock', const {'articleId': 'A001', 'quantite': 30}),
          contains('négatif'));
    });

    test('avertit quand une vente dépasse le stock disponible', () {
      final r = resumer('createVente', const {
        'clientId': 'C001',
        'lignes': [
          {'articleId': 'A001', 'qte': 40, 'prixUnitaire': 50000}
        ],
      });
      expect(r, contains('que 24 barre'));
      expect(r, contains('Mamadou Diallo'));
    });

    test('signale la référence existante avant d\'en créer une deuxième', () {
      final r = resumer('createArticle', const {
        'nom': 'Cornière 30',
        'categorie': 'Profilés',
        'unite': 'barre',
        'prixVente': 60000,
      });
      expect(r, contains('ATTENTION'));
      expect(r, contains('COR-30'));
      expect(r, contains('entrée de stock'));
    });

    test('ne crie pas au doublon sur une marchandise réellement nouvelle', () {
      final r = resumer('createArticle', const {
        'nom': 'Ciment Diamond 42,5',
        'categorie': 'Ciment',
        'unite': 'sac',
        'prixVente': 95000,
      });
      expect(r, isNot(contains('ATTENTION')));
    });

    test('avertit quand un article serait vendu à perte', () {
      final r = resumer('createArticle', const {
        'nom': 'Tôle',
        'categorie': 'Tôles',
        'unite': 'feuille',
        'prixVente': 1000,
        'prixAchat': 1500,
      });
      expect(r, contains('à perte'));
    });

    test('lit un montant écrit à la façon d\'un modèle, espaces compris', () {
      final r = resumer('createDepense',
          const {'libelle': 'Carburant', 'montant': '500 000 GNF'});
      expect(r, contains(fmtMontantAttendu));
    });

    test('dit que « naviguer » ne modifie rien', () {
      expect(resumer('naviguer', const {'page': 'stock'}),
          contains('Rien n\'est modifié'));
    });
  });
}

/// Le montant tel que l'application le met en forme — le séparateur de milliers
/// n'est pas une espace ordinaire, et comparer à « 500 000 » écrit à la main
/// échouerait pour une raison qui n'a rien à voir avec la lecture du nombre.
final fmtMontantAttendu = _montant(500000);
String _montant(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
