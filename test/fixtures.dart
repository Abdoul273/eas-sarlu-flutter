// ignore_for_file: avoid_relative_lib_imports
import '../lib/core/models/models.dart';

// Fabriques d'objets métier pour les tests.
//
// Transposition de `src/lib/__tests__/fixtures.ts` de l'application web, avec
// les mêmes valeurs par défaut : quand les deux suites affirment la même chose,
// elles doivent partir des mêmes chiffres.
//
// Chaque fabrique part d'un objet complet et valide, et n'expose en argument
// que les champs qui comptent pour le test. Un test qui vérifie un reste dû n'a
// pas à inventer un numéro de facture ni une adresse de client : ce bruit-là
// cache ce que le test affirme vraiment.

Article article({
  String id = 'A1',
  String ref = 'REF-1',
  String nom = 'Tube carré 40x40',
  String categorie = 'Tube carré',
  int prixAchat = 100000,
  int prixVente = 130000,
  int stock = 50,
  int stockMin = 20,
}) =>
    Article(
      id: id,
      ref: ref,
      nom: nom,
      categorie: categorie,
      unite: 'Barre',
      prixAchat: prixAchat,
      prixVente: prixVente,
      stock: stock,
      stockMin: stockMin,
      longueur: 6,
      epaisseur: 2,
      provenance: 'Turquie',
    );

LigneVente ligne({
  String articleId = 'A1',
  int qte = 1,
  int prixUnitaire = 130000,
  int total = 130000,
}) =>
    LigneVente(
      articleId: articleId,
      articleRef: 'REF-1',
      articleNom: 'Tube carré 40x40',
      unite: 'Barre',
      qte: qte,
      prixUnitaire: prixUnitaire,
      total: total,
    );

Vente vente({
  String id = 'V1',
  String date = '2026-03-15T10:00:00.000Z',
  int totalNet = 130000,
  List<LigneVente>? lignes,
}) =>
    Vente(
      id: id,
      numero: 'VTE-2026-0001',
      clientId: 'C1',
      vendeur: 'Mamadou',
      date: date,
      lignes: lignes ?? [ligne()],
      totalHT: totalNet,
      totalNet: totalNet,
    );

Paiement paiement({
  String id = 'P1',
  String date = '2026-03-15T10:00:00.000Z',
  int montant = 50000,
  String mode = 'espèces',
}) =>
    Paiement(
      id: id,
      date: date,
      montant: montant,
      mode: mode,
      utilisateur: 'Mamadou',
    );

Facture facture({
  String id = 'F1',
  String clientId = 'C1',
  String dateEmission = '2026-03-15T10:00:00.000Z',
  String dateEcheance = '2026-04-15',
  int montantTTC = 130000,
  List<Paiement> paiements = const [],
}) =>
    Facture(
      id: id,
      numero: 'FAC-2026-0001',
      venteId: 'V1',
      clientId: clientId,
      dateEmission: dateEmission,
      dateEcheance: dateEcheance,
      montantHT: montantTTC,
      montantTTC: montantTTC,
      paiements: paiements,
    );

Reglement reglement({
  String id = 'R1',
  String date = '2026-03-20T10:00:00.000Z',
  int montant = 200000,
}) =>
    Reglement(
      id: id,
      date: date,
      montant: montant,
      mode: 'espèces',
      utilisateur: 'Mamadou',
    );

Depense depense({
  String id = 'D1',
  String date = '2026-03-10T08:00:00.000Z',
  String categorie = 'Loyer',
  int montant = 500000,
  List<Reglement> reglements = const [],
}) =>
    Depense(
      id: id,
      numero: 'DEP-2026-0001',
      date: date,
      categorie: categorie,
      libelle: 'Loyer du dépôt',
      beneficiaire: 'Bailleur',
      montant: montant,
      reglements: reglements,
    );
