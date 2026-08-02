import '../../app/format.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/models/models.dart';

// ─── Facture imprimable ───────────────────────────────────────────────────────
// Transposition fidèle du gabarit de l'application web (`src/lib/print-facture.ts`).
// Les deux applications partagent le même serveur : elles doivent sortir le même
// papier. En-tête sur une ligne (logo à gauche, coordonnées et identifiants
// fiscaux à droite), titre « Facture » centré, bloc numéro/dates aligné à
// droite, tableau sobre en noir et blanc, montant en toutes lettres, cartouche
// de signature, puis le pied à trois colonnes « Payable à / Informations
// Bancaires / Autres détails » et les deux lignes manuscrites « Livré par » et
// « Numéro du réceptionneur ».
//
// Le document ne porte AUCUNE mention de paiement : ni statut, ni versements,
// ni reste à payer. Le magasin appose ses propres cachets sur le papier, et
// c'est cette marque-là qui fait foi.

// ─── Conversion des unités du gabarit web ─────────────────────────────────────
// Le gabarit HTML est coté en pixels CSS (96 ppp) et en millimètres. Le PDF
// travaille en points typographiques (72 ppp). Ces deux fonctions transposent
// les cotes telles quelles, ce qui évite de recalculer chaque valeur à la main
// et de voir les deux documents diverger au premier ajustement.
double _px(double cssPx) => cssPx * 72.0 / 96.0;
double _mm(double millimetres) => millimetres * PdfPageFormat.mm;

/// Interligne supplémentaire correspondant à un `line-height` CSS.
double _interligne(double taille, double hauteurLigne) =>
    taille * (hauteurLigne - 1);

// Teintes du gabarit web.
const _noir = PdfColors.black;
const _gris222 = PdfColor.fromInt(0xff222222);
const _gris333 = PdfColor.fromInt(0xff333333);
const _gris555 = PdfColor.fromInt(0xff555555);
const _gris999 = PdfColor.fromInt(0xff999999);
const _grisCCC = PdfColor.fromInt(0xffcccccc);
const _grisDDD = PdfColor.fromInt(0xffdddddd);
const _grisF2 = PdfColor.fromInt(0xfff2f2f2);

// Valeurs de repli du pied de document (PIED_DOCUMENT côté web).
const _piedBanque = 'UBA (United Bank for Africa)';
const _piedCompte = 'N° 600 210 3000 84 44';
const _piedAutresDetails = 'Entreprise Alpha Solutions SARLU';
const _piedSignataire = 'Diallo Mamadou Alpha';

// ─── Mise en forme ────────────────────────────────────────────────────────────

// ─── Images ───────────────────────────────────────────────────────────────────

/// Décode le logo ou la signature enregistrés dans les paramètres.
///
/// Le champ n'a pas la même forme selon l'application qui l'a rempli : la web
/// enregistre une adresse de données complète (`data:image/png;base64,…`), la
/// version mobile le base64 seul. Les deux écrivent dans le même enregistrement
/// serveur, donc les deux formes doivent être acceptées.
///
/// Un champ vide était la cause du plantage « RangeError (length): Valid value
/// range is empty: 0 » : `base64Decode('')` rend un tableau vide, que le
/// décodeur d'images du paquet `pdf` lit sans vérifier sa longueur. Le champ
/// signature n'étant jamais nul mais souvent vide, le bouton « PDF » échouait
/// dès qu'aucune signature n'avait été téléversée — c'est-à-dire presque
/// toujours. Toute donnée absente ou illisible rend désormais `null`, et le
/// document se génère sans l'image.
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

// ─── Gabarit ──────────────────────────────────────────────────────────────────

/// Les deux documents que le magasin imprime. Ils sortent du même gabarit : sur
/// le papier, le bon de livraison est la facture avec un autre titre et un autre
/// numéro.
enum TypeDocument { facture, bonLivraison }

/// Numéro du bon de livraison, dérivé de celui de la vente : VTE-2026-0377
/// devient BL-2026-0377. Une vente pas encore synchronisée n'a pas de numéro :
/// le bon n'en porte pas non plus.
String numeroBL(Vente? vente) {
  final m = RegExp(r'^VTE-(.+)$').firstMatch(vente?.numero ?? '');
  return m == null ? '' : 'BL-${m.group(1)}';
}

Future<Uint8List> genererFacturePdf(
  Facture facture,
  Vente? vente,
  Client? client,
  Entreprise? entreprise, {
  TypeDocument type = TypeDocument.facture,
}) async {
  // Le gabarit web est composé en Arial/Helvetica. Les polices standard du PDF
  // couvrent le même dessin et sont embarquées dans le lecteur : aucun appel
  // réseau, donc aucun document manquant parce que le magasin est hors ligne.
  final regulier = pw.Font.helvetica();
  final gras = pw.Font.helveticaBold();
  final italique = pw.Font.helveticaOblique();

  final ent = entreprise ?? Entreprise();
  final devise = ent.devise.trim().isEmpty ? 'GNF' : ent.devise.trim();
  final bl = type == TypeDocument.bonLivraison;
  final lignes = (vente?.lignes ?? const <LigneVente>[])
      .where((l) => l.qte > 0)
      .toList();

  // Titre, numéro et référence croisée : le bon renvoie à la facture, la
  // facture renvoie au bon — c'est ce que porte le papier du magasin.
  final titre = bl ? 'Bon de livraison' : 'Facture';
  final numeroDoc = bl ? numeroBL(vente) : facture.numero;
  final prefixeNum = bl ? 'BL N°' : 'Fac N°';
  final refCroisee = bl
      ? (facture.numero.isNotEmpty
          ? 'Fac N°${facture.numero}'
          : (vente?.numero ?? ''))
      : (numeroBL(vente).isNotEmpty ? numeroBL(vente) : (vente?.numero ?? ''));

  // Une facture sans raison sociale n'a aucune valeur commerciale. Plutôt que
  // de produire un en-tête vide qui passerait inaperçu à l'impression, on le
  // signale sur le document lui-même : l'oubli se voit avant l'envoi au client.
  final nomEnt = ent.nom.trim();
  // Le gabarit web ouvre l'avertissement par « ⚠ » ; ce caractère n'existe pas
  // dans le jeu WinAnsi des polices PDF standard et sortirait en blanc.
  final nomAffiche =
      nomEnt.isEmpty ? '(!) Nom de l\'entreprise à renseigner' : nomEnt;

  final logo = _imageDepuisChamp(ent.logo);
  final signature = _imageDepuisChamp(ent.signatureImage);

  final identifiants = joindreNonVides([
    ent.rccm.trim().isEmpty ? null : 'Impôt Id : ${ent.rccm}',
    ent.nif.trim().isEmpty ? null : 'NIF : ${ent.nif}',
  ], '    ');

  final totalQte = lignes.fold<int>(0, (s, l) => s + l.qte);

  // ── Styles, décalqués de la feuille de style du gabarit web ────────────────
  final base = pw.TextStyle(font: regulier, fontSize: _px(11), color: _noir);
  final sEntNom = base.copyWith(font: gras, fontSize: _px(15));
  final sEntLigne = base.copyWith(fontSize: _px(9), color: _gris222);
  final sBlocLabel = base.copyWith(fontSize: _px(10), color: _gris333);
  final sBlocNom = base.copyWith(font: gras, fontSize: _px(11));
  final sNumFacture = base.copyWith(font: gras, fontSize: _px(17));
  final sNumMeta = base.copyWith(fontSize: _px(9), color: _gris333);
  final sTitre = base.copyWith(font: gras, fontSize: _px(22));
  final sMentions =
      base.copyWith(font: italique, lineSpacing: _interligne(_px(11), 1.6));
  final sEntete = base.copyWith(fontSize: _px(10), color: _gris222);
  final sNumLigne = base.copyWith(fontSize: _px(10), color: _gris333);
  final sProdNom = base.copyWith(font: gras);
  final sProdDesc =
      base.copyWith(font: italique, fontSize: _px(10), color: _gris333);
  final sTotalLigne = base.copyWith(font: gras);
  final sConditionsTitre = base;
  final sConditionsTexte = base.copyWith(fontSize: _px(10), color: _gris222);
  final sSignature =
      base.copyWith(fontSize: _px(10), lineSpacing: _interligne(_px(10), 1.6));
  final sPied = base.copyWith(fontSize: _px(10));
  final sPiedTitre = sPied.copyWith(font: gras);
  final sManuscrit = base.copyWith(lineSpacing: _interligne(_px(11), 2));

  const filetNoir = pw.BorderSide(color: _noir, width: 0.75);
  const filetClair = pw.BorderSide(color: _grisDDD, width: 0.75);

  // ── En-tête : logo à gauche, bloc d'identité juste à côté ──────────────────
  //
  // Le logo tient la hauteur du bloc d'identité placé à côté ; la largeur est
  // libre, un logo large n'est pas écrasé dans un carré.
  final entete = pw.Padding(
    padding: pw.EdgeInsets.only(bottom: _px(6)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: _px(170),
          child: pw.Center(
            child: logo != null
                ? pw.Image(logo, height: _px(150), fit: pw.BoxFit.contain)
                : pw.Container(
                    width: _px(150),
                    height: _px(150),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _gris999, width: 0.75)),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      nomEnt.isEmpty
                          ? '?'
                          : nomEnt.substring(0, 1).toUpperCase(),
                      style: base.copyWith(
                          font: gras, fontSize: _px(60), color: _gris555),
                    ),
                  ),
          ),
        ),
        pw.SizedBox(width: _px(16)),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(nomAffiche, style: sEntNom),
              if (ent.slogan.trim().isNotEmpty)
                pw.Text(ent.slogan, style: sEntLigne),
              if (joindreNonVides([ent.adresse, ent.quartier, ent.ville]).isNotEmpty)
                pw.Text(joindreNonVides([ent.adresse, ent.quartier, ent.ville]),
                    style: sEntLigne),
              if (ent.telephone.trim().isNotEmpty)
                pw.Text(ent.telephone, style: sEntLigne),
              if (ent.email.trim().isNotEmpty)
                pw.Text(ent.email, style: sEntLigne),
              if (ent.siteWeb.trim().isNotEmpty)
                pw.Text(ent.siteWeb, style: sEntLigne),
              if (identifiants.isNotEmpty)
                pw.Padding(
                  padding: pw.EdgeInsets.only(top: _px(2)),
                  child: pw.Text(identifiants, style: sEntLigne),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Bandeau : client à gauche, numéro et dates à droite ────────────────────
  final adresseClient =
      joindreNonVides([client?.adresse, client?.quartier, client?.ville]);
  final bandeau = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(bl ? 'Livrer à' : 'Facturer à', style: sBlocLabel),
            pw.Text(
                (client?.nom.trim().isNotEmpty ?? false)
                    ? client!.nom
                    : 'Client de passage',
                style: sBlocNom),
            if (adresseClient.isNotEmpty)
              pw.Text(adresseClient, style: sBlocLabel),
            if ((client?.telephone ?? '').trim().isNotEmpty)
              pw.Text(client!.telephone, style: sBlocLabel),
            if ((client?.email ?? '').trim().isNotEmpty)
              pw.Text(client!.email, style: sBlocLabel),
          ],
        ),
      ),
      pw.SizedBox(width: _px(16)),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('$prefixeNum$numeroDoc',
              style: sNumFacture, textAlign: pw.TextAlign.right),
          pw.SizedBox(height: _px(2)),
          pw.Text(fmtDateNum(bl ? vente?.date : facture.dateEmission),
              style: sNumMeta, textAlign: pw.TextAlign.right),
          if (!bl)
            pw.Text('Date d\'échéance : ${fmtDateNum(facture.dateEcheance)}',
                style: sNumMeta, textAlign: pw.TextAlign.right),
          pw.Text('Référence : $refCroisee',
              style: sNumMeta, textAlign: pw.TextAlign.right),
        ],
      ),
    ],
  );

  // ── Tableau des lignes ────────────────────────────────────────────────────
  //
  // Sur le papier, la quantité et l'unité sont sur deux lignes, et le prix
  // unitaire est en colonne « Taux ». La remise éventuelle n'a pas de colonne
  // dédiée : elle se lit dans le montant, on la rappelle sous la désignation.
  // La colonne du numéro de ligne est étroite (22 px sur le gabarit web) : à
  // 6 px de marge de chaque côté, l'en-tête « N° » se coupait entre le N et le
  // degré. Le navigateur élargit la colonne dans ce cas, le tableau PDF non —
  // on resserre donc la marge sur cette seule colonne.
  pw.Widget celluleTexte(String texte, pw.TextStyle style,
          {pw.TextAlign align = pw.TextAlign.left,
          double haut = 6,
          double cote = 6}) =>
      pw.Padding(
        padding:
            pw.EdgeInsets.symmetric(vertical: _px(haut), horizontal: _px(cote)),
        child: pw.Text(texte, style: style, textAlign: align),
      );

  final tableau = pw.Table(
    columnWidths: {
      0: pw.FixedColumnWidth(_px(22)),
      1: const pw.FlexColumnWidth(1),
      2: pw.FixedColumnWidth(_px(70)),
      if (!bl) 3: pw.FixedColumnWidth(_px(110)),
      if (!bl) 4: pw.FixedColumnWidth(_px(110)),
    },
    children: [
      pw.TableRow(
        decoration:
            const pw.BoxDecoration(border: pw.Border(bottom: filetNoir)),
        children: [
          celluleTexte('N°', sEntete, haut: 4, cote: 2),
          celluleTexte('Produit', sEntete, haut: 4),
          celluleTexte('qté', sEntete, align: pw.TextAlign.right, haut: 4),
          if (!bl) celluleTexte('Taux', sEntete, align: pw.TextAlign.right, haut: 4),
          if (!bl) celluleTexte('Montant', sEntete, align: pw.TextAlign.right, haut: 4),
        ],
      ),
      for (var i = 0; i < lignes.length; i++)
        pw.TableRow(
          decoration:
              const pw.BoxDecoration(border: pw.Border(bottom: filetClair)),
            children: [
              celluleTexte('${i + 1}', sNumLigne, cote: 2),
              pw.Padding(
                padding:
                    pw.EdgeInsets.symmetric(vertical: _px(6), horizontal: _px(6)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(lignes[i].articleNom, style: sProdNom),
                    if (lignes[i].articleRef.trim().isNotEmpty)
                      pw.Text(lignes[i].articleRef, style: sProdDesc),
                  ],
                ),
              ),
              pw.Padding(
                padding:
                    pw.EdgeInsets.symmetric(vertical: _px(6), horizontal: _px(6)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(numFRPdf(lignes[i].qte), style: base),
                    if (lignes[i].unite.trim().isNotEmpty)
                      pw.Text(lignes[i].unite, style: sProdDesc),
                  ],
                ),
              ),
              if (!bl)
                celluleTexte(numFRPdf(lignes[i].prixUnitaire), base,
                    align: pw.TextAlign.right),
              if (!bl)
                celluleTexte(numFRPdf(lignes[i].total), base,
                    align: pw.TextAlign.right),
            ],
          ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _grisF2,
          border: pw.Border(top: filetNoir, bottom: filetNoir),
        ),
        children: [
          celluleTexte('', sTotalLigne),
          celluleTexte('Le total', sTotalLigne),
          celluleTexte(numFRPdf(totalQte), sTotalLigne,
              align: pw.TextAlign.right),
          if (!bl) celluleTexte('-', sTotalLigne, align: pw.TextAlign.right),
          if (!bl)
            celluleTexte(numFRPdf(facture.montantTTC), sTotalLigne,
                align: pw.TextAlign.right),
        ],
      ),
    ],
  );

  // ── Bas de tableau : conditions à gauche, cumul à droite ───────────────────
  pw.Widget ligneCumul(String libelle, String montant, {bool fort = false}) =>
      pw.Container(
        decoration:
            const pw.BoxDecoration(border: pw.Border(bottom: filetNoir)),
        padding: pw.EdgeInsets.symmetric(vertical: _px(5), horizontal: _px(2)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(libelle, style: fort ? base.copyWith(font: gras) : base),
            pw.Text(montant, style: fort ? base.copyWith(font: gras) : base),
          ],
        ),
      );

  final bas = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          // Le filet sous l'intitulé court sur toute la colonne, comme la
          // bordure d'un bloc HTML, et non sur la seule largeur du texte.
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              decoration:
                  const pw.BoxDecoration(border: pw.Border(bottom: filetNoir)),
              padding: pw.EdgeInsets.only(bottom: _px(4)),
              child: pw.Text(
                  'Cette vente est soumise aux conditions générales suivantes :',
                  style: sConditionsTitre),
            ),
            pw.SizedBox(height: _px(6)),
            pw.Text(joindreNonVides([ent.conditionsPaiement, facture.note], '\n'),
                style: sConditionsTexte),
          ],
        ),
      ),
      pw.SizedBox(width: _px(24)),
      pw.SizedBox(
        // « width:48% » du gabarit web, rapporté à la largeur utile de la page
        // (210 mm moins les deux marges de 14 mm).
        width: _mm((210 - 14 - 14) * 0.48),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (!bl)
              ligneCumul('Total Net', '$devise ${numFRPdf(facture.montantTTC)}',
                  fort: true),
          ],
        ),
      ),
    ],
  );

  // ── Cartouche de signature ────────────────────────────────────────────────
  //
  // Le nom et la mention « Signature » descendent bas sur la page : la zone
  // laissée au-dessus reçoit la signature manuscrite et le cachet, apposés
  // après l'impression. Sans signature scannée, on réserve la place pour signer
  // ET tamponner ; avec, il ne reste que le cachet à apposer.
  // Le cartouche occupe toute la largeur utile : sans cette contrainte la
  // colonne se réduit à son contenu et se retrouve collée au bord gauche,
  // alors que le gabarit web l'aligne à droite de la page.
  final cartouche = pw.SizedBox(
    width: double.infinity,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.SizedBox(height: signature != null ? _mm(18) : _mm(34)),
        if (signature != null)
          pw.Image(signature, height: _mm(22), fit: pw.BoxFit.contain),
        pw.Text(
            ent.signataire.trim().isEmpty
                ? _piedSignataire
                : ent.signataire.trim(),
            style: sSignature,
            textAlign: pw.TextAlign.right),
        pw.Text('Signature', style: sSignature, textAlign: pw.TextAlign.right),
      ],
    ),
  );

  // ── Pied : trois colonnes séparées par des filets verticaux ────────────────
  pw.Widget colonnePied(String titre, String corps, {bool filet = false}) =>
      pw.Container(
        padding: pw.EdgeInsets.symmetric(horizontal: _px(12)),
        decoration: filet
            ? const pw.BoxDecoration(
                border: pw.Border(
                    left: pw.BorderSide(color: _grisCCC, width: 0.75)))
            : null,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(titre, style: sPiedTitre),
            pw.SizedBox(height: _px(3)),
            pw.Text(corps, style: sPied),
          ],
        ),
      );

  final infosBancaires = ent.rib.trim().isEmpty ? _piedCompte : ent.rib.trim();
  final pied = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: _px(22)),
      pw.Table(
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(children: [
            colonnePied('Payable à',
                ent.banque.trim().isEmpty ? _piedBanque : ent.banque.trim()),
            colonnePied(
                'Informations Bancaires',
                ent.swift.trim().isEmpty
                    ? infosBancaires
                    : '$infosBancaires\nSWIFT : ${ent.swift.trim()}',
                filet: true),
            colonnePied(
                'Autres détails',
                ent.mentionsLegales.trim().isEmpty
                    ? _piedAutresDetails
                    : ent.mentionsLegales.trim(),
                filet: true),
          ]),
        ],
      ),
      pw.SizedBox(height: _px(18)),
      pw.Text('Livré par :', style: sManuscrit),
      pw.Text('Numéro du réceptionneur :', style: sManuscrit),
    ],
  );

  // ── Assemblage ────────────────────────────────────────────────────────────
  final document = pw.Document(title: '$titre $numeroDoc');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme:
          pw.ThemeData.withFont(base: regulier, bold: gras, italic: italique),
      margin: pw.EdgeInsets.only(
          top: _mm(16), left: _mm(14), right: _mm(14), bottom: _mm(12)),
      // Le pied est ancré en bas de page, comme le `margin-top:auto` du gabarit
      // web. Une facture qui tient sur une page — le cas courant — sort donc
      // exactement comme à l'écran de l'application web.
      footer: (_) => pied,
      build: (_) => [
        entete,
        pw.Container(
          decoration:
              const pw.BoxDecoration(border: pw.Border(bottom: filetNoir)),
        ),
        pw.SizedBox(height: _px(14) + _px(10)),
        pw.Center(child: pw.Text(titre, style: sTitre)),
        pw.SizedBox(height: _px(14)),
        bandeau,
        pw.SizedBox(height: _px(16)),
        pw.Text('Commandé par :', style: sMentions),
        pw.Text('Livré à :', style: sMentions),
        pw.SizedBox(height: _px(10)),
        tableau,
        pw.SizedBox(height: _px(4) + _px(14)),
        bas,
        if (!bl) ...[
          pw.SizedBox(height: _px(18)),
          pw.Text(
              'Le montant en mots : ${montantEnLettres(facture.montantTTC)} Franc seulement',
              style: base),
        ],
        pw.SizedBox(height: _px(26)),
        cartouche,
      ],
    ),
  );

  return document.save();
}

Future<void> partagerFacturePdf(Facture facture, Vente? vente, Client? client,
    Entreprise? entreprise) async {
  final bytes = await genererFacturePdf(facture, vente, client, entreprise);
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'Facture_${facture.numero}.pdf',
  );
}

Future<void> imprimerFacturePdf(Facture facture, Vente? vente, Client? client,
    Entreprise? entreprise) async {
  final bytes = await genererFacturePdf(facture, vente, client, entreprise);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Facture_${facture.numero}',
  );
}
