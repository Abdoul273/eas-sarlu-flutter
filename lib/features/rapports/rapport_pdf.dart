import '../../app/format.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/models.dart';
import 'rapport_modele.dart';

// ─── Rapport imprimable ───────────────────────────────────────────────────────
// Transposition fidèle du gabarit de l'application web (`src/lib/print-rapport.ts`).
// Un document que le gérant peut poser sur la table devant sa banque, son
// comptable ou son associé. Il obéit aux mêmes règles que la facture du
// magasin : un seul gabarit, aucune ressource externe (le document doit
// s'ouvrir sans réseau), tout en noir sauf les accents — l'encre couleur coûte
// cher à Conakry.
//
// Le rapport n'affirme jamais plus que ce qu'il sait. Les valeurs de stock sont
// annoncées comme étant celles du jour d'édition, la marge comme une estimation
// au prix d'achat actuel, et les deux lectures argent — résultat et trésorerie —
// restent dans deux colonnes séparées qui ne s'additionnent pas.

// ─── Conversion des unités du gabarit web ─────────────────────────────────────
// Le gabarit HTML est coté en pixels CSS (96 ppp) et en millimètres, le PDF en
// points typographiques (72 ppp). On transpose plutôt que de recalculer chaque
// cote à la main : les deux gabarits ne peuvent pas diverger en silence.
double _px(double cssPx) => cssPx * 72.0 / 96.0;
double _mm(double millimetres) => millimetres * PdfPageFormat.mm;
double _interligne(double taille, double hauteurLigne) =>
    taille * (hauteurLigne - 1);

// Teintes du gabarit web.
const _n111 = PdfColor.fromInt(0xff111111);
const _n444 = PdfColor.fromInt(0xff444444);
const _n555 = PdfColor.fromInt(0xff555555);
const _n666 = PdfColor.fromInt(0xff666666);
const _n777 = PdfColor.fromInt(0xff777777);
const _n888 = PdfColor.fromInt(0xff888888);
const _n999 = PdfColor.fromInt(0xff999999);
const _naaa = PdfColor.fromInt(0xffaaaaaa);
const _nbbb = PdfColor.fromInt(0xffbbbbbb);
const _nccc = PdfColor.fromInt(0xffcccccc);
const _nddd = PdfColor.fromInt(0xffdddddd);
const _ne5 = PdfColor.fromInt(0xffe5e5e5);
const _neee = PdfColor.fromInt(0xffeeeeee);
const _nfa = PdfColor.fromInt(0xfffafafa);
const _nfb = PdfColor.fromInt(0xfffbfbfb);
const _vert = PdfColor.fromInt(0xff059669);
const _rouge = PdfColor.fromInt(0xffDC2626);
const _ambre = PdfColor.fromInt(0xffD97706);
const _alerteFond = PdfColor.fromInt(0xffFFF6F6);
const _bonFond = PdfColor.fromInt(0xffF7FDFA);
const _bonBord = PdfColor.fromInt(0xffA7F3D0);

/// Le rapport parle beaucoup de « moins » : le gabarit web emploie le signe
/// mathématique U+2212, absent du jeu WinAnsi des polices PDF standard, qui
/// sortirait en blanc. Le tiret ordinaire le remplace.
const _moins = '- ';

PdfColor _couleurHex(String? hex, PdfColor repli) {
  final v = (hex ?? '').trim().replaceFirst('#', '');
  if (v.length != 6) return repli;
  final n = int.tryParse(v, radix: 16);
  return n == null ? repli : PdfColor.fromInt(0xff000000 | n);
}

// ─── Mise en forme ────────────────────────────────────────────────────────────


/// Un montant signé, écrit comme sur le gabarit web : le signe devant, la
/// valeur absolue derrière.
String _signe(int n) => '${n < 0 ? _moins : ''}${numFRPdf(n.abs())}';

String _pct(double n) => '${n.toStringAsFixed(1).replaceAll('.', ',')} %';

/// Compacte les montants des étiquettes de graphique. « 12 450 000 » sous une
/// barre de 8 mm de large déborde sur ses voisines ; « 12,5 M » se lit.
String _compact(num n) {
  final a = n.abs();
  if (a >= 1000000000) {
    return '${(n / 1000000000).toStringAsFixed(1).replaceAll('.', ',')} Md';
  }
  if (a >= 1000000) {
    return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} M';
  }
  if (a >= 1000) return '${(n / 1000).round()} k';
  return numFRPdf(n);
}

const _moisLongs = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _fmtDateLongue(DateTime d) => '${d.day} ${_moisLongs[d.month - 1]} ${d.year}';

String _fmtHeure(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Coupe un libellé trop long pour la largeur de sa colonne, sans casser la
/// mise en page.
String _tronquer(String? s, int n) {
  final t = (s ?? '').trim();
  return t.length > n ? '${t.substring(0, n - 1)}…' : t;
}

String _pluriel(int n, String singulier, [String? pluriel]) =>
    n == 1 ? singulier : (pluriel ?? '${singulier}s');

/// Ramène un texte dans le jeu de caractères que savent tracer les polices PDF
/// standard.
///
/// Helvetica ne couvre que le latin-1 : le tiret cadratin, les points de
/// suspension et l'apostrophe typographique — tous présents dans le gabarit web
/// et susceptibles d'arriver par un nom d'article saisi au téléphone —
/// sortaient en blanc, laissant des trous dans le document. On les remplace par
/// leur équivalent latin-1 ; ce qui reste hors du jeu est écarté plutôt que
/// laissé sous forme de vide inexplicable.
String _lat(String texte) {
  const equivalents = {
    '\u2014': '-', '\u2013': '-', '\u2212': '-', '\u2010': '-', '\u2011': '-',
    '\u2026': '...', '\u2019': "'", '\u2018': "'", '\u201C': '"',
    '\u201D': '"', '\u202F': '\u00A0', '\u2009': ' ', '\u2007': '\u00A0',
    '\u20AC': 'EUR', '\u2022': '\u00B7',
  };
  final tampon = StringBuffer();
  for (final rune in texte.runes) {
    final c = String.fromCharCode(rune);
    final remplacement = equivalents[c];
    if (remplacement != null) {
      tampon.write(remplacement);
    } else if (rune <= 0xFF) {
      tampon.write(c);
    }
  }
  return tampon.toString();
}

/// Un texte du rapport. Tout passe par ici : c'est le seul point où l'on peut
/// garantir qu'aucun caractère intraçable n'atteint la page.
pw.Widget _txt(String texte, {pw.TextStyle? style, pw.TextAlign? textAlign}) =>
    pw.Text(_lat(texte), style: style, textAlign: textAlign);

/// Décode le logo enregistré dans les paramètres, quelle que soit sa forme :
/// l'application web enregistre une adresse de données complète
/// (`data:image/png;base64,…`), la version mobile le base64 seul. Un champ vide
/// ou illisible rend `null` — le document sort alors avec l'initiale de
/// l'entreprise, jamais avec une exception.
pw.ImageProvider? _imageDepuisChamp(String? champ) {
  var donnees = (champ ?? '').trim();
  if (donnees.isEmpty) return null;
  final virgule = donnees.indexOf(',');
  if (donnees.startsWith('data:') && virgule != -1) {
    donnees = donnees.substring(virgule + 1);
  }
  donnees = donnees.replaceAll(RegExp(r'\s'), '');
  if (donnees.isEmpty) return null;
  try {
    final octets = base64Decode(donnees);
    if (octets.isEmpty) return null;
    return pw.MemoryImage(octets);
  } catch (_) {
    return null;
  }
}

// ─── Le gabarit ───────────────────────────────────────────────────────────────

class _Gabarit {
  final RapportComplet r;
  final Entreprise ent;
  final PdfColor accent;
  final String devise;

  final pw.Font regulier, gras, italique;

  _Gabarit(this.r, this.ent)
      : accent = _couleurHex(ent.couleurAccent, const PdfColor.fromInt(0xffE85D04)),
        devise = ent.devise.trim().isEmpty ? 'GNF' : ent.devise.trim(),
        regulier = pw.Font.helvetica(),
        gras = pw.Font.helveticaBold(),
        italique = pw.Font.helveticaOblique();

  // ── Styles, décalqués de la feuille de style du gabarit web ───────────────
  pw.TextStyle get base =>
      pw.TextStyle(font: regulier, fontSize: _px(9.5), color: _n111);
  pw.TextStyle s(double taille,
          {PdfColor? couleur,
          bool fort = false,
          bool italiques = false,
          double? espacement,
          double? hauteurLigne}) =>
      pw.TextStyle(
        font: italiques ? italique : (fort ? gras : regulier),
        fontSize: _px(taille),
        color: couleur ?? _n111,
        letterSpacing: espacement == null ? null : _px(espacement),
        lineSpacing: hauteurLigne == null
            ? null
            : _interligne(_px(taille), hauteurLigne),
      );

  pw.BoxDecoration get carteBord => pw.BoxDecoration(
        border: pw.Border.all(color: _nddd, width: 0.75),
        borderRadius: pw.BorderRadius.circular(_mm(2)),
      );

  // ── Blocs réutilisables ───────────────────────────────────────────────────

  pw.Widget kpi(String label, String valeur, String aide, [PdfColor? couleur]) =>
      pw.Container(
        decoration: carteBord,
        padding: pw.EdgeInsets.symmetric(vertical: _mm(4), horizontal: _mm(3.5)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _txt(label.toUpperCase(),
                style: s(7.5, couleur: _n777, fort: true, espacement: 1.1)),
            pw.SizedBox(height: _mm(2.5)),
            _txt(valeur, style: s(17, fort: true, couleur: couleur)),
            pw.SizedBox(height: _mm(1.5)),
            _txt(aide, style: s(8, couleur: _n777, hauteurLigne: 1.35)),
          ],
        ),
      );

  pw.Widget ligneCompte(
    String label,
    int valeur, {
    String? aide,
    bool total = false,
    bool retrait = false,
    PdfColor? couleur,
    bool signeMoins = false,
  }) =>
      pw.Container(
        margin: total ? pw.EdgeInsets.only(top: _mm(1)) : null,
        decoration: total
            ? const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: _n111, width: 0.6)))
            : null,
        padding: pw.EdgeInsets.only(
            top: total ? _mm(2.4) : _mm(1.9), bottom: _mm(1.9)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.only(left: retrait ? _mm(3.5) : 0),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(
                      text: pw.TextSpan(children: [
                        if (signeMoins)
                          pw.TextSpan(
                              text: '- ', style: s(9.5, couleur: _n999)),
                        pw.TextSpan(text: _lat(label), style: s(9.5, fort: total)),
                      ]),
                    ),
                    if (aide != null && aide.isNotEmpty) ...[
                      pw.SizedBox(height: _mm(0.4)),
                      _txt(aide,
                          style: s(7.5, couleur: _n888, hauteurLigne: 1.35)),
                    ],
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: _mm(4)),
            _txt(_signe(valeur),
                style: s(total ? 13 : 10.5, fort: true, couleur: couleur)),
          ],
        ),
      );

  /// La barre de proportion des tableaux : 14 mm de piste grise, remplie à la
  /// part de la ligne.
  pw.Widget barre(double part, PdfColor couleur) => pw.Container(
        width: _mm(14),
        height: _mm(1.2),
        decoration: pw.BoxDecoration(
            color: _neee, borderRadius: pw.BorderRadius.circular(_mm(1))),
        child: pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(
            width: _mm(14) * (part.clamp(0, 100)) / 100,
            height: _mm(1.2),
            decoration: pw.BoxDecoration(
                color: couleur, borderRadius: pw.BorderRadius.circular(_mm(1))),
          ),
        ),
      );

  pw.Widget cellulePart(double part, PdfColor couleur) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          barre(part, couleur),
          pw.SizedBox(width: _mm(1.6)),
          _txt('${part.round()} %', style: s(9)),
        ],
      );

  pw.Widget pastille(String texte, PdfColor couleur) => pw.Container(
        padding:
            pw.EdgeInsets.symmetric(vertical: _mm(0.5), horizontal: _mm(1.6)),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: couleur, width: 0.45),
          borderRadius: pw.BorderRadius.circular(_mm(6)),
        ),
        child: _txt(texte, style: s(7.5, fort: true, couleur: couleur)),
      );

  pw.Widget noteInline(String texte) => pw.Container(
        margin: pw.EdgeInsets.only(top: _mm(3)),
        padding: pw.EdgeInsets.only(left: _mm(2.5)),
        decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: _nddd, width: 1.2))),
        child: _txt(texte, style: s(8, couleur: _n666, hauteurLigne: 1.5)),
      );

  pw.Widget vide(String message, {bool bon = false}) => pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.all(_mm(7)),
        decoration: pw.BoxDecoration(
          color: bon ? _bonFond : null,
          border: pw.Border.all(color: bon ? _bonBord : _nddd, width: 0.45),
          borderRadius: pw.BorderRadius.circular(_mm(2)),
        ),
        child: _txt(message,
            style: s(9, couleur: bon ? _vert : _n888),
            textAlign: pw.TextAlign.center),
      );

  pw.Widget reste(String texte) => pw.Padding(
        padding: pw.EdgeInsets.only(top: _mm(1.5)),
        child: _txt(texte, style: s(8, couleur: _n888, italiques: true)),
      );

  pw.Widget sousTitre(String texte) => pw.Container(
        width: double.infinity,
        margin: pw.EdgeInsets.only(top: _mm(6), bottom: _mm(2.5)),
        padding: pw.EdgeInsets.only(bottom: _mm(1.2)),
        decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _nddd, width: 0.45))),
        child: _txt(texte, style: s(10, fort: true)),
      );

  /// L'en-tête d'une section : son numéro en gros gris, son titre et la phrase
  /// qui dit ce qu'on y lit.
  pw.Widget teteSection(String numero, String titre, String sousTitreTexte) =>
      pw.Container(
        width: double.infinity,
        margin: pw.EdgeInsets.only(bottom: _mm(5)),
        padding: pw.EdgeInsets.only(bottom: _mm(2.5)),
        decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _n111, width: 1.05))),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _txt(numero,
                style: s(21, fort: true, couleur: _nccc, espacement: -1)),
            pw.SizedBox(width: _mm(4)),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _txt(titre, style: s(14, fort: true, espacement: -0.3)),
                  pw.SizedBox(height: _mm(0.8)),
                  _txt(sousTitreTexte, style: s(9, couleur: _n666)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Une case de la rangée de trois : intitulé en capitales, chiffre, précision.
  pw.Widget trioCase(String label, String valeur, String precision,
          {PdfColor? couleur}) =>
      pw.Container(
          padding: pw.EdgeInsets.all(_mm(3.5)),
          decoration: carteBord,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _txt(label.toUpperCase(),
                  style: s(7.5, couleur: _n777, fort: true, espacement: 1)),
              pw.SizedBox(height: _mm(2)),
              _txt(valeur,
                  style: s(15, fort: true, couleur: couleur, espacement: -0.4)),
              pw.SizedBox(height: _mm(1.2)),
              _txt(precision,
                  style: s(7.5, couleur: _n888, hauteurLigne: 1.35)),
            ],
          ),
      );

  /// Une rangée de cases de largeur et de HAUTEUR égales, comme la grille CSS
  /// du gabarit web.
  ///
  /// Une `Row` ne convient pas : pour égaliser les hauteurs il lui faudrait
  /// `CrossAxisAlignment.stretch`, or dans un document à pages multiples la
  /// hauteur disponible est illimitée — les cases prenaient alors une hauteur
  /// infinie et la génération échouait. Un tableau à alignement `full` donne
  /// la même mise en page sans cette dépendance.
  pw.Widget rangeeEgale(List<pw.Widget> cases, {double gap = 4}) {
    final largeurs = <int, pw.TableColumnWidth>{};
    final cellules = <pw.Widget>[];
    for (var i = 0; i < cases.length; i++) {
      if (i > 0) {
        largeurs[cellules.length] = pw.FixedColumnWidth(_mm(gap));
        cellules.add(pw.SizedBox());
      }
      largeurs[cellules.length] = const pw.FlexColumnWidth(1);
      cellules.add(cases[i]);
    }
    return pw.Table(
      columnWidths: largeurs,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      children: [pw.TableRow(children: cellules)],
    );
  }

  pw.Widget trio(List<pw.Widget> cases) => pw.Container(
        margin: pw.EdgeInsets.only(bottom: _mm(4)),
        child: rangeeEgale(cases),
      );

  /// Une carte de compte : en-tête grisé, puis les lignes du compte.
  pw.Widget carte(String titre, String sousTitreTexte, List<pw.Widget> corps) =>
      pw.Container(
          decoration: carteBord,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                color: _nfa,
                padding: pw.EdgeInsets.symmetric(
                    vertical: _mm(3), horizontal: _mm(4)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _txt(titre, style: s(11, fort: true)),
                    pw.SizedBox(height: _mm(0.6)),
                    _txt(sousTitreTexte,
                        style: s(8, couleur: _n666, hauteurLigne: 1.4)),
                  ],
                ),
              ),
              pw.Container(
                decoration: const pw.BoxDecoration(
                    border:
                        pw.Border(top: pw.BorderSide(color: _neee, width: 0.75))),
                padding: pw.EdgeInsets.fromLTRB(_mm(4), _mm(1.5), _mm(4), _mm(3)),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: corps),
              ),
            ],
          ),
      );

  // ── Tableaux ──────────────────────────────────────────────────────────────

  pw.Widget celluleEntete(String texte, {bool droite = false}) => pw.Padding(
        padding: pw.EdgeInsets.all(_mm(2)),
        child: _txt(texte.toUpperCase(),
            style: s(7.5, fort: true, couleur: _n666, espacement: 0.6),
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left),
      );

  pw.Widget cellule(pw.Widget contenu) => pw.Padding(
        padding:
            pw.EdgeInsets.symmetric(vertical: _mm(1.9), horizontal: _mm(2)),
        child: contenu,
      );

  pw.Widget celluleTexte(String texte,
          {bool droite = false,
          bool fort = false,
          double taille = 9,
          PdfColor? couleur,
          bool italiques = false}) =>
      cellule(pw.Align(
        alignment: droite ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: _txt(texte,
            style: s(taille, fort: fort, couleur: couleur, italiques: italiques),
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left),
      ));

  /// Un tableau du rapport : filet noir sous l'en-tête, filets clairs entre les
  /// lignes, une ligne sur deux légèrement grisée, et un pied souligné.
  pw.Widget tableau({
    required Map<int, pw.TableColumnWidth> largeurs,
    required List<pw.Widget> entetes,
    required List<List<pw.Widget>> lignes,
    List<pw.Widget>? pied,
    List<bool>? alerte,
  }) =>
      pw.Table(
        columnWidths: largeurs,
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: _n111, width: 0.75))),
            children: entetes,
          ),
          for (var i = 0; i < lignes.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: (alerte != null && alerte[i])
                    ? _alerteFond
                    : (i.isOdd ? _nfb : null),
                border: const pw.Border(
                    bottom: pw.BorderSide(color: _neee, width: 0.375)),
              ),
              children: lignes[i],
            ),
          if (pied != null)
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                  border:
                      pw.Border(top: pw.BorderSide(color: _n111, width: 0.75))),
              children: pied,
            ),
        ],
      );
}

// ─── Graphique ────────────────────────────────────────────────────────────────

/// Histogramme du chiffre d'affaires avec la courbe des encaissements
/// par-dessus. Les deux sont volontairement sur le même graphique : c'est là
/// que se voit l'écart entre ce qui a été vendu et ce qui a été encaissé,
/// l'écart qui vide une caisse sans qu'on comprenne pourquoi.
///
/// Le tracé est fait à la main sur la toile du PDF, comme le SVG écrit à la
/// main du gabarit web : aucune bibliothèque de graphiques, aucune ressource
/// externe.
class _Graphique extends pw.StatelessWidget {
  final List<PointSerie> serie;
  final PdfColor accent;
  final _Gabarit g;

  _Graphique(this.serie, this.accent, this.g);

  // Le repère du gabarit web, en unités de son viewBox 940 × 260.
  static const _l = 940.0, _h = 260.0;
  static const _mgHaut = 16.0, _mgBas = 34.0, _mgGauche = 58.0, _mgDroite = 14.0;

  @override
  pw.Widget build(pw.Context context) {
    if (serie.isEmpty) return pw.SizedBox();

    var maximum = 1;
    for (final p in serie) {
      maximum = math.max(maximum, math.max(p.chiffreAffaires, p.encaissements));
    }
    // Un plafond « rond » : l'axe se lit mieux gradué sur 4 lignes régulières.
    final ordre = math.pow(10, (math.log(maximum) / math.ln10).floor()).toDouble();
    final plafond = (maximum / ordre).ceil() * ordre;

    // Au-delà de 24 points, une étiquette sur deux : sinon elles se chevauchent.
    final saut = serie.length > 24 ? (serie.length / 20).ceil() : 1;

    return pw.Container(
      decoration: g.carteBord,
      padding: pw.EdgeInsets.all(_mm(4)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.AspectRatio(
            aspectRatio: _l / _h,
            child: pw.LayoutBuilder(builder: (context, constraints) {
              final k = (constraints?.maxWidth ?? _l) / _l;
              const l = _l - _mgGauche - _mgDroite;
              const h = _h - _mgHaut - _mgBas;
              double y(num v) => _mgHaut + h - (v / plafond) * h;
              final pasX = l / serie.length;
              final largeurBarre = math.max(3.0, math.min(38.0, pasX * 0.56));
              double cx(int i) => _mgGauche + i * pasX + pasX / 2;

              return pw.Stack(children: [
                pw.CustomPaint(
                  size: PdfPoint(_l * k, _h * k),
                  painter: (canvas, taille) {
                    // La toile du PDF a son origine en bas à gauche ; le repère
                    // du gabarit web descend depuis le haut. On convertit ici,
                    // une seule fois, plutôt que dans chaque tracé.
                    double px(double x) => x * k;
                    double py(double yy) => taille.y - yy * k;

                    for (final f in [0.0, 0.25, 0.5, 0.75, 1.0]) {
                      final vy = _mgHaut + h - f * h;
                      canvas
                        ..setStrokeColor(f == 0 ? const PdfColor.fromInt(0xff333333) : _ne5)
                        ..setLineWidth((f == 0 ? 1 : 0.6) * k)
                        ..drawLine(px(_mgGauche), py(vy), px(_l - _mgDroite), py(vy))
                        ..strokePath();
                    }

                    canvas.setFillColor(accent);
                    for (var i = 0; i < serie.length; i++) {
                      final haut = y(serie[i].chiffreAffaires);
                      final hb = math.max(0.0, _mgHaut + h - haut);
                      if (hb <= 0) continue;
                      canvas.drawRect(px(cx(i) - largeurBarre / 2), py(haut + hb),
                          px(largeurBarre), hb * k);
                    }
                    canvas.fillPath();

                    if (serie.length > 1) {
                      canvas
                        ..setStrokeColor(_vert)
                        ..setLineWidth(1.8 * k)
                        ..setLineJoin(PdfLineJoin.round)
                        ..moveTo(px(cx(0)), py(y(serie[0].encaissements)));
                      for (var i = 1; i < serie.length; i++) {
                        canvas.lineTo(px(cx(i)), py(y(serie[i].encaissements)));
                      }
                      canvas.strokePath();
                    }

                    canvas.setFillColor(_vert);
                    for (var i = 0; i < serie.length; i++) {
                      canvas.drawEllipse(px(cx(i)), py(y(serie[i].encaissements)),
                          2.2 * k, 2.2 * k);
                    }
                    canvas.fillPath();
                  },
                ),
                // Les étiquettes sont posées par-dessus en widgets de texte :
                // la toile ne sait pas mesurer une chaîne, et un axe mal aligné
                // se voit immédiatement.
                for (final f in [0.0, 0.25, 0.5, 0.75, 1.0])
                  pw.Positioned(
                    left: 0,
                    top: (_mgHaut + h - f * h - 6) * k,
                    child: pw.SizedBox(
                      width: (_mgGauche - 7) * k,
                      child: _txt(_compact(plafond * f),
                          style: g.s(9 * k / 0.75 * 0.75, couleur: _n666),
                          textAlign: pw.TextAlign.right),
                    ),
                  ),
                for (var i = 0; i < serie.length; i++)
                  if (i % saut == 0)
                    pw.Positioned(
                      left: (cx(i) - pasX / 2) * k,
                      top: (_h - 24) * k,
                      child: pw.SizedBox(
                        width: pasX * k,
                        child: _txt(serie[i].label,
                            style: g.s(9 * k, couleur: _n555),
                            textAlign: pw.TextAlign.center),
                      ),
                    ),
              ]);
            }),
          ),
          pw.SizedBox(height: _mm(2)),
          pw.Row(children: [
            _legende(accent, 'Chiffre d\'affaires (ventes enregistrées)'),
            pw.SizedBox(width: _mm(8)),
            _legende(_vert, 'Encaissements (argent réellement reçu)', ligne: true),
          ]),
        ],
      ),
    );
  }

  pw.Widget _legende(PdfColor couleur, String texte, {bool ligne = false}) =>
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Container(
          width: ligne ? _mm(4) : _mm(2.6),
          height: ligne ? _mm(1.2) : _mm(2.6),
          decoration: pw.BoxDecoration(
              color: couleur,
              borderRadius: pw.BorderRadius.circular(_mm(ligne ? 1 : 0.5))),
        ),
        pw.SizedBox(width: _mm(1.6)),
        _txt(texte, style: g.s(8, couleur: _n555)),
      ]);
}

// ─── Document ─────────────────────────────────────────────────────────────────

Future<Uint8List> genererRapportPdf(
    RapportComplet r, Entreprise? entreprise) async {
  final ent = entreprise ?? Entreprise();
  final g = _Gabarit(r, ent);
  final b = r.bilan;
  final devise = g.devise;
  final accent = g.accent;

  final nomEnt = ent.nom.trim();
  // Un rapport sans raison sociale n'a aucune valeur : plutôt qu'un en-tête vide
  // qui passerait inaperçu, on le signale sur le document lui-même. Le gabarit
  // web ouvre par « ⚠ », absent du jeu WinAnsi des polices PDF standard.
  final nomAffiche = nomEnt.isEmpty ? '(!) Nom de l\'entreprise à renseigner' : nomEnt;
  final logo = _imageDepuisChamp(ent.logo);

  // ── Couverture ────────────────────────────────────────────────────────────
  final sommaire = [
    ('01', 'Synthèse — résultat et trésorerie de la période'),
    ('02', 'Évolution — ventes et encaissements dans le temps'),
    ('03', 'Ventes — articles, clients, détail des opérations'),
    ('04', 'Encaissements et impayés'),
    ('05', 'Dépenses par catégorie et détail'),
    ('06', 'Stock et mouvements'),
    ('07', 'Méthode de calcul'),
  ];

  pw.Widget colonneSommaire(Iterable<(String, String)> items) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final it in items)
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(vertical: _mm(1.4)),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                        width: _mm(7),
                        child: _txt(it.$1,
                            style: g.s(9.5, fort: true, couleur: _n999))),
                    pw.Expanded(child: _txt(it.$2, style: g.s(9.5))),
                  ],
                ),
              ),
          ],
        ),
      );

  final couverture = pw.SizedBox(
    height: _mm(262),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Le bandeau d'accent en tête de couverture.
        pw.Container(
          height: _mm(4),
          decoration: pw.BoxDecoration(
              color: accent, borderRadius: pw.BorderRadius.circular(_mm(1))),
        ),
        pw.Container(
          margin: pw.EdgeInsets.only(top: _mm(8)),
          padding: pw.EdgeInsets.only(bottom: _mm(7)),
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _n111, width: 0.75))),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: _mm(34),
                child: logo != null
                    ? pw.Image(logo, height: _mm(30), fit: pw.BoxFit.contain)
                    : pw.Container(
                        width: _mm(24),
                        height: _mm(24),
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: _nbbb, width: 0.75)),
                        child: _txt(
                            (nomEnt.isEmpty ? '?' : nomEnt.substring(0, 1))
                                .toUpperCase(),
                            style: g.s(34, fort: true, couleur: _n666)),
                      ),
              ),
              pw.SizedBox(width: _px(14)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _txt(nomAffiche,
                        style: g.s(17, fort: true, espacement: -0.2)),
                    if (ent.slogan.trim().isNotEmpty)
                      _txt(ent.slogan,
                          style: g.s(10, couleur: _n444, italiques: true)),
                    for (final ligne in [
                      joindreNonVides([ent.adresse, ent.quartier, ent.ville], ', '),
                      joindreNonVides([ent.telephone, ent.email]),
                      joindreNonVides([
                        ent.rccm.trim().isEmpty ? null : 'RCCM ${ent.rccm}',
                        ent.nif.trim().isEmpty ? null : 'NIF ${ent.nif}',
                      ]),
                    ])
                      if (ligne.isNotEmpty)
                        pw.Padding(
                          padding: pw.EdgeInsets.only(top: _px(2)),
                          child: _txt(ligne, style: g.s(9, couleur: _n444)),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),

        pw.Padding(
          padding: pw.EdgeInsets.only(top: _mm(22), bottom: _mm(14)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _txt('RAPPORT D\'ACTIVITÉ',
                  style: g.s(10, fort: true, couleur: _n666, espacement: 3.4)),
              pw.SizedBox(height: _px(5)),
              _txt(r.choix.libelle,
                  style: g.s(36, fort: true, espacement: -1, hauteurLigne: 1.08)),
              pw.SizedBox(height: _px(7)),
              _txt(
                  'Du ${fmtDateNum(r.choix.periode.debut)} au ${fmtDateNum(r.choix.periode.fin)} · montants en $devise',
                  style: g.s(11, couleur: _n444)),
            ],
          ),
        ),

        g.rangeeEgale([
          g.kpi(
              'Chiffre d\'affaires',
              numFRPdf(b.chiffreAffaires),
              '${b.nbVentes} ${_pluriel(b.nbVentes, 'vente')} ${_pluriel(b.nbVentes, 'enregistrée')}',
              accent),
          r.voitPrixAchat
              ? g.kpi(
                  'Résultat d\'exploitation',
                  _signe(b.resultatExploitation),
                  b.resultatExploitation >= 0
                      ? 'Bénéfice de la période'
                      : 'Perte de la période',
                  b.resultatExploitation >= 0 ? _vert : _rouge)
              : g.kpi('Encaissements', numFRPdf(b.encaissements),
                  'Versements clients reçus', _vert),
          g.kpi(
              'Flux de trésorerie',
              _signe(b.fluxTresorerie),
              b.fluxTresorerie >= 0
                  ? 'La caisse s\'est remplie'
                  : 'La caisse s\'est vidée',
              b.fluxTresorerie >= 0 ? _vert : _rouge),
          g.kpi(
              'Créances clients',
              numFRPdf(b.creancesClients),
              '${r.impayes.length} ${_pluriel(r.impayes.length, 'facture')} non ${_pluriel(r.impayes.length, 'soldée')}',
              b.creancesClients > 0 ? _rouge : null),
        ]),

        pw.Container(
          margin: pw.EdgeInsets.only(top: _mm(14)),
          padding: pw.EdgeInsets.only(top: _mm(5)),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _nddd, width: 0.75))),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _txt('CE QUE CONTIENT CE RAPPORT',
                  style: g.s(8, fort: true, couleur: _n777, espacement: 1.6)),
              pw.SizedBox(height: _mm(3)),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  colonneSommaire(sommaire.take(4)),
                  pw.SizedBox(width: _mm(10)),
                  colonneSommaire(sommaire.skip(4)),
                ],
              ),
            ],
          ),
        ),

        pw.Spacer(),
        pw.Container(
          padding: pw.EdgeInsets.only(top: _mm(6)),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _neee, width: 0.75))),
          child: _txt(
            'Édité le ${_fmtDateLongue(r.genereLe)} à ${_fmtHeure(r.genereLe)}'
            '${r.generePar.trim().isEmpty ? '' : ' par ${r.generePar}'}. '
            'Document établi à partir des seules opérations saisies dans l\'application '
            '— aucune projection, aucune estimation d\'activité.',
            style: g.s(8, couleur: _n777, hauteurLigne: 1.5),
          ),
        ),
      ],
    ),
  );

  // ── 01 Synthèse ───────────────────────────────────────────────────────────
  final synthese = <pw.Widget>[
    g.teteSection('01', 'Synthèse de la période',
        'Deux lectures de l\'argent qui ne s\'additionnent jamais : ce que le commerce gagne, et ce qu\'il y a dans la caisse.'),
    pw.Container(
      margin: pw.EdgeInsets.only(bottom: _mm(4)),
      child: g.rangeeEgale([
          if (r.voitPrixAchat)
            g.carte('Résultat',
                'Ce que le commerce gagne, que les clients aient payé ou non.', [
              g.ligneCompte('Chiffre d\'affaires', b.chiffreAffaires,
                  couleur: _vert,
                  aide:
                      '${b.nbVentes} ${_pluriel(b.nbVentes, 'vente')} · net de remises'),
              g.ligneCompte(
                  'Coût d\'achat des marchandises vendues', -b.coutMarchandises,
                  signeMoins: true,
                  retrait: true,
                  aide: 'Estimé au prix d\'achat actuel des articles'),
              g.ligneCompte('Marge brute', b.margeBrute,
                  total: true,
                  couleur: b.margeBrute >= 0 ? _vert : _rouge,
                  aide: b.tauxMarge == null
                      ? null
                      : '${_pct(b.tauxMarge!)} du chiffre d\'affaires'),
              g.ligneCompte('Charges d\'exploitation', -b.chargesExploitation,
                  signeMoins: true,
                  retrait: true,
                  aide: 'Loyer, salaires, transport, taxes… engagés'),
              g.ligneCompte('Résultat d\'exploitation', b.resultatExploitation,
                  total: true,
                  couleur: b.resultatExploitation >= 0 ? _vert : _rouge,
                  aide: b.resultatExploitation >= 0
                      ? 'Bénéfice de la période'
                      : 'Perte de la période'),
            ])
          else
            g.carte('Résultat non communiqué',
                'Ce compte n\'a pas accès aux prix d\'achat.', [
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(vertical: _mm(2)),
                child: _txt(
                    'Le calcul du résultat repose sur les prix d\'achat, que ce compte ne voit pas. '
                    'Les faire figurer dans un document imprimé reviendrait à les publier. La trésorerie, '
                    'les dépenses et les créances restent complètes ci-contre.',
                    style: g.s(8, couleur: _n666, hauteurLigne: 1.5)),
              ),
            ]),
          g.carte('Trésorerie',
              'L\'argent qui a réellement bougé, quelle que soit la date des pièces.', [
            g.ligneCompte('Encaissements clients', b.encaissements,
                couleur: _vert,
                aide:
                    'Versements reçus pendant la période, y compris sur des ventes plus anciennes'),
            g.ligneCompte('Règlements versés', -b.decaissements,
                signeMoins: true,
                retrait: true,
                aide:
                    'Charges, achats de marchandise et investissements confondus'),
            g.ligneCompte('Flux de trésorerie', b.fluxTresorerie,
                total: true, couleur: b.fluxTresorerie >= 0 ? _vert : _rouge),
            pw.Container(
              margin: pw.EdgeInsets.only(top: _mm(3)),
              padding: pw.EdgeInsets.only(top: _mm(3)),
              decoration: const pw.BoxDecoration(
                  border:
                      pw.Border(top: pw.BorderSide(color: _neee, width: 0.45))),
              child: g.rangeeEgale([
                _miniCase(g, 'Achats de marchandise', numFRPdf(b.achatsMarchandises),
                    'engagés · hors résultat',
                    PdfColor.fromInt(couleurNature['marchandise']!)),
                _miniCase(g, 'Investissements', numFRPdf(b.investissements),
                    'engagés · hors résultat',
                    PdfColor.fromInt(couleurNature['investissement']!)),
              ], gap: 3),
            ),
          ]),
      ]),
    ),
    g.trio([
      g.trioCase('Clients qui vous doivent', numFRPdf(b.creancesClients),
          'Factures non soldées au ${fmtDateNum(r.choix.periode.fin)}',
          couleur: _rouge),
      g.trioCase('Ce que vous devez', numFRPdf(b.dettesFournisseurs),
          'Dépenses saisies et non encore réglées',
          couleur: _ambre),
      g.trioCase('Position nette', _signe(b.positionNette),
          'Créances - dettes, hors caisse',
          couleur: b.positionNette >= 0 ? _vert : _rouge),
    ]),
    g.trio([
      g.trioCase('Panier moyen',
          r.panierMoyen == null ? '—' : numFRPdf(r.panierMoyen!),
          'Chiffre d\'affaires ÷ nombre de ventes'),
      g.trioCase('Clients servis', numFRPdf(r.nbClientsServis),
          'Clients distincts sur la période'),
      g.trioCase('Factures émises', numFRPdf(r.facturesEmises),
          '${numFRPdf(r.montantFacture)} $devise facturés'),
    ]),
  ];

  // ── 02 Évolution ──────────────────────────────────────────────────────────
  final evolution = <pw.Widget>[
    g.teteSection(
        '02',
        'Évolution',
        r.pasSerie == 'jour'
            ? 'Jour par jour sur la période.'
            : 'Mois par mois sur la période.'),
    if (r.serie.isEmpty)
      g.vide('Période trop courte pour un graphique.')
    else ...[
      _Graphique(r.serie, accent, g),
      g.noteInline(
          'L\'écart entre les barres et la courbe est ce qui reste dehors : de la marchandise '
          'livrée dont l\'argent n\'est pas encore rentré. C\'est cet écart, et non le chiffre '
          'd\'affaires, qui explique une caisse vide un mois où l\'on a beaucoup vendu.'),
    ],
  ];

  // ── 03 Ventes ─────────────────────────────────────────────────────────────
  final articlesAffiches = r.articlesVendus.take(25).toList();
  final ventes = <pw.Widget>[
    g.teteSection(
        '03',
        'Ventes',
        '${b.nbVentes} ${_pluriel(b.nbVentes, 'vente')} · ${numFRPdf(b.chiffreAffaires)} $devise · '
            '${r.nbClientsServis} ${_pluriel(r.nbClientsServis, 'client')} ${_pluriel(r.nbClientsServis, 'servi')}'),
    g.sousTitre('Articles vendus'),
    if (articlesAffiches.isEmpty)
      g.vide('Aucune vente sur la période.')
    else ...[
      g.tableau(
        largeurs: {
          0: pw.FixedColumnWidth(_mm(6)),
          1: const pw.FlexColumnWidth(3.2),
          2: const pw.FlexColumnWidth(1.6),
          3: const pw.FlexColumnWidth(1.3),
          4: const pw.FlexColumnWidth(1.7),
          if (r.voitPrixAchat) 5: const pw.FlexColumnWidth(1.7),
          (r.voitPrixAchat ? 6 : 5): const pw.FlexColumnWidth(1.7),
        },
        entetes: [
          g.celluleEntete('#'),
          g.celluleEntete('Article'),
          g.celluleEntete('Catégorie'),
          g.celluleEntete('Quantité', droite: true),
          g.celluleEntete('Chiffre d\'affaires', droite: true),
          if (r.voitPrixAchat) g.celluleEntete('Marge estimée', droite: true),
          g.celluleEntete('Part', droite: true),
        ],
        lignes: [
          for (var i = 0; i < articlesAffiches.length; i++)
            () {
              final a = articlesAffiches[i];
              final part = b.chiffreAffaires > 0
                  ? a.chiffreAffaires / b.chiffreAffaires * 100
                  : 0.0;
              return [
                g.celluleTexte('${i + 1}', taille: 8, couleur: _naaa),
                g.cellule(pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _txt(_tronquer(a.nom, 42), style: g.s(9, fort: true)),
                    if (a.ref.isNotEmpty)
                      _txt(a.ref,
                          style: g.s(7.5, couleur: _n888, italiques: true)),
                  ],
                )),
                g.celluleTexte(a.categorie, taille: 8, couleur: _n666),
                g.cellule(pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _txt(numFRPdf(a.qte), style: g.s(9)),
                    if (a.unite.isNotEmpty) ...[
                      pw.SizedBox(width: _px(3)),
                      _txt(a.unite, style: g.s(7.5, couleur: _n999)),
                    ],
                  ],
                )),
                g.celluleTexte(numFRPdf(a.chiffreAffaires),
                    droite: true, fort: true),
                if (r.voitPrixAchat)
                  g.celluleTexte(_signe(a.marge ?? 0),
                      droite: true,
                      couleur: (a.marge ?? 0) >= 0 ? _vert : _rouge),
                g.cellule(g.cellulePart(part, accent)),
              ];
            }(),
        ],
      ),
      if (r.articlesVendus.length > 25)
        g.reste(
            '+ ${r.articlesVendus.length - 25} autre${r.articlesVendus.length - 25 > 1 ? 's' : ''} '
            'référence${r.articlesVendus.length - 25 > 1 ? 's' : ''}, comprises dans les totaux.'),
    ],
    if (r.clients.isNotEmpty) ...[
      g.sousTitre('Clients de la période'),
      g.tableau(
        largeurs: {
          0: pw.FixedColumnWidth(_mm(6)),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1),
          4: const pw.FlexColumnWidth(1.8),
          5: const pw.FlexColumnWidth(2.2),
        },
        entetes: [
          g.celluleEntete('#'),
          g.celluleEntete('Client'),
          g.celluleEntete('Type'),
          g.celluleEntete('Ventes', droite: true),
          g.celluleEntete('Chiffre d\'affaires', droite: true),
          g.celluleEntete('Reste dû (tout historique)', droite: true),
        ],
        lignes: [
          for (var i = 0; i < r.clients.take(20).length; i++)
            () {
              final c = r.clients[i];
              return [
                g.celluleTexte('${i + 1}', taille: 8, couleur: _naaa),
                g.celluleTexte(_tronquer(c.nom, 40), fort: true),
                g.celluleTexte(c.type, taille: 8, couleur: _n666),
                g.celluleTexte(numFRPdf(c.nbVentes), droite: true),
                g.celluleTexte(numFRPdf(c.chiffreAffaires),
                    droite: true, fort: true),
                g.celluleTexte(c.resteDu > 0 ? numFRPdf(c.resteDu) : '—',
                    droite: true, couleur: c.resteDu > 0 ? _rouge : null),
              ];
            }(),
        ],
      ),
      if (r.clients.length > 20)
        g.reste(
            '+ ${r.clients.length - 20} autre${r.clients.length - 20 > 1 ? 's' : ''} '
            'client${r.clients.length - 20 > 1 ? 's' : ''}.'),
    ],
    if (r.ventes.isNotEmpty) ...[
      g.sousTitre('Détail des ventes'),
      g.tableau(
        largeurs: {
          0: const pw.FlexColumnWidth(1.8),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(2.6),
          3: const pw.FlexColumnWidth(1.8),
          4: const pw.FlexColumnWidth(0.9),
          5: const pw.FlexColumnWidth(1.7),
          6: const pw.FlexColumnWidth(1.5),
        },
        entetes: [
          g.celluleEntete('N°'),
          g.celluleEntete('Date'),
          g.celluleEntete('Client'),
          g.celluleEntete('Vendeur'),
          g.celluleEntete('Lignes', droite: true),
          g.celluleEntete('Montant', droite: true),
          g.celluleEntete('Reste dû', droite: true),
        ],
        lignes: [
          for (final v in r.ventes.take(120))
            [
              g.celluleTexte(v.numero, taille: 8, couleur: _n555),
              g.celluleTexte(fmtDateNum(v.date), taille: 8, couleur: _n666),
              g.celluleTexte(_tronquer(v.client, 34)),
              g.celluleTexte(_tronquer(v.vendeur, 22), taille: 8, couleur: _n666),
              g.celluleTexte('${v.nbLignes}',
                  droite: true, taille: 8, couleur: _n666),
              g.celluleTexte(numFRPdf(v.total), droite: true, fort: true),
              g.celluleTexte(v.resteDu > 0 ? numFRPdf(v.resteDu) : 'soldée',
                  droite: true, couleur: v.resteDu > 0 ? _rouge : null),
            ],
        ],
        pied: [
          g.celluleTexte('Total des ventes de la période', fort: true),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.celluleTexte(numFRPdf(b.chiffreAffaires), droite: true, fort: true),
          g.cellule(pw.SizedBox()),
        ],
      ),
      if (r.ventes.length > 120)
        g.reste(
            'Seules les 120 premières ventes sont détaillées ; le total ci-dessus '
            'porte sur les ${r.ventes.length} ventes de la période.'),
    ],
  ];

  // ── 04 Encaissements et impayés ───────────────────────────────────────────
  final totalMode = r.encaissementsParMode.fold<int>(0, (s, m) => s + m.montant);
  final impayesAffiches = r.impayes.take(60).toList();
  final encaissements = <pw.Widget>[
    g.teteSection('04', 'Encaissements et impayés',
        '${numFRPdf(b.encaissements)} $devise encaissés · ${numFRPdf(b.creancesClients)} $devise encore dus'),
    g.sousTitre('Répartition des encaissements'),
    if (r.encaissementsParMode.isEmpty)
      g.vide('Aucun versement reçu sur la période.')
    else
      g.tableau(
        largeurs: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2),
        },
        entetes: [
          g.celluleEntete('Mode de règlement'),
          g.celluleEntete('Nombre', droite: true),
          g.celluleEntete('Montant', droite: true),
          g.celluleEntete('Part', droite: true),
        ],
        lignes: [
          for (final m in r.encaissementsParMode)
            [
              g.celluleTexte(m.mode, fort: true),
              g.celluleTexte(numFRPdf(m.nombre), droite: true),
              g.celluleTexte(numFRPdf(m.montant),
                  droite: true, fort: true, couleur: _vert),
              g.cellule(g.cellulePart(
                  totalMode > 0 ? m.montant / totalMode * 100 : 0, _vert)),
            ],
        ],
        pied: [
          g.celluleTexte('Total encaissé', fort: true),
          g.celluleTexte(
              numFRPdf(r.encaissementsParMode.fold<int>(0, (s, m) => s + m.nombre)),
              droite: true,
              fort: true),
          g.celluleTexte(numFRPdf(totalMode), droite: true, fort: true),
          g.cellule(pw.SizedBox()),
        ],
      ),
    if (r.impayes.isEmpty) ...[
      g.sousTitre('Impayés'),
      g.vide(
          'Aucune facture en attente de règlement au ${fmtDateNum(r.choix.periode.fin)}. Tout est soldé.',
          bon: true),
    ] else ...[
      g.sousTitre(
          'Factures non soldées au ${fmtDateNum(r.choix.periode.fin)}'),
      g.tableau(
        largeurs: {
          0: const pw.FlexColumnWidth(1.6),
          1: const pw.FlexColumnWidth(2.4),
          2: const pw.FlexColumnWidth(1.2),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FlexColumnWidth(1.5),
          6: const pw.FlexColumnWidth(1.5),
          7: const pw.FlexColumnWidth(1),
        },
        entetes: [
          g.celluleEntete('N°'),
          g.celluleEntete('Client'),
          g.celluleEntete('Émise'),
          g.celluleEntete('Échéance'),
          g.celluleEntete('Montant', droite: true),
          g.celluleEntete('Versé', droite: true),
          g.celluleEntete('Reste dû', droite: true),
          g.celluleEntete('Retard', droite: true),
        ],
        alerte: [for (final f in impayesAffiches) f.joursRetard > 0],
        lignes: [
          for (final f in impayesAffiches)
            [
              g.celluleTexte(f.numero, taille: 8, couleur: _n555),
              g.celluleTexte(_tronquer(f.client, 30)),
              g.celluleTexte(fmtDateNum(f.dateEmission),
                  taille: 8, couleur: _n666),
              g.celluleTexte(fmtDateNum(f.dateEcheance),
                  taille: 8, couleur: _n666),
              g.celluleTexte(numFRPdf(f.montant), droite: true),
              g.celluleTexte(numFRPdf(f.paye), droite: true),
              g.celluleTexte(numFRPdf(f.reste),
                  droite: true, fort: true, couleur: _rouge),
              g.celluleTexte(f.joursRetard > 0 ? '${f.joursRetard} j' : '—',
                  droite: true, taille: 8, couleur: _n666),
            ],
        ],
        pied: [
          g.celluleTexte('Total encore dû par les clients', fort: true),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.celluleTexte(numFRPdf(b.creancesClients),
              droite: true, fort: true, couleur: _rouge),
          g.cellule(pw.SizedBox()),
        ],
      ),
      if (r.impayes.length > 60)
        g.reste(
            '+ ${r.impayes.length - 60} autre${r.impayes.length - 60 > 1 ? 's' : ''} '
            'facture${r.impayes.length - 60 > 1 ? 's' : ''} non '
            'soldée${r.impayes.length - 60 > 1 ? 's' : ''} ; le total porte sur toutes.'),
      g.noteInline(
          'Cette liste n\'est pas limitée à la période : une créance de l\'an dernier est toujours '
          'une créance aujourd\'hui. Ne montrer que les impayés du mois ferait disparaître les plus '
          'anciens — précisément ceux qu\'il faut relancer.'),
    ],
  ];

  // ── 05 Dépenses ───────────────────────────────────────────────────────────
  final totalEngage = b.parCategorie.fold<int>(0, (s, l) => s + l.engage);
  final depenses = <pw.Widget>[
    g.teteSection(
        '05',
        'Dépenses',
        '${b.nbDepenses} ${_pluriel(b.nbDepenses, 'dépense')} ${_pluriel(b.nbDepenses, 'engagée')} · '
            '${numFRPdf(b.decaissements)} $devise réellement sortis de la caisse'),
    g.sousTitre('Par catégorie'),
    if (b.parCategorie.isEmpty)
      g.vide('Aucune dépense saisie sur la période.')
    else ...[
      g.tableau(
        largeurs: {
          0: const pw.FlexColumnWidth(2.4),
          1: const pw.FlexColumnWidth(2.2),
          2: const pw.FlexColumnWidth(0.9),
          3: const pw.FlexColumnWidth(1.6),
          4: const pw.FlexColumnWidth(1.6),
          5: const pw.FlexColumnWidth(2),
        },
        entetes: [
          g.celluleEntete('Catégorie'),
          g.celluleEntete('Nature comptable'),
          g.celluleEntete('Lignes', droite: true),
          g.celluleEntete('Engagé', droite: true),
          g.celluleEntete('Décaissé', droite: true),
          g.celluleEntete('Part', droite: true),
        ],
        lignes: [
          for (final l in b.parCategorie)
            [
              g.celluleTexte(l.categorie, fort: true),
              g.cellule(pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: g.pastille(libelleNature[l.nature] ?? l.nature,
                    PdfColor.fromInt(couleurNature[l.nature] ?? 0xffE85D04)),
              )),
              g.celluleTexte(numFRPdf(l.nombre),
                  droite: true, taille: 8, couleur: _n666),
              g.celluleTexte(numFRPdf(l.engage), droite: true, fort: true),
              g.celluleTexte(numFRPdf(l.decaisse), droite: true, couleur: _vert),
              g.cellule(g.cellulePart(
                  totalEngage > 0 ? l.engage / totalEngage * 100 : 0,
                  PdfColor.fromInt(couleurNature[l.nature] ?? 0xffE85D04))),
            ],
        ],
        pied: [
          g.celluleTexte('Total', fort: true),
          g.cellule(pw.SizedBox()),
          g.cellule(pw.SizedBox()),
          g.celluleTexte(numFRPdf(totalEngage), droite: true, fort: true),
          g.celluleTexte(
              numFRPdf(b.parCategorie.fold<int>(0, (s, l) => s + l.decaisse)),
              droite: true,
              fort: true),
          g.cellule(pw.SizedBox()),
        ],
      ),
      g.noteInline(
          '« Engagé » : ce qui a été saisi sur la période. « Décaissé » : ce qui est réellement '
          'sorti de la caisse. Les deux diffèrent dès qu\'une dépense est réglée en plusieurs fois '
          'ou plus tard.'),
    ],
    if (r.depenses.isNotEmpty) ...[
      g.sousTitre('Détail des dépenses engagées'),
      g.tableau(
        largeurs: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(3),
          3: const pw.FlexColumnWidth(1.8),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FlexColumnWidth(1.5),
          6: const pw.FlexColumnWidth(1.4),
        },
        entetes: [
          g.celluleEntete('N°'),
          g.celluleEntete('Date'),
          g.celluleEntete('Libellé'),
          g.celluleEntete('Bénéficiaire'),
          g.celluleEntete('Montant', droite: true),
          g.celluleEntete('Réglé', droite: true),
          g.celluleEntete('Reste', droite: true),
        ],
        lignes: [
          for (final d in r.depenses.take(120))
            [
              g.celluleTexte(d.numero, taille: 8, couleur: _n555),
              g.celluleTexte(fmtDateNum(d.date), taille: 8, couleur: _n666),
              g.cellule(pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _txt(_tronquer(d.libelle, 36), style: g.s(9, fort: true)),
                  _txt(d.categorie,
                      style: g.s(7.5, couleur: _n888, italiques: true)),
                ],
              )),
              g.celluleTexte(_tronquer(d.beneficiaire, 24),
                  taille: 8, couleur: _n666),
              g.celluleTexte(numFRPdf(d.montant), droite: true, fort: true),
              g.celluleTexte(numFRPdf(d.regle), droite: true, couleur: _vert),
              g.celluleTexte(d.reste > 0 ? numFRPdf(d.reste) : 'réglée',
                  droite: true, couleur: d.reste > 0 ? _rouge : null),
            ],
        ],
      ),
      if (r.depenses.length > 120)
        g.reste(
            'Seules les 120 premières dépenses sont détaillées ; les totaux portent '
            'sur les ${r.depenses.length} de la période.'),
    ],
  ];

  // ── 06 Stock ──────────────────────────────────────────────────────────────
  final st = r.stock;
  final alertes = [...st.ruptures, ...st.faibles];
  final alertesAffichees = alertes.take(40).toList();
  final stock = <pw.Widget>[
    g.teteSection(
        '06',
        'Stock et mouvements',
        '${numFRPdf(st.nbReferences)} ${_pluriel(st.nbReferences, 'référence')} au catalogue · '
            '${numFRPdf(st.nbMouvements)} ${_pluriel(st.nbMouvements, 'mouvement')} sur la période'),
    g.trio([
      st.valeurAchat != null
          ? g.trioCase('Valeur du stock (prix d\'achat)', numFRPdf(st.valeurAchat!),
              'État du jour d\'édition')
          : g.trioCase('Valeur du stock', '—',
              'Prix d\'achat non accessibles à ce compte'),
      g.trioCase('Valeur au prix de vente', numFRPdf(st.valeurVente),
          'État du jour d\'édition'),
      g.trioCase('Mouvements de la période',
          '+${numFRPdf(st.entrees)} / -${numFRPdf(st.sorties)}',
          'Entrées et sorties, toutes références'),
    ]),
    g.noteInline(
        'Le stock n\'est pas historisé : l\'application ne peut pas dire ce qu\'il contenait '
        'un jour donné du passé. Les deux valeurs ci-dessus sont donc celles du '
        '${fmtDateNum(r.genereLe.toIso8601String())}, jour d\'édition du rapport, et non celles '
        'de la fin de période. Les mouvements, eux, sont bien ceux de la période.'),
    g.sousTitre('Articles à réapprovisionner'),
    if (alertesAffichees.isEmpty)
      g.vide('Aucune rupture, aucun seuil d\'alerte franchi. Le dépôt est en ordre.',
          bon: true)
    else ...[
      g.tableau(
        largeurs: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(1.8),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1.6),
        },
        entetes: [
          g.celluleEntete('Référence'),
          g.celluleEntete('Article'),
          g.celluleEntete('Catégorie'),
          g.celluleEntete('En stock', droite: true),
          g.celluleEntete('Seuil', droite: true),
          g.celluleEntete('État'),
        ],
        alerte: [for (final a in alertesAffichees) a.stock == 0],
        lignes: [
          for (final a in alertesAffichees)
            [
              g.celluleTexte(a.ref, taille: 8, couleur: _n555),
              g.celluleTexte(_tronquer(a.nom, 40), fort: true),
              g.celluleTexte(a.categorie, taille: 8, couleur: _n666),
              g.celluleTexte(numFRPdf(a.stock),
                  droite: true,
                  fort: true,
                  couleur: a.stock == 0 ? _rouge : _ambre),
              g.celluleTexte(numFRPdf(a.stockMin),
                  droite: true, taille: 8, couleur: _n666),
              g.cellule(pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: g.pastille(a.stock == 0 ? 'Rupture' : 'Stock faible',
                    a.stock == 0 ? _rouge : _ambre),
              )),
            ],
        ],
      ),
      if (alertes.length > 40)
        g.reste(
            '+ ${alertes.length - 40} autre${alertes.length - 40 > 1 ? 's' : ''} '
            'article${alertes.length - 40 > 1 ? 's' : ''} sous le seuil.'),
    ],
  ];

  // ── 07 Méthode ────────────────────────────────────────────────────────────
  final blocsMethode = <(String, String)>[
    (
      'Résultat et trésorerie ne s\'additionnent pas',
      'Le résultat dit si le commerce gagne de l\'argent ; la trésorerie dit ce qu\'il y a dans la caisse. '
          'On peut être bénéficiaire et sans un franc parce que les clients n\'ont pas encore payé. Les mélanger '
          'revient à croire qu\'on gagne de l\'argent le mois où l\'on encaisse une vieille créance, et qu\'on en '
          'perd le mois où l\'on remplit le dépôt.'
    ),
    (
      'Les achats de marchandise ne réduisent pas le résultat',
      'Ils ne sont pas perdus : ils sont dans le dépôt. Leur coût entre dans le résultat le jour de la '
          'vente, par le coût d\'achat des marchandises vendues. Les déduire aussi à l\'achat compterait le même '
          'franc deux fois. Idem pour les investissements : un camion sort de la caisse une fois mais sert des '
          'années. Les deux figurent bien dans la trésorerie.'
    ),
    if (r.voitPrixAchat)
      (
        'La marge est une estimation, et elle est datée',
        'Le prix d\'achat n\'est pas historisé ligne à ligne : la marge est calculée au prix d\'achat '
            'actuel des articles. Si un prix a bougé depuis la vente, la marge bouge avec lui. Une ligne '
            'dont l\'article a été supprimé du catalogue compte pour zéro de coût.'
      ),
    (
      'Rien n\'est inventé',
      'Chaque chiffre remonte à une pièce saisie : une vente, un versement, une dépense, un règlement. '
          'Aucune extrapolation, aucun lissage, aucune projection. Une journée sans activité vaut zéro et '
          's\'affiche comme telle.'
    ),
    (
      'Périmètre des arrêtés',
      'Les créances et les dettes sont arrêtées au ${fmtDateNum(r.choix.periode.fin)} : on ne retient '
          'que les pièces émises jusqu\'à cette date, et l\'on ne déduit que les versements reçus jusqu\'à cette '
          'date. Un règlement encaissé après ne fait pas disparaître rétroactivement la créance.'
    ),
    (
      'TVA',
      'Le magasin ne facture ni ne récupère la TVA : tous les montants de ce rapport sont des montants '
          'réels, sans retraitement fiscal.'
    ),
  ];

  pw.Widget colonneMethode(Iterable<(String, String)> blocs) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final bloc in blocs)
              pw.Padding(
                padding: pw.EdgeInsets.only(bottom: _mm(4.5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _txt(bloc.$1, style: g.s(9.5, fort: true)),
                    pw.SizedBox(height: _mm(1.2)),
                    _txt(bloc.$2,
                        style: g.s(8.5, couleur: _n444, hauteurLigne: 1.55)),
                  ],
                ),
              ),
          ],
        ),
      );

  final moitie = (blocsMethode.length / 2).ceil();
  final methode = <pw.Widget>[
    g.teteSection('07', 'Méthode de calcul',
        'Ce que les chiffres de ce rapport veulent dire exactement — et ce qu\'ils ne disent pas.'),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        colonneMethode(blocsMethode.take(moitie)),
        pw.SizedBox(width: _mm(8)),
        colonneMethode(blocsMethode.skip(moitie)),
      ],
    ),
  ];

  // ── Assemblage ────────────────────────────────────────────────────────────
  final document = pw.Document(
      title: 'Rapport ${r.choix.libelle} — $nomEnt');

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(
          base: g.regulier, bold: g.gras, italic: g.italique),
      margin: pw.EdgeInsets.only(
          top: _mm(11), left: _mm(10), right: _mm(10), bottom: _mm(13)),
      // Le pied revient sur chaque page : c'est ce qui permet de retrouver de
      // quel rapport vient une feuille égarée sur un bureau.
      footer: (_) => pw.Container(
        padding: pw.EdgeInsets.only(top: _px(2.5)),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _nddd, width: 0.375))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: _txt(
                  '$nomEnt — Rapport d\'activité · ${r.choix.libelle}',
                  style: g.s(7.5, couleur: _n888)),
            ),
            _txt(
                'Édité le ${fmtDateNum(r.genereLe.toIso8601String())}'
                '${r.generePar.trim().isEmpty ? '' : ' par ${r.generePar}'}',
                style: g.s(7.5, couleur: _n888)),
          ],
        ),
      ),
      build: (_) => [
        couverture,
        // Chaque section commence en haut d'une page, comme le
        // `page-break-before` du gabarit web. La synthèse fait exception : elle
        // suit la couverture sur sa propre page.
        pw.NewPage(),
        ...synthese,
        pw.NewPage(),
        ...evolution,
        pw.NewPage(),
        ...ventes,
        pw.NewPage(),
        ...encaissements,
        pw.NewPage(),
        ...depenses,
        pw.NewPage(),
        ...stock,
        pw.NewPage(),
        ...methode,
      ],
    ),
  );

  return document.save();
}

/// Les deux petites cases « Achats de marchandise » / « Investissements » du
/// bloc trésorerie.
pw.Widget _miniCase(_Gabarit g, String label, String valeur, String precision,
        PdfColor couleur) =>
    pw.Container(
        padding: pw.EdgeInsets.all(_mm(2.5)),
        decoration: pw.BoxDecoration(
            color: _nfa, borderRadius: pw.BorderRadius.circular(_mm(1.5))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _txt(label.toUpperCase(),
                style: g.s(7, couleur: _n888, fort: true, espacement: 0.8)),
            pw.SizedBox(height: _mm(1)),
            _txt(valeur, style: g.s(12, couleur: couleur)),
            pw.SizedBox(height: _mm(0.5)),
            _txt(precision, style: g.s(7, couleur: _n999)),
          ],
        ),
    );

// ─── Sortie ───────────────────────────────────────────────────────────────────

Future<void> partagerRapportPdf(
    RapportComplet rapport, Entreprise? entreprise) async {
  final bytes = await genererRapportPdf(rapport, entreprise);
  final dir = await getTemporaryDirectory();
  final nom = nomFichierRapport(rapport.choix);
  final fichier = File('${dir.path}/$nom.pdf');
  await fichier.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(fichier.path)],
      text: 'Rapport d\'activité — ${rapport.choix.libelle}');
}

Future<void> imprimerRapportPdf(
    RapportComplet rapport, Entreprise? entreprise) async {
  final bytes = await genererRapportPdf(rapport, entreprise);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: nomFichierRapport(rapport.choix),
  );
}
