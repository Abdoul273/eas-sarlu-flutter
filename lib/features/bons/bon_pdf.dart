import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/models.dart';
import '../factures/facture_pdf.dart';

// ─── Bon de livraison imprimable ──────────────────────────────────────────────
// Sur le papier, le bon de livraison est la facture avec un autre titre et un
// autre numéro : l'application web les tire du même gabarit
// (`src/lib/print-facture.ts`, `documentHtml(…, "bon-livraison")`). On fait ici
// de même en appelant le gabarit partagé plutôt qu'en entretenant une seconde
// mise en page — deux gabarits auraient divergé au premier ajustement, et
// c'est exactement ce qui s'était produit : le bon sortait avec un en-tête, un
// tableau et un cartouche de signature sans rapport avec ceux de la facture.
//
// Le numéro n'est pas alloué séparément : il dérive de celui de la vente
// (VTE-2026-0377 → BL-2026-0377), déjà attribué de façon atomique par le
// serveur. Une vente pas encore synchronisée n'a pas de numéro : le bon n'en
// porte pas non plus.

/// Numéro affichable du bon, avec un repli lisible tant que la vente n'a pas
/// été synchronisée — c'est ce que la liste et le nom de fichier utilisent.
String numeroBonAffiche(Vente vente) {
  final numero = numeroBL(vente);
  return numero.isEmpty ? 'BL-...' : numero;
}

/// Le bon reprend les montants de la facture liée à la vente. Sans facture —
/// vente pas encore facturée — le document sort tout de même, avec un cumul à
/// zéro : mieux vaut un bon de livraison utilisable pour la remise des
/// marchandises qu'un bouton qui ne fait rien.
Facture _factureDeRepli(Vente vente) => Facture(
      id: '',
      venteId: vente.id,
      clientId: vente.clientId,
      dateEmission: vente.date,
    );

Future<Uint8List> genererBonPdf(
  Vente vente,
  Client? client,
  Entreprise? entreprise, {
  Facture? facture,
}) =>
    genererFacturePdf(
      facture ?? _factureDeRepli(vente),
      vente,
      client,
      entreprise,
      type: TypeDocument.bonLivraison,
    );

Future<void> partagerBonPdf(
  Vente vente,
  Client? client,
  Entreprise? entreprise, {
  Facture? facture,
}) async {
  final bytes =
      await genererBonPdf(vente, client, entreprise, facture: facture);
  final dir = await getTemporaryDirectory();
  final numero = numeroBonAffiche(vente);
  final fichier = File('${dir.path}/bon_$numero.pdf');
  await fichier.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(fichier.path)],
      text: 'Bon de livraison $numero');
}

Future<void> imprimerBonPdf(
  Vente vente,
  Client? client,
  Entreprise? entreprise, {
  Facture? facture,
}) async {
  final bytes =
      await genererBonPdf(vente, client, entreprise, facture: facture);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Bon_${numeroBonAffiche(vente)}',
  );
}
