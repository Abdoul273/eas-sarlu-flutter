// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/core/models/models.dart';

// Les droits d'accès, côté Android.
//
// Ce fichier ne protège rien : c'est le serveur qui refuse. Mais l'écran doit
// dire la même chose que lui, sinon il propose des actions qui échoueront —
// ou cache des actions permises.
//
// Le dernier groupe de tests compare le vocabulaire au serveur, en lisant
// directement son fichier. Les trois listes — serveur, application web,
// application Android — doivent rester identiques ; c'est la seule façon de
// s'en apercevoir avant que ce soit le magasin qui le découvre.

/// Le projet web, voisin du dépôt Flutter. Absent, les tests de concordance
/// sont ignorés plutôt que rendus faussement rouges.
final _serveur = File('/home/anonymous/Téléchargements/Gestion magasin '
    'matériaux construction/supabase/functions/server/index.tsx');

Utilisateur _compte({
  bool proprietaire = false,
  List<String> droits = const [],
  bool actif = true,
}) =>
    Utilisateur(
      id: 'U1',
      nom: 'Ibrahima Bah',
      actif: actif,
      proprietaire: proprietaire,
      droits: droits,
    );

void main() {
  group('aLeDroit', () {
    test('le propriétaire a tout, quoi que dise sa liste', () {
      final patron = _compte(proprietaire: true, droits: const []);
      for (final d in kDroits.keys) {
        expect(patron.aLeDroit(d), isTrue, reason: d);
      }
    });

    test('les autres comptes s\'en tiennent à leur liste', () {
      final vendeur = _compte(droits: const ['vendre']);
      expect(vendeur.aLeDroit('vendre'), isTrue);
      expect(vendeur.aLeDroit('maintenance'), isFalse);
      expect(vendeur.aLeDroit('utilisateurs'), isFalse);
    });

    test('un compte désactivé n\'a plus rien, même propriétaire', () {
      // Le serveur le refuserait de toute façon : l'écran doit dire pareil.
      final revoque = _compte(proprietaire: true, actif: false);
      expect(revoque.aLeDroit('vendre'), isFalse);
      expect(revoque.aLeDroit('maintenance'), isFalse);
    });

    test('un droit inconnu est refusé', () {
      expect(_compte(droits: const ['inventé']).aLeDroit('inventé'), isFalse);
    });
  });

  group('droitsEffectifs', () {
    test('rend la liste complète pour un propriétaire', () {
      expect(_compte(proprietaire: true).droitsEffectifs, kDroits.keys.toList());
    });

    test('écarte ce qui n\'est pas un droit connu', () {
      expect(_compte(droits: const ['vendre', 'inventé']).droitsEffectifs,
          ['vendre']);
    });
  });

  group('lecture du serveur', () {
    test('les droits sont lus depuis le JSON', () {
      final u = Utilisateur.fromJson({
        'id': 'U1',
        'nom': 'Ibrahima',
        'proprietaire': false,
        'droits': ['vendre', 'finances', 'inventé'],
      });
      expect(u.droits, ['vendre', 'finances']);
      expect(u.aLeDroit('vendre'), isTrue);
      expect(u.aLeDroit('finances'), isTrue);
      expect(u.aLeDroit('maintenance'), isFalse);
    });

    test('un serveur pas encore à jour ne prive pas le compte de tout', () {
      // Sans liste de droits, on retombe sur l'ancien réglage plutôt que de
      // rendre le compte incapable de la moindre action.
      final u = Utilisateur.fromJson(
          {'id': 'U1', 'nom': 'Ibrahima', 'voitPrixAchat': true});
      expect(u.aLeDroit('prixAchat'), isTrue);
      expect(u.voitPrixAchat, isTrue);
    });

    test('voitPrixAchat découle du droit, il ne vit plus à part', () {
      final u = _compte(droits: const ['vendre']);
      expect(u.voitPrixAchat, isFalse);
      expect(_compte(droits: const ['prixAchat']).voitPrixAchat, isTrue);
      expect(_compte(proprietaire: true).voitPrixAchat, isTrue);
    });

    test('les droits repartent bien vers le serveur', () {
      final json = _compte(droits: const ['vendre', 'prixAchat']).toJson();
      expect(json['droits'], ['vendre', 'prixAchat']);
      expect(json['proprietaire'], isFalse);
      expect(json['voitPrixAchat'], isTrue);
    });
  });

  group('routeAutorisee', () {
    // Le panneau masque déjà les entrées interdites, mais masquer n'est pas
    // fermer : une route restaurée au démarrage ou un lien direct y mènent
    // quand même. Le routeur est le seul point par lequel toute navigation
    // passe.
    bool pour(Utilisateur u, String chemin) => routeAutorisee(chemin, u.aLeDroit);

    test('le propriétaire atteint tout', () {
      final patron = _compte(proprietaire: true);
      for (final r in const [
        '/accueil', '/ventes', '/stock', '/factures', '/clients', '/bons',
        '/depenses', '/finances', '/rapports', '/parametres', '/activite',
      ]) {
        expect(pour(patron, r), isTrue, reason: r);
      }
    });

    test('un vendeur est arrêté sur ce qui ne le regarde pas', () {
      final vendeur = _compte(droits: const ['vendre']);
      expect(pour(vendeur, '/ventes'), isTrue);
      expect(pour(vendeur, '/bons'), isTrue);
      expect(pour(vendeur, '/factures'), isTrue); // encaisser suppose de les voir
      expect(pour(vendeur, '/depenses'), isFalse);
      expect(pour(vendeur, '/finances'), isFalse);
      expect(pour(vendeur, '/rapports'), isFalse);
    });

    test('les Paramètres restent ouverts à tous', () {
      // On y trouve son propre mot de passe, le code de déverrouillage, le
      // thème et l'assistant IA. Fermer la page entière privait un vendeur de
      // réglages qui sont les siens ; ce sont ses sections sensibles qui sont
      // gardées, une par une.
      expect(pour(_compte(droits: const []), '/parametres'), isTrue);
      expect(pour(_compte(droits: const ['vendre']), '/parametres'), isTrue);
    });

    test('les sous-routes suivent leur écran parent', () {
      // `/factures/F1` ne doit pas s'ouvrir parce que le chemin est plus long.
      final sansRien = _compte(droits: const []);
      expect(pour(sansRien, '/factures/F1'), isFalse);
      expect(pour(sansRien, '/depenses/nouvelle'), isFalse);
      expect(pour(_compte(droits: const ['vendre']), '/factures/F1'), isTrue);
    });

    test('un chemin qui ressemble n\'ouvre pas celui qu\'il imite', () {
      // « /venteszzz » n'est pas « /ventes » : on ne compare pas des préfixes
      // nus, sinon une route ajoutée plus tard hériterait de droits au hasard.
      final sansRien = _compte(droits: const []);
      expect(pour(sansRien, '/venteszzz'), isTrue,
          reason: 'chemin inconnu : ouvert, mais pas confondu avec /ventes');
    });

    test('les écrans du quotidien restent ouverts à tous', () {
      final sansRien = _compte(droits: const []);
      for (final r in const ['/accueil', '/stock', '/clients', '/activite']) {
        expect(pour(sansRien, r), isTrue, reason: r);
      }
    });

    test('les sections d\'administration restent nommées', () {
      // Le routeur laisse entrer, ce sont les sections qui filtrent : la liste
      // doit rester en phase avec ce que garde la page des paramètres.
      expect(kDroitsAdministration,
          ['entreprise', 'utilisateurs', 'appareils', 'maintenance']);
    });
  });

  group('concordance avec le serveur', () {
    test('expose exactement les mêmes droits que le serveur', () {
      if (!_serveur.existsSync()) {
        markTestSkipped('Projet web absent : concordance non vérifiable ici.');
        return;
      }
      final source = _serveur.readAsStringSync();
      final bloc =
          RegExp(r'const DROITS = \{([\s\S]*?)\n\} as const;').firstMatch(source);
      expect(bloc, isNotNull,
          reason: 'bloc DROITS introuvable dans le serveur');
      final cles = RegExp(r'^\s{2}(\w+):', multiLine: true)
          .allMatches(bloc!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(cles..sort(), kDroits.keys.toList()..sort());
    });
  });
}
