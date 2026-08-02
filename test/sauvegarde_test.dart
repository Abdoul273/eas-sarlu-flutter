// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/core/sauvegarde/sauvegarde.dart';

// Le fichier de sauvegarde est la dernière ligne de défense : c'est ce qu'on
// ressort quand tout le reste a échoué. Il doit se refuser franchement quand il
// n'est pas exploitable, et dire ce qu'il contient AVANT qu'on écrase quoi que
// ce soit.
//
// Les mêmes cas sont vérifiés côté web (`src/lib/__tests__/sauvegarde.test.ts`),
// sur les mêmes valeurs : les deux applications doivent lire le fichier de
// l'autre à l'identique.

final donnees = <String, dynamic>{
  'schemaVersion': '3.1',
  'exportDate': '2026-08-01T10:00:00.000Z',
  'articles': [
    {'id': 'A1'},
    {'id': 'A2'}
  ],
  'ventes': [
    {'id': 'V1'}
  ],
  'clients': [
    {'id': 'C1'}
  ],
  'factures': [
    {'id': 'F1'}
  ],
  'mouvements': <dynamic>[],
  'depenses': [
    {'id': 'D1'},
    {'id': 'D2'}
  ],
  'entreprise': {'nom': 'E.A.S Sarlu'},
};

void main() {
  group('resumerSauvegarde', () {
    test('compte ce que contient la sauvegarde', () {
      final r = resumerSauvegarde(donnees);
      expect(r['articles'], 2);
      expect(r['ventes'], 1);
      expect(r['mouvements'], 0);
      expect(r['depenses'], 2);
      expect(r.entreprise, 'E.A.S Sarlu');
      expect(r.total, 7);
    });

    test('ne s\'effondre pas sur une sauvegarde incomplète', () {
      final r = resumerSauvegarde({});
      expect(r.total, 0);
      expect(r.entreprise, '');
    });
  });

  group('construireEnveloppe', () {
    test('marque le fichier et y joint son résumé', () {
      final e = construireEnveloppe(donnees);
      expect(e['format'], kFormatSauvegarde);
      expect(e['schemaVersion'], '3.1');
      expect((e['resume'] as Map)['articles'], 2);
    });

    test('fait un aller-retour sans rien perdre', () {
      final lu = lireSauvegarde(jsonEncode(construireEnveloppe(donnees)));
      expect(lu.donnees['articles'], hasLength(2));
      expect(lu.resume['ventes'], 1);
      expect(lu.ancienFormat, isFalse);
      expect(lu.avertissements, isEmpty);
    });
  });

  group('nomFichierSauvegarde', () {
    test('nomme le fichier de façon reconnaissable et triable', () {
      expect(nomFichierSauvegarde(DateTime(2026, 8, 1, 9, 5)),
          'eas-sarlu-sauvegarde-2026-08-01-09h05.json');
    });
  });

  group('lireSauvegarde', () {
    test('refuse un fichier qui n\'est pas du JSON', () {
      // Le cas d'un transfert interrompu : le fichier est là, mais coupé.
      expect(() => lireSauvegarde("{ceci n'est pas"),
          throwsA(isA<SauvegardeInvalide>()));
      expect(() => lireSauvegarde(''), throwsA(isA<SauvegardeInvalide>()));
    });

    test('refuse un JSON qui n\'a rien d\'une sauvegarde', () {
      expect(() => lireSauvegarde('{"bonjour":"monde"}'),
          throwsA(isA<SauvegardeInvalide>()));
      expect(
          () => lireSauvegarde('[1,2,3]'), throwsA(isA<SauvegardeInvalide>()));
      expect(() => lireSauvegarde('null'), throwsA(isA<SauvegardeInvalide>()));
    });

    test('explique pourquoi il refuse, plutôt que « erreur »', () {
      try {
        lireSauvegarde("{ceci n'est pas");
        fail('aurait dû refuser');
      } on SauvegardeInvalide catch (e) {
        expect(e.message, matches(RegExp('transfert interrompu|refaites')));
      }
    });

    test('accepte les sauvegardes d\'avant l\'enveloppe', () {
      // Elles portaient les collections à la racine. Les refuser rendrait
      // inutilisables les fichiers déjà chez le gérant.
      final lu = lireSauvegarde(jsonEncode(donnees));
      expect(lu.ancienFormat, isTrue);
      expect(lu.resume['articles'], 2);
    });

    test('signale une sauvegarde partielle sans la refuser', () {
      final lu = lireSauvegarde(jsonEncode({
        'articles': [
          {'id': 'A1'}
        ]
      }));
      expect(lu.resume['articles'], 1);
      expect(lu.avertissements.join(' '), contains('partielle'));
      expect(lu.avertissements.join(' '), contains('vidées'));
    });

    test('signale un fichier remanié après coup', () {
      final e = construireEnveloppe(donnees);
      (e['donnees'] as Map)['ventes'] = <dynamic>[];
      final lu = lireSauvegarde(jsonEncode(e));
      expect(lu.avertissements.join(' '), contains('ne correspond pas'));
      expect(lu.avertissements.join(' '), contains('ventes'));
    });

    test('prévient d\'une sauvegarde venue d\'une version plus récente', () {
      final futur = {...construireEnveloppe(donnees), 'schemaVersion': '9.9'};
      final lu = lireSauvegarde(jsonEncode(futur));
      expect(lu.avertissements.join(' '), contains('plus récente'));
    });

    test('ne prévient de rien sur une sauvegarde de la version courante', () {
      final lu = lireSauvegarde(jsonEncode(construireEnveloppe(donnees)));
      expect(lu.avertissements, isEmpty);
    });
  });

  group('compatibilité entre les deux applications', () {
    test('relit une enveloppe écrite par l\'application web', () {
      // Fichier tel que le produit `construireEnveloppe` de src/lib/sauvegarde.ts :
      // c'est ce qu'un gérant restaure sur son téléphone après l'avoir
      // sauvegardé depuis le navigateur.
      const ecritParLeWeb = '''
{
  "format": "eas-sarlu/sauvegarde",
  "schemaVersion": "3.1",
  "exportDate": "2026-08-01T10:00:00.000Z",
  "resume": {
    "articles": 2, "ventes": 1, "clients": 1,
    "factures": 1, "mouvements": 0, "depenses": 2,
    "entreprise": "E.A.S Sarlu"
  },
  "donnees": {
    "schemaVersion": "3.1",
    "articles": [{"id": "A1"}, {"id": "A2"}],
    "ventes": [{"id": "V1"}],
    "clients": [{"id": "C1"}],
    "factures": [{"id": "F1"}],
    "mouvements": [],
    "depenses": [{"id": "D1"}, {"id": "D2"}],
    "entreprise": {"nom": "E.A.S Sarlu"}
  }
}
''';
      final lu = lireSauvegarde(ecritParLeWeb);
      expect(lu.ancienFormat, isFalse);
      expect(lu.resume['articles'], 2);
      expect(lu.resume['depenses'], 2);
      expect(lu.resume.entreprise, 'E.A.S Sarlu');
      expect(lu.avertissements, isEmpty,
          reason: 'un fichier sain ne doit alarmer sur rien');
    });
  });
}
