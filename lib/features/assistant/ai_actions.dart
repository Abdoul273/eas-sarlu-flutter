import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../app/format.dart';
import '../../core/models/models.dart';
import 'resolution_article.dart';

// ─── Ce que l'assistant a le droit d'écrire ───────────────────────────────────
//
// Transposition de `src/lib/ai-actions.ts` de l'application web. Les deux
// applications parlent au même serveur et doivent refuser les mêmes choses aux
// mêmes personnes : un droit retiré depuis l'ordinateur doit fermer la même
// porte sur le téléphone, jusqu'au nom de l'action et au texte du refus.
//
// Les outils (`ai_outils.dart`) LISENT le magasin. Ce fichier-ci décrit ce que
// l'assistant peut proposer d'y ÉCRIRE — et rien d'autre ne peut l'être.
//
// Trois principes, et le premier commande les deux autres.
//
// 1. L'ASSISTANT N'EXÉCUTE RIEN. Il émet une intention : « voici l'entrée de
//    stock que je crois que tu veux ». Elle ne devient une écriture qu'après
//    une fiche que l'humain lit et un bouton qu'il appuie.
//
// 2. LES DROITS SE VÉRIFIENT ICI, EN CODE — pas dans le message système. Un
//    prompt se contourne : il suffit de convaincre le modèle qu'il a tort. Une
//    fonction qui compare une liste, non. `verifierAction` est appelée sur
//    chaque intention, quoi qu'ait raconté le modèle, et c'est elle qui tranche.
//    Le serveur revérifie ensuite le même droit sur la route ET sur l'opération
//    rejouée hors ligne : trois serrures, dont deux hors de portée du modèle.
//
// 3. CE QUI N'EST PAS AU CATALOGUE N'EXISTE PAS. Aucun geste irréversible n'y
//    figure — ni suppression, ni annulation de règlement, ni remise à zéro. Il
//    n'y a pas de code pour les refuser parce qu'il n'y a pas de code pour les
//    faire. Un test le vérifie, pour que personne ne les ajoute par distraction.

/// Ce qu'un champ attend, et donc comment la feuille de saisie le présente.
enum TypeChamp { texte, nombre, article, client, facture, choix, date }

@immutable
class ChampAction {
  final String nom;
  final String libelle;
  final TypeChamp type;

  /// Sans lui, l'action ne part pas : la fiche s'ouvre et le réclame.
  final bool requis;
  final String? aide;
  final List<String>? choix;
  final String? suffixe;

  const ChampAction({
    required this.nom,
    required this.libelle,
    required this.type,
    required this.requis,
    this.aide,
    this.choix,
    this.suffixe,
  });
}

/// Ce dont le résumé de confirmation a besoin pour être précis plutôt que vague.
@immutable
class ContexteResume {
  final List<Article> articles;
  final List<Client> clients;
  const ContexteResume({this.articles = const [], this.clients = const []});
}

@immutable
class ActionIA {
  /// Le nom employé par le modèle, identique à celui de l'application web.
  final String type;

  /// Le droit exigé, ou `null` pour ce qui ne touche à rien — ouvrir un écran
  /// n'écrit nulle part, et le routeur filtre déjà les pages interdites.
  final String? droit;
  final String titre;
  final List<ChampAction> champs;

  /// Ce qui va se passer, dit en clair, ligne par ligne. C'est ce que l'humain
  /// lit avant de confirmer : un résumé vague vaut une confirmation aveugle, et
  /// une confirmation aveugle ne protège de rien.
  final List<String> Function(Map<String, dynamic> args, ContexteResume ctx)
      resume;

  const ActionIA({
    required this.type,
    required this.droit,
    required this.titre,
    required this.champs,
    required this.resume,
  });
}

// ─── Lecture tolérante des arguments ──────────────────────────────────────────

String _txt(dynamic v) => (v ?? '').toString().trim();

/// Les modèles écrivent « 10 000 », « 10.000 GNF » ou « 10 000 ». On ne garde
/// que les chiffres et le séparateur décimal : un montant illisible vaut mieux
/// refusé par le champ obligatoire qu'accepté à un facteur mille près.
double? _num(dynamic v) {
  final brut = _txt(v).replaceAll(RegExp(r'[^\d.,-]'), '').replaceAll(',', '.');
  if (brut.isEmpty) return null;
  return double.tryParse(brut);
}

bool _chiffre(dynamic v) => _txt(v).isNotEmpty && _num(v) != null;

/// Retrouve l'article désigné, pour l'écrire en clair dans le récapitulatif.
///
/// Passe par la même résolution que l'exécution (`resolution_article.dart`) :
/// la fiche doit montrer l'article sur lequel l'écriture partira réellement, pas
/// un autre trouvé par un `contains` plus indulgent. Une fiche qui annonce la
/// cornière 30 pendant que le stock bouge sur la 25 est pire que pas de fiche.
Article? _trouverArticle(String cle, ContexteResume ctx) {
  final t = cle.trim();
  if (t.isEmpty || ctx.articles.isEmpty) return null;
  final r = resoudreArticle(ctx.articles, t);
  if (r.article != null) return r.article;
  // Verdict ambigu : le récapitulatif nomme le mieux placé, et
  // `action_executeur.dart` refusera de son côté tant que ce n'est pas tranché.
  return r.candidats.where((c) => c.compatible).firstOrNull?.article;
}

String _designer(String cle, ContexteResume ctx) {
  final a = _trouverArticle(cle, ctx);
  return a == null ? cle : '${a.nom} [${a.ref}]';
}

String _cleArticle(Map<String, dynamic> p) =>
    _txt(p['articleId'] ?? p['articleNom'] ?? p['nom'] ?? p['article']);

// ─── Le catalogue ─────────────────────────────────────────────────────────────
// Toute écriture possible par l'assistant est ici, et seulement ici.

List<String> Function(Map<String, dynamic>, ContexteResume) _resumeMouvement(
    String sens) {
  return (p, ctx) {
    final cle = _cleArticle(p);
    final a = _trouverArticle(cle, ctx);
    final q = _num(p['quantite']) ?? 0;
    final lignes = <String>[
      'Article : ${_designer(cle, ctx)}',
      '${sens == 'entrée' ? 'Entrée' : 'Sortie'} de ${fmtNombre(q)} '
          '${a?.unite ?? ''}'
          .trim(),
    ];
    if (a != null) {
      final apres = sens == 'entrée' ? a.stock + q : a.stock - q;
      lignes.add('Le stock passera de ${fmtNombre(a.stock)} à '
          '${fmtNombre(apres)} ${a.unite}.');
      if (apres < 0) {
        lignes.add(
            'ATTENTION : le stock deviendrait négatif. Vérifiez la quantité.');
      }
    }
    if (_txt(p['note']).isNotEmpty) lignes.add('Note : ${_txt(p['note'])}');
    if (sens == 'entrée') {
      lignes.add('Aucune dépense n\'est créée : enregistrez-la séparément si '
          'le fournisseur doit être payé.');
    }
    return lignes;
  };
}

final List<ActionIA> kActions = [
  ActionIA(
    type: 'addStock',
    droit: 'stock',
    titre: 'Entrée de stock',
    champs: const [
      ChampAction(
          nom: 'articleId',
          libelle: 'Article',
          type: TypeChamp.article,
          requis: true),
      ChampAction(
          nom: 'quantite',
          libelle: 'Quantité reçue',
          type: TypeChamp.nombre,
          requis: true),
      ChampAction(
          nom: 'note',
          libelle: 'Note',
          type: TypeChamp.texte,
          requis: false,
          aide: 'Numéro de bon de livraison, provenance du camion…'),
    ],
    resume: _resumeMouvement('entrée'),
  ),
  ActionIA(
    type: 'removeStock',
    droit: 'stock',
    titre: 'Sortie de stock',
    champs: const [
      ChampAction(
          nom: 'articleId',
          libelle: 'Article',
          type: TypeChamp.article,
          requis: true),
      ChampAction(
          nom: 'quantite',
          libelle: 'Quantité sortie',
          type: TypeChamp.nombre,
          requis: true),
      ChampAction(
          nom: 'note',
          libelle: 'Motif',
          type: TypeChamp.texte,
          requis: false,
          aide: 'Casse, retour fournisseur, prélèvement chantier…'),
    ],
    resume: _resumeMouvement('sortie'),
  ),
  ActionIA(
    type: 'createArticle',
    droit: 'stock',
    titre: 'Nouvel article au catalogue',
    champs: const [
      ChampAction(
          nom: 'nom',
          libelle: 'Désignation',
          type: TypeChamp.texte,
          requis: true,
          aide: 'Ce que le magasin dit à l\'oral : « Cornière 30×30×3 ».'),
      ChampAction(
          nom: 'categorie',
          libelle: 'Catégorie',
          type: TypeChamp.texte,
          requis: true),
      ChampAction(
          nom: 'unite',
          libelle: 'Unité de vente',
          type: TypeChamp.texte,
          requis: true,
          aide: 'barre, sac, tonne, m², pièce…'),
      ChampAction(
          nom: 'prixVente',
          libelle: 'Prix de vente',
          type: TypeChamp.nombre,
          requis: true,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'prixAchat',
          libelle: 'Prix d\'achat',
          type: TypeChamp.nombre,
          requis: false,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'stockInitial',
          libelle: 'Stock de départ',
          type: TypeChamp.nombre,
          requis: false),
      ChampAction(
          nom: 'stockMin',
          libelle: 'Seuil d\'alerte',
          type: TypeChamp.nombre,
          requis: false),
      ChampAction(
          nom: 'fournisseur',
          libelle: 'Fournisseur habituel',
          type: TypeChamp.texte,
          requis: false),
      // Ce champ n'est pas une formalité : c'est la trace, dans l'action
      // elle-même, que le commerçant a été prévenu qu'une référence voisine
      // existait et qu'il a quand même voulu une nouvelle ligne. Sans lui,
      // `action_executeur.dart` refuse la création dès qu'un doublon est
      // possible. Voir `garderContreDoublon`.
      ChampAction(
          nom: 'confirmerNouveau',
          libelle: 'Créer quand même une nouvelle référence',
          type: TypeChamp.choix,
          requis: false,
          choix: ['oui', 'non'],
          aide: 'À renseigner seulement si un article ressemblant existe déjà.'),
    ],
    resume: (p, ctx) {
      final lignes = <String>[
        'Nouvelle référence : ${_txt(p['nom'])}',
        'Catégorie : ${_txt(p['categorie']).isEmpty ? 'Divers' : _txt(p['categorie'])}'
            ' — vendu à l\'unité « ${_txt(p['unite']).isEmpty ? 'unité' : _txt(p['unite'])} »',
        'Prix de vente : ${fmtGNF((_num(p['prixVente']) ?? 0).round())}',
      ];
      if (_chiffre(p['prixAchat'])) {
        final pa = _num(p['prixAchat'])!;
        lignes.add('Prix d\'achat : ${fmtGNF(pa.round())}');
        final marge = (_num(p['prixVente']) ?? 0) - pa;
        lignes.add('Marge unitaire : ${fmtGNF(marge.round())}'
            '${marge < 0 ? ' — ATTENTION, vous vendriez à perte.' : ''}');
      }
      final brutStock = p['stockInitial'] ?? p['stock'];
      final st = _num(brutStock);
      lignes.add(_chiffre(brutStock) && st != null && st > 0
          ? 'Stock de départ : ${fmtNombre(st)} ${_txt(p['unite'])}'
          : 'Stock de départ : 0 — l\'article sera créé vide.');
      if (_txt(p['fournisseur']).isNotEmpty) {
        lignes.add('Fournisseur : ${_txt(p['fournisseur'])}');
      }
      // Le doublon se voit ici ou nulle part. Une fois la référence créée, deux
      // « cornière 30 » coexistent, le stock se répartit entre les deux au
      // hasard de qui saisit, et plus personne ne sait laquelle est la bonne.
      final semblables = articlesSemblables(ctx.articles, _txt(p['nom']));
      if (semblables.isNotEmpty) {
        lignes.add('');
        lignes.add('ATTENTION : ${semblables.length} article·s ressemblant·s '
            'existent déjà au catalogue :');
        for (final s in semblables.take(4)) {
          final quoi = s.conflits.isNotEmpty
              ? 'diffère : ${s.conflits.join(' ; ')}'
              : 'aucune différence détectée — c\'est probablement le même article';
          lignes.add('  · ${s.article.nom} [${s.article.ref}] — '
              'stock ${fmtNombre(s.article.stock)} ${s.article.unite} ($quoi)');
        }
        lignes.add('Si c\'est l\'un d\'eux, annulez et demandez plutôt une '
            'entrée de stock.');
      }
      return lignes;
    },
  ),
  ActionIA(
    type: 'updateArticle',
    droit: 'stock',
    titre: 'Modifier un article',
    champs: const [
      ChampAction(
          nom: 'articleId',
          libelle: 'Article',
          type: TypeChamp.article,
          requis: true),
      ChampAction(
          nom: 'prixVente',
          libelle: 'Prix de vente',
          type: TypeChamp.nombre,
          requis: false,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'prixAchat',
          libelle: 'Prix d\'achat',
          type: TypeChamp.nombre,
          requis: false,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'stockMin',
          libelle: 'Seuil d\'alerte',
          type: TypeChamp.nombre,
          requis: false),
      ChampAction(
          nom: 'fournisseur',
          libelle: 'Fournisseur',
          type: TypeChamp.texte,
          requis: false),
      ChampAction(
          nom: 'categorie',
          libelle: 'Catégorie',
          type: TypeChamp.texte,
          requis: false),
    ],
    resume: (p, ctx) {
      final lignes = <String>[
        'Article modifié : ${_designer(_cleArticle(p), ctx)}'
      ];
      final paires = <List<String>>[
        [
          'Prix de vente',
          _chiffre(p['prixVente']) ? fmtGNF(_num(p['prixVente'])!.round()) : ''
        ],
        [
          'Prix d\'achat',
          _chiffre(p['prixAchat']) ? fmtGNF(_num(p['prixAchat'])!.round()) : ''
        ],
        [
          'Seuil d\'alerte',
          _chiffre(p['stockMin']) ? fmtNombre(_num(p['stockMin'])!) : ''
        ],
        ['Fournisseur', _txt(p['fournisseur'])],
        ['Catégorie', _txt(p['categorie'])],
      ];
      for (final e in paires) {
        if (e[1].isNotEmpty) lignes.add('${e[0]} → ${e[1]}');
      }
      if (lignes.length == 1) lignes.add('Aucune modification renseignée.');
      lignes.add('Le stock n\'est pas touché.');
      return lignes;
    },
  ),
  ActionIA(
    type: 'createClient',
    // Créer un client fait partie du geste de vendre : c'est au comptoir, face
    // à quelqu'un qui achète, qu'on ouvre une fiche. Le serveur exige déjà
    // « vendre » sur l'opération `client`.
    droit: 'vendre',
    titre: 'Nouveau client',
    champs: const [
      ChampAction(
          nom: 'nom',
          libelle: 'Nom du client',
          type: TypeChamp.texte,
          requis: true),
      ChampAction(
          nom: 'telephone',
          libelle: 'Téléphone',
          type: TypeChamp.texte,
          requis: false),
      ChampAction(
          nom: 'type',
          libelle: 'Type',
          type: TypeChamp.choix,
          requis: false,
          choix: ['professionnel', 'particulier']),
      ChampAction(
          nom: 'quartier',
          libelle: 'Quartier',
          type: TypeChamp.texte,
          requis: false),
      ChampAction(
          nom: 'ville', libelle: 'Ville', type: TypeChamp.texte, requis: false),
    ],
    resume: (p, ctx) {
      final lignes = <String>[
        'Nouveau client : ${_txt(p['nom'])}',
        'Type : ${_txt(p['type']).isEmpty ? 'particulier' : _txt(p['type'])}',
      ];
      if (_txt(p['telephone']).isNotEmpty) {
        lignes.add('Téléphone : ${_txt(p['telephone'])}');
      }
      final lieu = [_txt(p['quartier']), _txt(p['ville'])]
          .where((x) => x.isNotEmpty)
          .join(', ');
      if (lieu.isNotEmpty) lignes.add('Adresse : $lieu');
      return lignes;
    },
  ),
  ActionIA(
    type: 'createVente',
    droit: 'vendre',
    titre: 'Enregistrer une vente',
    champs: const [
      ChampAction(
          nom: 'clientId',
          libelle: 'Client',
          type: TypeChamp.client,
          requis: true),
      ChampAction(
          nom: 'lignes',
          libelle: 'Articles vendus',
          type: TypeChamp.texte,
          requis: true),
      ChampAction(
          nom: 'note', libelle: 'Note', type: TypeChamp.texte, requis: false),
    ],
    resume: (p, ctx) {
      final cle = _txt(p['clientId'] ?? p['client']);
      final cli = ctx.clients.where((c) =>
          c.id == cle || c.nom.toLowerCase() == cle.toLowerCase());
      final lignes = <String>[
        'Client : ${cli.isEmpty ? cle : cli.first.nom}'
      ];
      final items = p['lignes'] is List ? p['lignes'] as List : const [];
      var total = 0.0;
      for (final brut in items) {
        if (brut is! Map) continue;
        final l = Map<String, dynamic>.from(brut);
        final a = _trouverArticle(
            _txt(l['articleId'] ?? l['article'] ?? l['nom']), ctx);
        final q = _num(l['qte'] ?? l['quantite']) ?? 0;
        final pu = _num(l['prixUnitaire']);
        final sous = (pu ?? 0) * q;
        total += sous;
        lignes.add('— ${fmtNombre(q)} ${a?.unite ?? ''} de '
            '${a == null ? _txt(l['articleId']) : '${a.nom} [${a.ref}]'}'
            '${pu == null ? '' : ' à ${fmtGNF(pu.round())} = ${fmtGNF(sous.round())}'}');
        if (a != null && q > a.stock) {
          lignes.add('  ATTENTION : il n\'y a que ${fmtNombre(a.stock)} '
              '${a.unite} en stock.');
        }
      }
      if (total > 0) lignes.add('TOTAL : ${fmtGNF(total.round())}');
      lignes.add('Une facture sera émise, non réglée : encaissez le versement '
          'depuis l\'écran Factures.');
      return lignes;
    },
  ),
  ActionIA(
    type: 'enregistrerPaiement',
    droit: 'vendre',
    titre: 'Encaisser un versement',
    champs: const [
      ChampAction(
          nom: 'factureId',
          libelle: 'Facture',
          type: TypeChamp.facture,
          requis: true),
      ChampAction(
          nom: 'montant',
          libelle: 'Montant reçu',
          type: TypeChamp.nombre,
          requis: true,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'mode',
          libelle: 'Mode de règlement',
          type: TypeChamp.choix,
          requis: false,
          choix: ['espèces', 'mobile money', 'virement', 'chèque']),
      ChampAction(
          nom: 'note', libelle: 'Note', type: TypeChamp.texte, requis: false),
    ],
    resume: (p, ctx) => [
      'Facture : ${_txt(p['factureId'] ?? p['numero'] ?? p['facture'])}',
      'Versement reçu : ${fmtGNF((_num(p['montant']) ?? 0).round())}',
      'Mode : ${_txt(p['mode']).isEmpty ? 'espèces' : _txt(p['mode'])}',
      'Le solde de la facture sera recalculé automatiquement.',
    ],
  ),
  ActionIA(
    type: 'createDepense',
    droit: 'depenses',
    titre: 'Saisir une dépense',
    champs: const [
      ChampAction(
          nom: 'libelle',
          libelle: 'Objet de la dépense',
          type: TypeChamp.texte,
          requis: true),
      ChampAction(
          nom: 'montant',
          libelle: 'Montant',
          type: TypeChamp.nombre,
          requis: true,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'categorie',
          libelle: 'Catégorie',
          type: TypeChamp.texte,
          requis: true,
          aide: 'Doit être exactement l\'une des catégories du magasin.'),
      ChampAction(
          nom: 'beneficiaire',
          libelle: 'Bénéficiaire',
          type: TypeChamp.texte,
          requis: false),
      ChampAction(
          nom: 'date',
          libelle: 'Date',
          type: TypeChamp.date,
          requis: false,
          aide: 'Laissez vide pour aujourd\'hui.'),
    ],
    resume: (p, ctx) {
      final lignes = <String>[
        'Dépense : ${_txt(p['libelle'])}',
        'Montant : ${fmtGNF((_num(p['montant']) ?? 0).round())}',
        'Catégorie : ${_txt(p['categorie'])}',
      ];
      if (_txt(p['beneficiaire']).isNotEmpty) {
        lignes.add('Bénéficiaire : ${_txt(p['beneficiaire'])}');
      }
      lignes.add(_txt(p['date']).isEmpty
          ? 'Date : aujourd\'hui'
          : 'Date : ${_txt(p['date'])}');
      lignes.add('Elle sera enregistrée comme non réglée : saisissez le '
          'règlement séparément.');
      return lignes;
    },
  ),
  ActionIA(
    type: 'createFournisseur',
    // Le catalogue et les entrées de stock sont sous « stock » ; un fournisseur
    // appartient au même circuit d'approvisionnement, et le serveur exige
    // exactement ce droit-là sur l'opération.
    droit: 'stock',
    titre: 'Enregistrer un fournisseur',
    champs: const [
      ChampAction(
          nom: 'nom',
          libelle: 'Nom / Raison sociale',
          type: TypeChamp.texte,
          requis: true),
      ChampAction(
          nom: 'telephone',
          libelle: 'Téléphone',
          type: TypeChamp.texte,
          requis: false),
      ChampAction(
          nom: 'quartier',
          libelle: 'Quartier',
          type: TypeChamp.texte,
          requis: false),
      ChampAction(
          nom: 'ville', libelle: 'Ville', type: TypeChamp.texte, requis: false),
      ChampAction(
          nom: 'email', libelle: 'Email', type: TypeChamp.texte, requis: false),
    ],
    resume: (p, ctx) {
      final lignes = <String>['Fournisseur : ${_txt(p['nom'])}'];
      if (_txt(p['telephone']).isNotEmpty) {
        lignes.add('Téléphone : ${_txt(p['telephone'])}');
      }
      final lieu = [_txt(p['quartier']), _txt(p['ville'])]
          .where((x) => x.isNotEmpty)
          .join(', ');
      if (lieu.isNotEmpty) lignes.add('Lieu : $lieu');
      lignes.add('Il pourra ensuite être choisi lors d\'un achat de stock.');
      return lignes;
    },
  ),
  ActionIA(
    type: 'reglerDepense',
    droit: 'depenses',
    titre: 'Régler une dépense',
    champs: const [
      ChampAction(
          nom: 'depenseId',
          libelle: 'Dépense',
          type: TypeChamp.texte,
          requis: true,
          aide: 'Numéro (DEP-2026-0007) ou libellé exact de la dépense.'),
      ChampAction(
          nom: 'montant',
          libelle: 'Montant versé',
          type: TypeChamp.nombre,
          requis: true,
          suffixe: 'GNF'),
      ChampAction(
          nom: 'mode',
          libelle: 'Mode de règlement',
          type: TypeChamp.choix,
          requis: false,
          choix: ['espèces', 'mobile money', 'virement', 'chèque']),
      ChampAction(
          nom: 'note', libelle: 'Note', type: TypeChamp.texte, requis: false),
    ],
    resume: (p, ctx) => [
      'Dépense : ${_txt(p['depenseId'] ?? p['numero'] ?? p['depense'])}',
      'Versement effectué : ${fmtGNF((_num(p['montant']) ?? 0).round())}',
      'Mode : ${_txt(p['mode']).isEmpty ? 'espèces' : _txt(p['mode'])}',
      'Le reste à payer et le statut seront recalculés automatiquement.',
    ],
  ),
  ActionIA(
    type: 'naviguer',
    // Ouvrir un écran n'écrit nulle part, et le routeur refuse déjà les pages
    // qu'un compte n'a pas le droit de voir. Exiger un droit ici empêcherait
    // l'assistant d'amener quelqu'un devant l'écran dont il lui parle.
    droit: null,
    titre: 'Ouvrir un écran',
    champs: const [
      ChampAction(
          nom: 'page', libelle: 'Écran', type: TypeChamp.texte, requis: true),
    ],
    resume: (p, ctx) => [
      'L\'écran « ${_txt(p['page'] ?? p['vue'])} » sera ouvert.',
      'Rien n\'est modifié.',
    ],
  ),
];

/// Noms alternatifs employés par le modèle pour la même action. Les accepter
/// évite de refuser une intention correcte sur un détail de vocabulaire — mais
/// ils passent par la même serrure, sans exception.
const Map<String, String> kAliasActions = {
  'ouvrirPage': 'naviguer',
  'ajouterPaiement': 'enregistrerPaiement',
  'addDepense': 'createDepense',
};

/// Ramène un nom d'action à celui du catalogue.
String canoniser(String type) => kAliasActions[type] ?? type;

ActionIA? trouverAction(String type) {
  final canon = canoniser(type);
  for (final a in kActions) {
    if (a.type == canon) return a;
  }
  return null;
}

// ─── La serrure ───────────────────────────────────────────────────────────────

@immutable
class Verdict {
  final bool ok;
  final ActionIA? action;

  /// Les champs obligatoires que le modèle a laissés vides.
  final List<ChampAction> manquants;

  /// Pourquoi c'est refusé, dit à l'utilisateur autant qu'au modèle.
  final String? motif;

  const Verdict._(this.ok, this.action, this.manquants, this.motif);

  const Verdict.autorise(ActionIA action, List<ChampAction> manquants)
      : this._(true, action, manquants, null);

  const Verdict.refuse(String motif)
      : this._(false, null, const [], motif);
}

/// Tranche sur une action proposée par le modèle.
///
/// C'est LA fonction de sécurité. Elle ne consulte pas ce que le message système
/// a documenté, seulement le catalogue et les droits du compte. Un modèle
/// retourné qui inventerait `supprimerTout`, ou qui appellerait `createVente`
/// pour un magasinier sans le droit de vendre, se heurte ici — avant que rien ne
/// soit écrit, avant que l'écran n'annonce que c'est fait.
Verdict verifierAction(
  String type,
  Map<String, dynamic> args,
  Utilisateur? compte,
) {
  final action = trouverAction(type);
  if (action == null) {
    return Verdict.refuse(
      'L\'action « $type » n\'existe pas. L\'assistant ne peut rien supprimer, '
      'rien annuler et rien remettre à zéro : ces gestes se font à la main, '
      'depuis l\'écran concerné.',
    );
  }
  final droit = action.droit;
  if (droit != null && !(compte?.aLeDroit(droit) ?? false)) {
    return Verdict.refuse(
      'Ce compte n\'a pas le droit de ${kDroits[droit]}. '
      'L\'action « ${action.type} » lui est refusée.',
    );
  }
  final manquants = action.champs
      .where((c) => c.requis && _txt(args[c.nom]).isEmpty)
      .toList();
  return Verdict.autorise(action, manquants);
}

/// La deuxième serrure : celle qui protège le catalogue de lui-même.
///
/// [verifierAction] répond à « ce compte a-t-il le droit ? ». Celle-ci répond à
/// « est-ce bien un article nouveau ? », et c'est une question de métier, pas de
/// droits : le patron a parfaitement le droit de créer un article, et c'est
/// justement pour ça qu'il peut créer le même deux fois.
///
/// La consigne existe déjà dans le message système. Elle ne suffit pas : un
/// modèle qui a lu « ajoute 10 barres de cornière 30 » enchaîne volontiers sur
/// une création sans avoir appelé `resoudre_article`, surtout quand la
/// conversation est longue. Le prompt propose ; cette fonction dispose.
///
/// Rend le motif du refus, ou `null` si la création peut suivre son cours.
/// [confirme] vaut vrai quand le commerçant a explicitement voulu la nouvelle
/// référence malgré l'avertissement.
String? motifDoublonArticle(
  List<Article> articles,
  String nom, {
  bool confirme = false,
}) {
  if (confirme || nom.trim().isEmpty) return null;
  final semblables = articlesSemblables(articles, nom);
  final identiques = semblables.where((c) => c.compatible).toList();
  if (identiques.isEmpty) return null;

  final liste = identiques
      .take(4)
      .map((c) => '${c.article.nom} [${c.article.ref}] '
          '(stock ${fmtNombre(c.article.stock)} ${c.article.unite})')
      .join(' ; ');

  return identiques.length == 1
      ? '« $nom » existe déjà au catalogue : $liste. '
          'Pour en augmenter le stock, demandez une entrée de stock. '
          'S\'il s\'agit vraiment d\'une autre marchandise — finition, épaisseur '
          'ou longueur différente —, dites-le et la référence sera créée.'
      : '« $nom » ressemble à ${identiques.length} articles déjà au catalogue : '
          '$liste. Précisez lequel vous visez, ou confirmez qu\'il s\'agit d\'une '
          'marchandise réellement différente.';
}

/// Vrai quand le commerçant a levé l'avertissement de doublon.
///
/// Tolérant sur la forme parce que le modèle écrit « oui », « true » ou `true`
/// selon son humeur — mais fermé par défaut : tout ce qui n'est pas un
/// acquiescement franc vaut refus.
bool confirmationNouvelArticle(Map<String, dynamic> args) {
  final v = _txt(args['confirmerNouveau'] ?? args['confirmer']).toLowerCase();
  return v == 'oui' || v == 'true' || v == 'yes' || v == '1';
}

/// Ce que ce compte peut réellement proposer. Un compte inconnu ne peut rien.
List<ActionIA> actionsPermises(Utilisateur? compte) => kActions
    .where((a) => a.droit == null || (compte?.aLeDroit(a.droit!) ?? false))
    .toList();

/// Les actions qui écrivent réellement — celles dont le refus se dit.
List<ActionIA> actionsEcriture(Utilisateur? compte) =>
    actionsPermises(compte).where((a) => a.droit != null).toList();

// ─── Le protocole ─────────────────────────────────────────────────────────────

@immutable
class AppelAction {
  final String type;
  final Map<String, dynamic> params;
  final String libelle;

  /// Une écriture ne peut être exécutée qu'après la fiche affichée à l'humain.
  /// Cette marque est posée exclusivement par [ouvrirFicheActions]. Elle est
  /// volontairement transportée avec l'intention afin que l'exécuteur puisse
  /// refuser aussi un futur raccourci qui oublierait la confirmation.
  final bool confirmationHumaine;

  const AppelAction(
    this.type,
    this.params,
    this.libelle, {
    this.confirmationHumaine = false,
  });
}

/// Extrait le bloc ```action``` d'une réponse, comme le fait l'application web.
///
/// Le bloc porte soit une action unique, soit une liste sous `actions` — un
/// enchaînement se confirme alors d'un seul geste, ce qui évite de faire valider
/// quatre fois de suite la même intention.
({String texte, List<AppelAction> actions}) extraireActions(String contenu) {
  final motif = RegExp(r'```action\s*\n([\s\S]*?)\n?```');
  final trouve = motif.firstMatch(contenu);
  if (trouve == null) return (texte: contenu, actions: const []);

  final texte = contenu.replaceFirst(motif, '').trim();
  try {
    final brut = jsonDecode(trouve.group(1)!.trim());
    final liste = brut is List
        ? brut
        : (brut is Map && brut['actions'] is List)
            ? brut['actions'] as List
            : [brut];

    final actions = <AppelAction>[];
    for (final e in liste) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final type = _txt(m['type']);
      if (type.isEmpty) continue;
      // Le modèle écrit indifféremment les champs à plat ou groupés sous
      // `params` : on accepte les deux plutôt que de rejeter une action
      // correcte sur un détail de forme.
      final imbrique = m['params'] is Map
          ? Map<String, dynamic>.from(m['params'] as Map)
          : <String, dynamic>{};
      final params = <String, dynamic>{...m, ...imbrique}
        ..remove('type')
        ..remove('label')
        ..remove('description')
        ..remove('params');
      actions.add(AppelAction(
          type, params, _txt(m['label']).isEmpty ? type : _txt(m['label'])));
    }
    return (texte: texte, actions: actions);
  } catch (_) {
    // Bloc illisible : on rend le texte sans action plutôt que d'inventer.
    return (texte: texte, actions: const []);
  }
}

/// La marche à suivre dès qu'un article est nommé.
///
/// Taillée sur les droits du compte, comme le reste de la notice : nommer
/// `addStock` à un vendeur qui n'a pas le droit « stock » lui apprendrait le nom
/// d'une porte fermée, et l'enverrait se heurter à un refus qu'il aurait
/// annoncé au commerçant. Un compte sans droit sur le catalogue lit la même
/// règle de prudence, mais sans les noms d'actions.
String _consigneArticle(List<ActionIA> ecriture) {
  final surStock = ecriture.any((a) => a.droit == 'stock');
  final surVente = ecriture.any((a) => a.droit == 'vendre');
  if (!surStock && !surVente) return '';

  const preambule = '''

═══════════ AVANT DE TOUCHER À UN ARTICLE ═══════════
Le commerçant ne parle pas comme le catalogue. Il dit « ajoute 10 barres de cornière 30 » ; le catalogue dit « Cornière L 30×30×3 mm (6 m) ». C'est le même article. En créer un second serait une faute grave : le stock se scinde en deux lignes, la valorisation devient fausse, et personne ne s'en aperçoit avant l'inventaire.

Donc, à chaque fois qu'un article est nommé, dans CET ordre :
1. Appelle resoudre_article avec la désignation telle qu'il l'a dite, sans la reformuler.
2. Suis le verdict qu'il te rend, sans le réinterpréter :''';

  const commun = '''
   · plusieurs candidats → pose UNE question courte pour trancher, en citant ce qui les distingue (épaisseur, longueur, finition, section) et jamais leurs identifiants. N'émets AUCUNE action tant qu'il n'a pas répondu.
   · rien de connu → dis-le franchement et demande ce qui manque.''';

  const fin = '''

Ce qui fait deux articles différents, même à section égale : la finition (noir, galvanisé, inox, prélaqué), l'épaisseur, la longueur de barre, le diamètre. Une cornière 30 galva n'est pas une cornière 30 noire — autre prix, autre fournisseur, autre stock. Ne les confonds jamais, et au moindre doute, demande : une question de dix secondes vaut mieux qu'une écriture à corriger.''';

  if (!surStock) {
    return '''$preambule
   · article trouvé → sers-t'en tel quel, avec son identifiant.
$commun
   · déclinaison voisine seulement → dis ce que tu as trouvé et ce qui diffère. Ce compte n'a pas le droit de modifier le catalogue : renvoie vers le responsable au lieu de promettre une création.$fin''';
  }

  return '''$preambule
   · article trouvé → addStock ou removeStock avec son "articleId". JAMAIS createArticle.
$commun
   · déclinaison voisine seulement → dis ce que tu as trouvé et ce qui diffère, puis DEMANDE s'il veut créer une nouvelle référence.
3. Ne propose createArticle qu'après un accord explicite du commerçant dans la conversation, et ajoute alors "confirmerNouveau":"oui". Sans cet accord, la création sera refusée — quoi que tu aies annoncé.$fin''';
}

/// La notice remise au modèle.
///
/// Ne documente QUE ce que le compte peut faire. Ne pas mentionner une action
/// est la façon la plus sûre de ne pas la voir proposée — mais ce n'est qu'un
/// confort : [verifierAction] refuse de toute façon, et c'est elle qui protège.
String documenterActions(Utilisateur? compte) {
  final ecriture = actionsEcriture(compte);

  final entete = '''
═══════════ ACTIONS : CE QUE TU PEUX PROPOSER ═══════════
Tu ne fais que PROPOSER. Rien ne s'exécute tout seul : le commerçant voit une fiche récapitulative et confirme, ou annule.

Règles, et elles ne se négocient pas :
- Ne dis JAMAIS « c'est fait », « j'ai ajouté », « c'est enregistré ». Tu proposes ; c'est le commerçant qui décide.
- Ne devine JAMAIS un prix, une quantité, un fournisseur. Un champ laissé vide sera demandé au commerçant ; un champ inventé passera inaperçu.
- Vérifie tes chiffres par un outil avant de proposer une écriture. Proposer d'ajouter du stock sans avoir regardé le stock actuel est une faute.
- Ne propose jamais une action que l'utilisateur n'a pas demandée.
- Rien ne permet de supprimer, d'annuler un règlement ni de remettre à zéro. Ne le propose pas et ne prétends pas pouvoir le faire.
${_consigneArticle(ecriture)}''';

  if (ecriture.isEmpty) {
    return '''$entete

CE COMPTE N'A LE DROIT D'ENREGISTRER AUCUNE ÉCRITURE.
Si on te demande d'ajouter du stock, d'enregistrer une vente, de créer un article, un client ou une dépense, réponds franchement que ce compte n'en a pas le droit et qu'il faut voir le responsable. N'invente aucun contournement et ne prétends jamais l'avoir fait. Tu peux en revanche tout consulter et ouvrir les écrans avec « naviguer ».''';
  }

  final lignes = ecriture.map((a) {
    final champs = a.champs
        .map((c) =>
            '"${c.nom}"${c.requis ? '' : '?'}'
            '${c.choix == null ? '' : ':${c.choix!.join('|')}'}')
        .join(', ');
    return '- ${a.type} — ${a.titre.toLowerCase()} '
        '(exige le droit « ${a.droit} ») : {$champs}';
  }).join('\n');

  return '''$entete

Pour proposer, termine ta réponse par :
```action
{"type":"${ecriture.first.type}", …, "label":"ce que tu proposes, en une phrase"}
```
Plusieurs actions liées peuvent être confirmées d'un coup : {"actions":[ … ]}.
Un « ? » marque un champ facultatif.

$lignes
- naviguer — ouvrir un écran : {"page":"accueil|stock|ventes|factures|clients|depenses|finances|rapports|activite|parametres"}''';
}
