import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/format.dart';
import '../../core/models/models.dart';
import '../factures/facture_pdf.dart';

// ─── Devis imprimable ─────────────────────────────────────────────────────────
// Un calcul de comptoir devient un papier qu'on tend au client, ou qu'on lui
// envoie sur WhatsApp. C'est le même gabarit que la facture et le bon de
// livraison (`facture_pdf.dart`) : même en-tête, même tableau, même cartouche
// de signature, même pied. Le client qui reçoit le devis lundi et la facture
// jeudi reconnaît la maison sur les deux.
//
// Le devis ne passe PAS par le serveur, et c'est délibéré : c'est un chiffrage,
// pas un engagement. Rien n'est réservé, aucun stock n'est retenu, aucun numéro
// n'est consommé dans la série des ventes. Le magasin peut donc en sortir vingt
// dans la journée sans polluer l'historique — et sans réseau, ce qui compte
// autant : un devis se fait au comptoir, souvent le téléphone en main.

/// Durée de validité par défaut, en jours.
///
/// Une semaine : sur les matériaux de construction, un prix tenu plus longtemps
/// est un prix qu'on regrette. Le fer et le ciment bougent, et un devis sans
/// date de fin engage le magasin indéfiniment.
const int kValiditeDevisJours = 7;

/// Numéro de la proforma — `PRO-2026-0802-1432`.
///
/// L'année, le jour puis l'heure : deux devis du même comptoir ne peuvent se
/// confondre, et le numéro se classe tout seul dans l'ordre chronologique. Il
/// n'est PAS tiré de la série des ventes : un chiffrage sans suite y laisserait
/// un trou inexplicable.
///
/// Il est attribué ICI, sur le téléphone, et le serveur le conserve tel quel :
/// le papier remis au client et l'enregistrement portent le même numéro, même
/// quand la proforma part hors ligne. Le serveur n'en attribue un que si
/// celui-ci manque.
///
/// Le code « PRO » est celui du document imprimé — une facture proforma. Le
/// bandeau annonçant « Fac Pro N° », le code lui-même n'est pas réimprimé.
String numeroDevis(DateTime quand) {
  String d(int n, [int large = 2]) => n.toString().padLeft(large, '0');
  return 'PRO-${quand.year}-${d(quand.month)}${d(quand.day)}-'
      '${d(quand.hour)}${d(quand.minute)}';
}

/// Ce que le calculateur transmet au document.
class Devis {
  final String numero;
  final DateTime date;
  final List<LigneVente> lignes;
  final Client? client;

  /// Nom saisi à la main, pour un client de passage qui n'est pas au fichier.
  /// Le devis mérite un nom : « Client de passage » sur un papier qu'on envoie
  /// fait négligé.
  final String nomLibre;

  final int validiteJours;

  /// Remarque libre — « livraison à Kipé comprise », « hors main-d'œuvre ».
  /// Elle s'imprime avec les conditions de paiement de l'entreprise.
  final String note;

  Devis({
    required this.numero,
    required this.date,
    required this.lignes,
    this.client,
    this.nomLibre = '',
    this.validiteJours = kValiditeDevisJours,
    this.note = '',
  });

  /// Reconstruit le document depuis une proforma enregistrée, pour la
  /// réimprimer ou la renvoyer depuis la liste.
  factory Devis.depuisProforma(Proforma p, {Client? client}) => Devis(
        numero: p.numero,
        date: p.dateValeur ?? DateTime.now(),
        lignes: p.lignes,
        client: client,
        nomLibre: client == null ? p.clientNom : '',
        validiteJours: p.validiteJours,
        note: p.note,
      );

  /// L'enregistrement qui en garde la trace.
  Proforma versProforma({required String id, required String creePar}) =>
      Proforma(
        id: id,
        numero: numero,
        clientId: client?.id ?? '',
        clientNom: client?.nom ?? nomLibre.trim(),
        date: date.toIso8601String(),
        validiteJours: validiteJours,
        lignes: lignes,
        totalNet: total,
        note: note.trim(),
        creePar: creePar,
      );

  int get total => lignes.fold<int>(0, (s, l) => s + l.total);
  int get totalUnites => lignes.fold<int>(0, (s, l) => s + l.qte);
  DateTime get valableJusquA => date.add(Duration(days: validiteJours));

  /// Le client tel qu'il doit apparaître sur le papier.
  ///
  /// Un nom saisi à la main vaut fiche client le temps du document : le devis
  /// sort au nom de la personne, sans qu'il faille d'abord créer un client au
  /// fichier pour un chiffrage qui n'aboutira peut-être pas.
  Client? get destinataire {
    if (client != null) return client;
    if (nomLibre.trim().isEmpty) return null;
    return Client(id: '', nom: nomLibre.trim());
  }
}

/// La vente et la facture que le gabarit attend — construites en mémoire, et
/// jamais enregistrées nulle part.
(Vente, Facture) _pieces(Devis devis) {
  final iso = devis.date.toIso8601String();
  final vente = Vente(
    id: '',
    clientId: devis.client?.id ?? '',
    date: iso,
    lignes: devis.lignes,
    totalHT: devis.total,
    totalNet: devis.total,
  );
  final facture = Facture(
    id: '',
    numero: devis.numero,
    venteId: '',
    clientId: devis.client?.id ?? '',
    dateEmission: iso,
    dateEcheance: devis.valableJusquA.toIso8601String(),
    montantHT: devis.total,
    montantTTC: devis.total,
    note: devis.note.trim(),
  );
  return (vente, facture);
}

Future<Uint8List> genererDevisPdf(Devis devis, Entreprise? entreprise) {
  final (vente, facture) = _pieces(devis);
  return genererFacturePdf(
    facture,
    vente,
    devis.destinataire,
    entreprise,
    type: TypeDocument.factureProforma,
  );
}

/// Le message qui accompagne le fichier.
///
/// WhatsApp affiche ce texte sous la pièce jointe : c'est souvent tout ce que
/// le client lit avant d'ouvrir le PDF. Il porte donc l'essentiel — de qui, pour
/// combien, jusqu'à quand — et rien d'autre.
String messageDevis(Devis devis, Entreprise? entreprise) {
  final maison = (entreprise?.nom ?? '').trim();
  final nom = (devis.destinataire?.nom ?? '').trim();
  return [
    if (nom.isEmpty) 'Bonjour,' else 'Bonjour $nom,',
    'voici votre facture proforma ${devis.numero}'
        '${maison.isEmpty ? '' : ' — $maison'}.',
    '${devis.lignes.length} article${devis.lignes.length > 1 ? 's' : ''} · '
        'Total : ${fmtGNF(devis.total)}',
    'Valable jusqu\'au ${fmtDateNum(devis.valableJusquA.toIso8601String())}.',
  ].join('\n');
}

/// Ouvre le partage du système : WhatsApp, e-mail, Bluetooth, enregistrement…
///
/// Le fichier est écrit dans le dossier temporaire sous son vrai nom — c'est ce
/// nom que le client verra dans sa conversation, et
/// « proforma_PRO-2026-0802-1432 » se retrouve, là où un nom généré au hasard
/// se perd.
Future<void> partagerDevisPdf(Devis devis, Entreprise? entreprise) async {
  final bytes = await genererDevisPdf(devis, entreprise);
  final dossier = await getTemporaryDirectory();
  final fichier = File('${dossier.path}/proforma_${devis.numero}.pdf');
  await fichier.writeAsBytes(bytes);
  await Share.shareXFiles(
    [XFile(fichier.path, mimeType: 'application/pdf')],
    text: messageDevis(devis, entreprise),
    subject: 'Facture proforma ${devis.numero}',
  );
}

Future<void> imprimerDevisPdf(Devis devis, Entreprise? entreprise) async {
  final bytes = await genererDevisPdf(devis, entreprise);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Proforma_${devis.numero}',
  );
}
