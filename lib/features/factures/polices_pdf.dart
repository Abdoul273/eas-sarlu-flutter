import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

// ─── La police des documents imprimés ─────────────────────────────────────────
// Roboto, embarquée dans l'application. Trois raisons, et aucune n'est
// esthétique :
//
//   — c'est la police des documents que le magasin imprime déjà. Un client qui
//     reçoit une facture doit reconnaître la même page que la semaine passée ;
//   — elle est EMBARQUÉE et non téléchargée. `PdfGoogleFonts` va la chercher
//     sur le réseau : une facture au comptoir de Conakry sortirait alors sans
//     police, ou pas du tout ;
//   — elle porte l'Unicode. Les polices standard du PDF (Helvetica & co) n'ont
//     que le jeu WinAnsi : un tiret cadratin, un « ⚠ », une puce y sortaient
//     BLANCS sur le papier, sans qu'aucune erreur ne soit levée. Ce piège a
//     déjà coûté une ligne entière sur un devis.

/// Les trois graisses employées par le gabarit.
///
/// L'accentuation est en Medium (500) et non en Bold (700) : c'est la graisse
/// des documents de référence du magasin. Le Bold, comparé côte à côte, écrase
/// les intitulés du pied et la mention « Signature ».
class PolicesDocument {
  final pw.Font regulier;
  final pw.Font gras;
  final pw.Font italique;

  const PolicesDocument(this.regulier, this.gras, this.italique);
}

PolicesDocument? _cache;

/// Le repli, quand les fichiers de police sont introuvables.
///
/// Un document sans accents corrects vaut mieux que pas de document : le
/// magasin doit pouvoir remettre son papier même si l'application a été
/// assemblée de travers.
PolicesDocument _repli() => PolicesDocument(
      pw.Font.helvetica(),
      pw.Font.helveticaBold(),
      pw.Font.helveticaOblique(),
    );

/// Charge les polices une fois pour toutes.
///
/// Elles pèsent près d'un mégaoctet et sont analysées à chaque appel : les
/// relire pour chaque facture ferait attendre une seconde à chaque impression.
Future<PolicesDocument> chargerPolices() async {
  final dejaLa = _cache;
  if (dejaLa != null) return dejaLa;

  try {
    final chargees = PolicesDocument(
      pw.Font.ttf(await rootBundle.load('assets/polices/Roboto-Regular.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/polices/Roboto-Medium.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/polices/Roboto-Italic.ttf')),
    );
    _cache = chargees;
    return chargees;
  } catch (e) {
    // Et on le DIT. Un repli muet livrerait des factures sans accents pendant
    // des mois sans que personne ne comprenne pourquoi « Cornière » s'imprime
    // « Corni re » : la police manquante est une erreur d'assemblage, pas un
    // état normal.
    debugPrint('Polices du document introuvables, repli sur Helvetica : $e');
    return _repli();
  }
}
