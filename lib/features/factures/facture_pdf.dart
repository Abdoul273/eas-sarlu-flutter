import '../../app/format.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/models/models.dart';
import 'polices_pdf.dart';

// ─── Les documents que le magasin remet ───────────────────────────────────────
// Facture, facture proforma et bon de livraison sortent d'UN SEUL gabarit. Sur
// le papier ils ne diffèrent que par leur titre, leur numéro, les lignes de
// dates et le cumul de droite : tout le reste — en-tête, tableau, cartouche de
// signature, pied bancaire — est rigoureusement identique. Trois gabarits
// auraient divergé au premier ajustement ; c'est déjà arrivé une fois.
//
// Les cotes ci-dessous ne sont pas inventées : elles sont relevées au point
// près sur les documents de référence du magasin (position des filets, largeur
// des colonnes, corps de chaque ligne). Un client doit recevoir exactement la
// page qu'il reçoit depuis toujours.

// ─── Cotes de la page ─────────────────────────────────────────────────────────
// Repères mesurés (en points, origine en haut à gauche) :
//   marge gauche 18 · marge droite 577,3 · filet d'en-tête à 102
//   tableau : 18 | 34,4 | 342,85 | 420,95 | 498,9 | 576,8
//   pied bancaire : encadré de 24,1 à 570,8
const _margeCote = 18.0;
const _margeHaut = 10.0;
const _bordDroit = 577.3;
const _largeurUtile = _bordDroit - _margeCote; // 559,3

// Colonnes du tableau, dans l'ordre.
const _colNum = 16.4;
const _colQte = 78.1;
const _colTaux = 77.95;
const _colMontant = 77.9;

// Corps des textes.
const _corpsTexte = 9.0;
const _corpsIntertitre = 10.5;
const _corpsIdentite = 16.5;
const _corpsTitre = 22.4;

/// Interligne d'un paragraphe de 9 pt qui se renvoie à la ligne.
const _interligne9 = 2.1;

/// Écart entre deux lignes de 9 pt EMPILÉES (deux `Text` successifs).
///
/// `lineSpacing` ne joue qu'à l'intérieur d'un même paragraphe : deux `Text`
/// l'un sous l'autre se touchent. Les documents de référence avancent de 12,6 pt
/// par ligne, soit 10,54 de hauteur de glyphe et 2,07 d'écart.
const _ecartLigne = 2.07;

/// Empile des lignes en respectant [_ecartLigne].
List<pw.Widget> _pile(List<pw.Widget> lignes, [double ecart = _ecartLigne]) {
  final sortie = <pw.Widget>[];
  for (var i = 0; i < lignes.length; i++) {
    if (i > 0) sortie.add(pw.SizedBox(height: ecart));
    sortie.add(lignes[i]);
  }
  return sortie;
}

// Teintes relevées.
const _noir = PdfColors.black;
const _grisFiletTableau = PdfColor.fromInt(0xffc9c9c9);
const _grisEnteteTableau = PdfColor.fromInt(0xfff3f3f3);
const _grisTotal = PdfColor.fromInt(0xffe9e9e9);
const _gris555 = PdfColor.fromInt(0xff555555);
const _gris999 = PdfColor.fromInt(0xff999999);

// Valeurs de repli du pied de document, quand la fiche entreprise est muette.
const _piedBanque = 'UBA (United Bank for Africa)';
const _piedCompte = 'N° 600 210 3000 84 44';
const _piedAutresDetails = 'Entreprise Alpha Solutions SARLU';
const _piedSignataire = 'Diallo Mamadou Alpha';

// ─── Chiffres ─────────────────────────────────────────────────────────────────
// Les documents de référence emploient la virgule des milliers et deux
// décimales sur les montants (1,875,000.00), l'entier seul sur les taux et les
// quantités (125,000 · 15). On les suit à la lettre : c'est ce que lisent les
// clients du magasin.

String _milliers(int n) {
  final signe = n < 0 ? '-' : '';
  final chiffres = n.abs().toString();
  final tampon = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write(',');
    tampon.write(chiffres[i]);
  }
  return '$signe$tampon';
}

/// Un montant : `1,875,000.00`.
@visibleForTesting
String fmtMontantDocument(int n) => '${_milliers(n)}.00';

/// Un taux ou une quantité : `125,000`.
@visibleForTesting
String fmtEntierDocument(int n) => _milliers(n);

/// Première lettre en capitale — « Un million… », et non « un million… ».
String _capitale(String t) =>
    t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

// ─── Images ───────────────────────────────────────────────────────────────────

/// Décode le logo ou la signature enregistrés dans les paramètres.
///
/// Le champ n'a pas la même forme selon l'application qui l'a rempli : la web
/// enregistre une adresse de données complète (`data:image/png;base64,…`), la
/// version mobile le base64 seul. Les deux écrivent dans le même enregistrement
/// serveur, donc les deux formes doivent être acceptées.
///
/// Un champ vide était la cause du plantage « RangeError (length) » :
/// `base64Decode('')` rend un tableau vide, que le décodeur d'images du paquet
/// `pdf` lit sans vérifier sa longueur. Toute donnée absente ou illisible rend
/// désormais `null`, et le document se génère sans l'image.
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

/// Les trois documents que le magasin remet à un client.
enum TypeDocument {
  /// Ce qui est dû. Porte l'échéance, la référence du bon, et un solde.
  facture,

  /// Un chiffrage qui n'engage pas encore. Porte une date de validité au lieu
  /// d'une échéance, et aucun solde : rien n'est dû tant que rien n'est vendu.
  factureProforma,

  /// La remise des marchandises. Ni échéance, ni validité, ni pied bancaire :
  /// il n'y a pas d'argent à réclamer sur un bon de livraison.
  bonLivraison,
}

/// Le numéro tel qu'il s'imprime, sans son code de série.
///
/// Le bandeau annonce déjà la nature du document — « BL N° », « Fac Pro N° » —
/// et répéter le code donnait « BL N°BL-2026-0377 ». On retire donc le préfixe
/// que la mention porte déjà.
@visibleForTesting
String numeroAffiche(String numero) =>
    numero.replaceFirst(RegExp(r'^(BL|PRO|DV|FAC|VTE)-'), '');

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
  final polices = await chargerPolices();
  final regulier = polices.regulier;
  final gras = polices.gras;
  final italique = polices.italique;

  final ent = entreprise ?? Entreprise();
  final devise = ent.devise.trim().isEmpty ? 'GNF' : ent.devise.trim();
  final bl = type == TypeDocument.bonLivraison;
  final proforma = type == TypeDocument.factureProforma;
  final lignes = (vente?.lignes ?? const <LigneVente>[])
      .where((l) => l.qte > 0)
      .toList();

  final titre = switch (type) {
    TypeDocument.facture => 'Facture',
    TypeDocument.factureProforma => 'Facture Proforma',
    TypeDocument.bonLivraison => 'Bon De Livraison',
  };
  final prefixeNum = switch (type) {
    TypeDocument.facture => 'Fac N°',
    TypeDocument.factureProforma => 'Fac Pro N°',
    TypeDocument.bonLivraison => 'BL N°',
  };
  final numeroDoc = numeroAffiche(bl ? numeroBL(vente) : facture.numero);

  // La facture renvoie au bon de livraison — c'est ce que porte le papier du
  // magasin, et ce qui permet de rapprocher les deux documents d'une vente.
  final refCroisee = numeroBL(vente).isNotEmpty
      ? 'BL N°${numeroAffiche(numeroBL(vente))}'
      : (vente?.numero ?? '');

  // Une facture sans raison sociale n'a aucune valeur commerciale. Plutôt que
  // de produire un en-tête vide qui passerait inaperçu à l'impression, on le
  // signale sur le document lui-même : l'oubli se voit avant l'envoi au client.
  final nomEnt = ent.nom.trim();
  // Le marqueur est en ASCII, et non un « ⚠ » : Roboto couvre le français mais
  // pas les symboles, et le pictogramme sortirait BLANC. L'avertissement qu'on
  // ne voit pas est précisément celui qui ne sert à rien. Un test le vérifie.
  final nomAffiche =
      nomEnt.isEmpty ? '(!) Nom de l\'entreprise à renseigner' : nomEnt;

  final logo = _imageDepuisChamp(ent.logo);
  final signature = _imageDepuisChamp(ent.signatureImage);

  final totalQte = lignes.fold<int>(0, (s, l) => s + l.qte);
  final totalMontant = bl
      ? lignes.fold<int>(0, (s, l) => s + l.total)
      : facture.montantTTC;

  // ── Styles ────────────────────────────────────────────────────────────────
  //
  // Chaque style est bâti par le CONSTRUCTEUR, jamais par `copyWith(font:)` :
  // le paquet `pdf` ignore la police passée à `copyWith`, et le style revient
  // silencieusement au romain. C'est ainsi que le gras des intitulés et
  // l'italique des unités avaient disparu du document sans qu'aucune erreur ne
  // le dise — il fallait comparer deux impressions pour s'en apercevoir.
  pw.TextStyle style({
    double taille = _corpsTexte,
    bool enGras = false,
    bool enItalique = false,
    double interligne = _interligne9,
    PdfColor couleur = _noir,
  }) =>
      pw.TextStyle(
        font: enGras ? gras : (enItalique ? italique : regulier),
        fontSize: taille,
        color: couleur,
        lineSpacing: interligne,
      );

  final sBase = style();
  final sGras = style(enGras: true);
  final sItalique = style(enItalique: true);
  final sIdentite = style(taille: _corpsIdentite, interligne: 1.0);
  final sTitre = style(taille: _corpsTitre, interligne: 0);
  final sNumero = style(taille: _corpsIdentite, interligne: 0);
  final sDate =
      style(taille: _corpsIntertitre, enGras: true, interligne: 0);
  final sIntertitre =
      style(taille: _corpsIntertitre, enGras: true, interligne: 2.8);

  const filetTableau =
      pw.BorderSide(color: _grisFiletTableau, width: 0.5);
  const filetNoir = pw.BorderSide(color: _noir, width: 0.5);

  // ── En-tête : logo à gauche, identité juste à côté ────────────────────────
  final identifiants = joindreNonVides([
    ent.rccm.trim().isEmpty ? null : 'Impôt Id : ${ent.rccm}',
    ent.nif.trim().isEmpty ? null : 'NIF ${ent.nif}',
  ], '        ');

  final entete = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 84,
        height: 81,
        child: logo != null
            ? pw.Image(logo, fit: pw.BoxFit.contain)
            : pw.Container(
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _gris999, width: 0.5)),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  nomEnt.isEmpty ? '?' : nomEnt.substring(0, 1).toUpperCase(),
                  style: style(taille: 34, enGras: true, couleur: _gris555),
                ),
              ),
      ),
      pw.SizedBox(width: 9.2),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: _pile([
            pw.Text(nomAffiche, style: sIdentite),
            if (ent.slogan.trim().isNotEmpty)
              pw.Text(ent.slogan.trim(), style: sBase),
            if (joindreNonVides([ent.adresse, ent.quartier, ent.ville])
                .isNotEmpty)
              pw.Text(joindreNonVides([ent.adresse, ent.quartier, ent.ville]),
                  style: sBase),
            if (ent.telephone.trim().isNotEmpty)
              pw.Text(ent.telephone.trim(), style: sBase),
            if (ent.email.trim().isNotEmpty)
              pw.Text(ent.email.trim(), style: sBase),
            if (ent.siteWeb.trim().isNotEmpty)
              pw.Text(ent.siteWeb.trim(), style: sBase),
            if (identifiants.isNotEmpty)
              pw.Text(identifiants, style: sBase),
          ]),
        ),
      ),
    ],
  );

  // ── Bandeau : destinataire à gauche, numéro et dates à droite ─────────────
  final adresseClient =
      joindreNonVides([client?.adresse, client?.quartier, client?.ville]);

  final bandeau = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: _pile([
            pw.Text('Facturer a', style: sBase),
            pw.Text(
                (client?.nom.trim().isNotEmpty ?? false)
                    ? client!.nom.trim()
                    : 'Client Divers',
                style: sBase),
            if (adresseClient.isNotEmpty)
              pw.Text(adresseClient, style: sBase),
            if ((client?.telephone ?? '').trim().isNotEmpty)
              pw.Text(client!.telephone.trim(), style: sBase),
            if ((client?.email ?? '').trim().isNotEmpty)
              pw.Text(client!.email.trim(), style: sBase),
          ]),
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('$prefixeNum${numeroDoc.isEmpty ? '—' : numeroDoc}',
              style: sNumero, textAlign: pw.TextAlign.right),
          pw.SizedBox(height: 0.7),
          pw.Text(fmtDateNum(bl ? vente?.date : facture.dateEmission),
              style: sDate, textAlign: pw.TextAlign.right),
          // Une facture porte une échéance de paiement ; une proforma, une
          // limite de validité des prix ; un bon de livraison, ni l'une ni
          // l'autre — il n'y a rien à payer sur une remise de marchandises.
          if (type == TypeDocument.facture &&
              facture.dateEcheance.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2.4),
            pw.Text('Date d\'échéance : ${fmtDateNum(facture.dateEcheance)}',
                style: sBase, textAlign: pw.TextAlign.right),
          ],
          if (proforma && facture.dateEcheance.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2.4),
            pw.Text('Valable jusqu\'à : ${fmtDateNum(facture.dateEcheance)}',
                style: sBase, textAlign: pw.TextAlign.right),
          ],
          if (type == TypeDocument.facture && refCroisee.isNotEmpty)
            pw.Text('Référence : $refCroisee',
                style: sBase, textAlign: pw.TextAlign.right),
        ],
      ),
    ],
  );

  // ── Tableau des lignes ────────────────────────────────────────────────────
  pw.Widget cellule(String texte, pw.TextStyle style,
          {pw.TextAlign align = pw.TextAlign.left, double cote = 4}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 2.83, horizontal: cote),
        child: pw.Text(texte, style: style, textAlign: align),
      );

  final tableau = pw.Table(
    border: const pw.TableBorder(
      left: filetTableau,
      right: filetTableau,
      top: filetTableau,
      bottom: filetTableau,
      horizontalInside: filetTableau,
      verticalInside: filetTableau,
    ),
    columnWidths: const {
      0: pw.FixedColumnWidth(_colNum),
      1: pw.FlexColumnWidth(1),
      2: pw.FixedColumnWidth(_colQte),
      3: pw.FixedColumnWidth(_colTaux),
      4: pw.FixedColumnWidth(_colMontant),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _grisEnteteTableau),
        children: [
          cellule('N°', sBase, cote: 3),
          cellule('Produit', sBase),
          cellule('qté', sBase, align: pw.TextAlign.right),
          cellule('Taux', sBase, align: pw.TextAlign.right),
          cellule('Montant', sBase, align: pw.TextAlign.right),
        ],
      ),
      for (var i = 0; i < lignes.length; i++)
        pw.TableRow(
          children: [
            cellule('${i + 1}', sBase, align: pw.TextAlign.center, cote: 3),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 2.83, horizontal: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: _pile([
                  pw.Text(lignes[i].articleNom, style: sBase),
                  if (lignes[i].articleRef.trim().isNotEmpty)
                    pw.Text(lignes[i].articleRef.trim(), style: sBase),
                ], 2.82),
              ),
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 2.83, horizontal: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: _pile([
                  pw.Text(fmtEntierDocument(lignes[i].qte), style: sBase),
                  if (lignes[i].unite.trim().isNotEmpty)
                    pw.Text(lignes[i].unite.trim(), style: sItalique),
                ], 2.82),
              ),
            ),
            cellule(fmtEntierDocument(lignes[i].prixUnitaire), sBase,
                align: pw.TextAlign.right),
            cellule(fmtMontantDocument(lignes[i].total), sBase,
                align: pw.TextAlign.right),
          ],
        ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _grisTotal),
        children: [
          cellule('', sBase, cote: 3),
          cellule('Le total', sBase),
          cellule(fmtEntierDocument(totalQte), sBase, align: pw.TextAlign.right),
          cellule('-', sBase, align: pw.TextAlign.right),
          cellule(fmtMontantDocument(totalMontant), sBase,
              align: pw.TextAlign.right),
        ],
      ),
    ],
  );

  // ── Conditions à gauche, cumul à droite ───────────────────────────────────
  pw.Widget ligneCumul(String libelle, String montant, {bool fond = false}) =>
      pw.Container(
        decoration: pw.BoxDecoration(
          color: fond ? _grisEnteteTableau : null,
          border: const pw.Border(top: filetNoir),
        ),
        padding: pw.EdgeInsets.symmetric(
            vertical: fond ? 3.5 : 2.6, horizontal: fond ? 3.4 : 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(libelle, style: sBase),
            pw.Text('$devise $montant', style: sBase),
          ],
        ),
      );

  final bas = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 318.5, // 18 → 336,5
        child: pw.Container(
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: filetNoir, bottom: filetNoir)),
          padding: const pw.EdgeInsets.fromLTRB(6, 2.6, 0, 1.7),
          child: pw.Text(
              'Cette vente est soumise aux conditions générales suivantes :',
              style: sBase),
        ),
      ),
      pw.Spacer(),
      pw.SizedBox(
        width: 222.8, // 354,5 → 577,3
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            ligneCumul('Le total', fmtMontantDocument(totalMontant)),
            ligneCumul('Somme finale', fmtMontantDocument(totalMontant), fond: true),
            // Le solde n'a de sens que sur ce qui est dû. Une proforma
            // n'engage rien et un bon de livraison ne réclame rien.
            if (type == TypeDocument.facture)
              ligneCumul('Solde', fmtMontantDocument(totalMontant)),
          ],
        ),
      ),
    ],
  );

  // ── Cartouche de signature ────────────────────────────────────────────────
  //
  // Le bloc est large de 119 points et calé à droite : c'est ce qui centre le
  // nom et la mention « Signature » sous l'image, exactement comme sur les
  // documents du magasin. L'espace au-dessus est réservé même sans signature
  // numérisée — il faut pouvoir signer et tamponner à la main.
  final cartouche = pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 119,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (signature != null)
            pw.Image(signature, height: 48, fit: pw.BoxFit.contain)
          else
            pw.SizedBox(height: 48),
          pw.SizedBox(height: 4),
          pw.Text(
              ent.signataire.trim().isEmpty
                  ? _piedSignataire
                  : ent.signataire.trim(),
              style: sBase,
              textAlign: pw.TextAlign.center),
          pw.Text('Signature', style: sGras, textAlign: pw.TextAlign.center),
        ],
      ),
    ),
  );

  // ── Pied bancaire, encadré, trois colonnes ────────────────────────────────
  pw.Widget colonnePied(String titre, String corps) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(6.5, 8.9, 6.5, 7.2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(titre, style: sGras),
            pw.SizedBox(height: 3.3),
            pw.Text(corps, style: sBase),
          ],
        ),
      );

  final infosBancaires = ent.rib.trim().isEmpty ? _piedCompte : ent.rib.trim();
  final piedBancaire = pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6.1),
    child: pw.Container(
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _grisFiletTableau, width: 0.5)),
      child: pw.Table(
        border: const pw.TableBorder(verticalInside: filetTableau),
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
                    : '$infosBancaires\nSWIFT : ${ent.swift.trim()}'),
            colonnePied(
                'Autres détails',
                ent.mentionsLegales.trim().isEmpty
                    ? _piedAutresDetails
                    : ent.mentionsLegales.trim()),
          ]),
        ],
      ),
    ),
  );

  // ── Assemblage ────────────────────────────────────────────────────────────
  final document = pw.Document(title: '$titre $numeroDoc');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme:
          pw.ThemeData.withFont(base: regulier, bold: gras, italic: italique),
      margin: pw.EdgeInsets.fromLTRB(
          _margeCote, _margeHaut, PdfPageFormat.a4.width - _bordDroit, 24),
      build: (_) => [
        entete,
        pw.SizedBox(height: 10),
        pw.Container(height: 1, width: _largeurUtile, color: _noir),
        pw.SizedBox(height: 13.5),
        pw.Center(child: pw.Text(titre, style: sTitre)),
        pw.SizedBox(height: 22.6),
        bandeau,
        pw.SizedBox(height: 15.7),
        // Deux lignes qu'on remplit à la main au moment de la remise. Elles
        // figurent sur les trois documents du magasin.
        pw.Text('Commandé par :', style: sIntertitre),
        pw.Text('Livré à :', style: sIntertitre),
        pw.SizedBox(height: 18.3),
        tableau,
        pw.SizedBox(height: 12.3),
        bas,
        pw.SizedBox(height: 14.4),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 9),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Le montant en mots : ', style: sGras),
              pw.TextSpan(
                  text: '${_capitale(montantEnLettres(totalMontant))} '
                      'Franc seulement',
                  style: sBase),
            ]),
          ),
        ),
        // L'espace au-dessus du cartouche est celui des documents du magasin :
        // il laisse la place d'apposer un cachet à côté de la signature.
        pw.SizedBox(height: 47.5),
        cartouche,
        pw.SizedBox(height: 9.7),
        // Le pied bancaire ne figure pas sur un bon de livraison : il n'y a
        // rien à payer sur une remise de marchandises.
        if (!bl) ...[
          piedBancaire,
          pw.SizedBox(height: 10.5),
        ],
        pw.Text('Livré par :', style: sIntertitre),
        pw.Text('Numéro du réceptionneur :', style: sIntertitre),
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
