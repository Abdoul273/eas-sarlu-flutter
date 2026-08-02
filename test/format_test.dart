import 'package:eas_sarlu/app/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  _lettres();
  // Même initialisation que `main()` : sans elle, tout DateFormat en 'fr_FR'
  // lève LocaleDataException.
  setUpAll(() async {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
  });

  // En français, `intl` sépare les milliers par une espace fine insécable
  // (U+202F) et non par une espace ordinaire.
  const fine = ' ';

  group('Montants', () {
    test('fmtGNF groupe les milliers et suffixe la devise', () {
      expect(fmtGNF(1500000), '1${fine}500${fine}000 GNF');
      expect(fmtGNF(0), '0 GNF');
    });

    test('fmtNombre groupe les milliers', () {
      expect(fmtNombre(1234567), '1${fine}234${fine}567');
    });
  });

  group('Dates', () {
    test('fmtDate rend le mois en français', () {
      expect(fmtDate(DateTime(2026, 7, 29)), '29 juillet 2026');
    });

    test('fmtDateIso accepte une chaîne ISO', () {
      expect(fmtDateIso('2026-07-29T14:05:00Z'), '29 juillet 2026');
    });

    test('fmtDateHeureExacteIso formatte selon exemple jeu. 30/07/26 8:15', () {
      expect(
          fmtDateHeureExacteIso('2026-07-30T08:15:00'), 'jeu. 30/07/26 8:15');
    });

    test('fmtHeureIso rend l\'heure', () {
      expect(fmtHeureIso('2026-07-29T14:05:00'), '14:05');
    });

    // Les modèles tolèrent une date absente : le formatage ne doit jamais
    // lever d'exception, sinon l'écran entier échoue à se construire.
    test('une date absente ou illisible ne lève pas d\'exception', () {
      // Note : « 2026-13-45 » n'en fait pas partie — DateTime.tryParse le
      // reporte volontairement au 14/02/2027 au lieu de le rejeter.
      for (final mauvaise in [null, '', 'pas-une-date', '29/07/2026']) {
        expect(fmtDateIso(mauvaise), '—', reason: 'fmtDateIso($mauvaise)');
        expect(fmtDateCourtIso(mauvaise), '—',
            reason: 'fmtDateCourtIso($mauvaise)');
        expect(fmtDateHeureExacteIso(mauvaise), '—',
            reason: 'fmtDateHeureExacteIso($mauvaise)');
        expect(fmtHeureIso(mauvaise), '—', reason: 'fmtHeureIso($mauvaise)');
      }
    });

    test('le texte de remplacement est personnalisable', () {
      expect(fmtDateIso(null, siInvalide: 'sans date'), 'sans date');
    });
  });
}

// ─── Montant en toutes lettres ────────────────────────────────────────────────
// Portage de `src/lib/__tests__/format.test.ts`. C'est la mention qui fait foi
// en cas de contestation sur la facture papier : chaque irrégularité du
// français y est vérifiée une par une.

void _lettres() {
  group('montantEnLettres', () {
    test('écrit zéro', () {
      expect(montantEnLettres(0), 'zéro');
    });

    test('écrit les unités et les nombres jusqu\'à seize', () {
      expect(montantEnLettres(1), 'un');
      expect(montantEnLettres(7), 'sept');
      expect(montantEnLettres(16), 'seize');
    });

    test('écrit les composés de dix-sept à dix-neuf', () {
      expect(montantEnLettres(17), 'dix-sept');
      expect(montantEnLettres(19), 'dix-neuf');
    });

    test('écrit les dizaines rondes', () {
      expect(montantEnLettres(20), 'vingt');
      expect(montantEnLettres(30), 'trente');
      expect(montantEnLettres(60), 'soixante');
    });

    test('écrit « et un » sauf à quatre-vingt-un', () {
      expect(montantEnLettres(21), 'vingt et un');
      expect(montantEnLettres(31), 'trente et un');
      expect(montantEnLettres(71), 'soixante-onze');
      expect(montantEnLettres(81), 'quatre-vingt-un');
    });

    test('compte les 70 et les 90 à partir de la dizaine inférieure', () {
      expect(montantEnLettres(70), 'soixante-dix');
      expect(montantEnLettres(77), 'soixante-dix-sept');
      expect(montantEnLettres(90), 'quatre-vingt-dix');
      expect(montantEnLettres(99), 'quatre-vingt-dix-neuf');
    });

    test('accorde « quatre-vingts » seul et l\'invariabilise devant un chiffre',
        () {
      expect(montantEnLettres(80), 'quatre-vingts');
      expect(montantEnLettres(82), 'quatre-vingt-deux');
    });

    test('écrit « cent » sans « un » devant, et l\'accorde au pluriel isolé',
        () {
      expect(montantEnLettres(100), 'cent');
      expect(montantEnLettres(200), 'deux cents');
      expect(montantEnLettres(201), 'deux cent un');
      expect(montantEnLettres(180), 'cent quatre-vingts');
    });

    test('écrit « mille » sans « un » devant et sans s', () {
      expect(montantEnLettres(1000), 'mille');
      expect(montantEnLettres(2000), 'deux mille');
      expect(montantEnLettres(1001), 'mille un');
      expect(montantEnLettres(80000), 'quatre-vingts mille');
    });

    test('accorde millions et milliards au pluriel', () {
      expect(montantEnLettres(1000000), 'un million');
      expect(montantEnLettres(2000000), 'deux millions');
      expect(montantEnLettres(1000000000), 'un milliard');
      expect(montantEnLettres(3000000000), 'trois milliards');
    });

    test('compose un montant de facture réaliste', () {
      expect(montantEnLettres(1275000),
          'un million deux cent soixante-quinze mille');
      expect(montantEnLettres(4350000),
          'quatre millions trois cent cinquante mille');
    });

    test('arrondit les décimales : la facture ne porte pas de centimes', () {
      expect(montantEnLettres(1000.4), 'mille');
      expect(montantEnLettres(999.6), 'mille');
    });

    test('préfixe « moins » pour un montant négatif', () {
      expect(montantEnLettres(-1500), 'moins mille cinq cents');
    });

    test('ne laisse jamais passer « null » ni « NaN » dans le texte', () {
      for (final n in [1, 15, 70, 80, 91, 100, 999, 1000, 90071, 1000000, 999999999]) {
        expect(montantEnLettres(n), isNot(matches(RegExp(r'null|NaN'))));
      }
    });
  });
}
