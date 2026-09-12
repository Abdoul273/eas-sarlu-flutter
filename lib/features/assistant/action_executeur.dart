import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/format.dart';
import '../../core/auth/auth_state.dart';
import '../../core/db/stores.dart';
import '../dashboard/dashboard_page.dart' show toutesFacturesProvider;
import '../../core/models/models.dart';
import '../../core/sync/op_queue.dart';
import 'ai_actions.dart';
import 'resolution_article.dart';

// ─── L'exécution d'une action confirmée ───────────────────────────────────────
//
// Rien n'arrive ici sans être passé par la fiche et par un appui. Et pourtant
// la première chose que fait ce fichier est de revérifier les droits.
//
// Ce n'est pas de la méfiance envers la fiche : c'est que la sécurité ne doit
// jamais dépendre du chemin emprunté. Si demain quelqu'un appelle `executer`
// depuis un raccourci, un test ou un écran nouveau, la serrure doit tenir sans
// qu'on ait pensé à la reposer. Le serveur fait exactement pareil de son côté.
//
// L'écriture passe par `opQueue`, comme la saisie manuelle : même file hors
// ligne, même gestion des conflits, même revérification des droits à l'arrivée.
// Une action de l'assistant n'est donc pas un canal privilégié — c'est la même
// porte, empruntée autrement.

class EchecAction implements Exception {
  final String message;
  EchecAction(this.message);
  @override
  String toString() => message;
}

class ResultatAction {
  /// Ce qui a été fait, pour le récapitulatif rendu à l'utilisateur.
  final String libelle;

  /// Page à ouvrir, le cas échéant.
  final String? page;

  const ResultatAction(this.libelle, {this.page});
}

class ExecuteurActions {
  final Ref _ref;
  const ExecuteurActions(this._ref);

  Stores get _stores => _ref.read(storesProvider);
  OpQueue get _queue => _ref.read(opQueueProvider);
  Utilisateur? get _compte => _ref.read(authStateProvider).value?.user;

  String get _nomUtilisateur => _compte?.nom ?? 'Utilisateur';

  Future<ResultatAction> executer(AppelAction appel) async {
    // La serrure, avant toute autre vérification. Celles qui suivent portent sur
    // le métier — quantité plausible, article trouvé ; celle-ci porte sur le
    // droit d'agir, et ne consulte que la liste de droits du compte.
    final verdict = verifierAction(appel.type, appel.params, _compte);
    if (!verdict.ok) throw EchecAction(verdict.motif!);
    if (verdict.manquants.isNotEmpty) {
      throw EchecAction('Il manque : '
          '${verdict.manquants.map((c) => c.libelle).join(', ')}.');
    }

    // Les droits ne suffisent pas : un compte autorisé ne donne pas au modèle
    // le droit d'écrire seul. Cette barrière est indépendante de l'interface
    // texte ou vocale et protège toute future entrée vers l'exécuteur.
    if (verdict.action!.droit != null && !appel.confirmationHumaine) {
      throw EchecAction(
        'Cette action doit être relue et confirmée à l’écran par un utilisateur.',
      );
    }

    final p = appel.params;
    switch (verdict.action!.type) {
      case 'addStock':
        return _mouvement(p, 'entrée');
      case 'removeStock':
        return _mouvement(p, 'sortie');
      case 'createArticle':
        return _creerArticle(p);
      case 'updateArticle':
        return _modifierArticle(p);
      case 'createClient':
        return _creerClient(p);
      case 'createFournisseur':
        return _creerFournisseur(p);
      case 'createDepense':
        return _creerDepense(p);
      case 'enregistrerPaiement':
        return _encaisser(p);
      case 'reglerDepense':
        return _reglerDepense(p);
      case 'naviguer':
        final page = _txt(p['page'] ?? p['vue']);
        return ResultatAction('Écran « $page » ouvert', page: page);
      case 'createVente':
        // Une vente engage le stock, la facture et sa numérotation : elle se
        // construit à l'écran Ventes, qui tient déjà ces trois fils ensemble.
        // La refaire ici en raccourci reviendrait à entretenir deux façons de
        // créer une facture — et à en avoir une mal testée.
        throw EchecAction(
            'Une vente s\'enregistre depuis l\'écran Ventes, qui gère le '
            'panier, la remise et la facture. Dites-moi « ouvre les ventes » '
            'et j\'y amène.');
      default:
        throw EchecAction('Action « ${appel.type} » non prise en charge.');
    }
  }

  // ── Stock ───────────────────────────────────────────────────────────────────

  Future<ResultatAction> _mouvement(
      Map<String, dynamic> p, String type) async {
    final article = await _article(p);
    final q = _num(p['quantite']);
    if (q == null || q <= 0) throw EchecAction('Quantité invalide.');
    if (type == 'sortie' && q > article.stock) {
      throw EchecAction('Stock insuffisant : il ne reste que '
          '${fmtNombre(article.stock)} ${article.unite} de ${article.nom}.');
    }

    final mouvement = MouvementStock(
      id: const Uuid().v4(),
      articleId: article.id,
      type: type,
      quantite: q.round(),
      date: DateTime.now().toIso8601String(),
      utilisateur: _nomUtilisateur,
      note: _txt(p['note']).isEmpty
          ? 'Saisi via l\'assistant'
          : _txt(p['note']),
    );
    // Écriture locale AVANT l'envoi, comme la feuille de mouvement : sans
    // cela, le stock annoncé par l'assistant ne bougeait à l'écran qu'à la
    // synchronisation suivante, et hors ligne, jamais.
    await _stores.upsert('mouvement', mouvement);
    await _stores.upsert(
      'article',
      article.copyWith(
        stock: stockApresMouvement(article.stock, type, mouvement.quantite),
      ),
    );
    await _queue.enqueue('mouvement', {'mouvement': mouvement.toJson()});

    final apres = stockApresMouvement(article.stock, type, mouvement.quantite);
    return ResultatAction(
        '${article.nom} : ${type == 'entrée' ? '+' : '−'}${fmtNombre(q)} '
        '${article.unite} (stock ${fmtNombre(article.stock)} → '
        '${fmtNombre(apres)})');
  }

  Future<ResultatAction> _creerArticle(Map<String, dynamic> p) async {
    final nom = _txt(p['nom']);

    // Avant d'ouvrir une ligne au catalogue, on regarde s'il n'y en a pas déjà
    // une. C'est le refus le plus utile de tout ce fichier : un doublon ne
    // déclenche aucune alarme, ne casse rien tout de suite, et se découvre six
    // mois plus tard quand l'inventaire ne tombe plus juste.
    final motif = motifDoublonArticle(
      await _stores.getArticles(),
      nom,
      confirme: confirmationNouvelArticle(p),
    );
    if (motif != null) throw EchecAction(motif);

    final categorie =
        _txt(p['categorie']).isEmpty ? 'Divers' : _txt(p['categorie']);
    final article = Article(
      id: const Uuid().v4(),
      ref: _txt(p['ref']).isEmpty
          ? '${categorie.toUpperCase().padRight(3).substring(0, 3).trim()}-'
              '${DateTime.now().millisecondsSinceEpoch % 10000}'
          : _txt(p['ref']),
      nom: nom,
      categorie: categorie,
      unite: _txt(p['unite']).isEmpty ? 'unité' : _txt(p['unite']),
      prixAchat: (_num(p['prixAchat']) ?? 0).round(),
      prixVente: (_num(p['prixVente']) ?? 0).round(),
      stock: (_num(p['stockInitial'] ?? p['stock']) ?? 0).round(),
      stockMin: (_num(p['stockMin']) ?? 5).round(),
      fournisseur: _txt(p['fournisseur']),
    );

    await _stores.upsert('article', article);
    await _queue.enqueue('article', {'record': article.toJson()});
    return ResultatAction('Article créé : ${article.nom} [${article.ref}]');
  }

  Future<ResultatAction> _modifierArticle(Map<String, dynamic> p) async {
    final article = await _article(p);
    final modifs = <String>[];

    int? maj(String cle, int actuel, String libelle) {
      final brut = _num(p[cle]);
      if (brut == null) return null;
      final v = brut.round();
      if (v == actuel) return null;
      if (v < 0) throw EchecAction('Valeur négative pour $libelle.');
      modifs.add('$libelle : ${fmtNombre(actuel)} → ${fmtNombre(v)}');
      return v;
    }

    final prixVente = maj('prixVente', article.prixVente, 'prix de vente');
    final prixAchat = maj('prixAchat', article.prixAchat, 'prix d\'achat');
    final stockMin = maj('stockMin', article.stockMin, 'seuil d\'alerte');

    final fournisseur = _txt(p['fournisseur']);
    final categorie = _txt(p['categorie']);
    if (fournisseur.isNotEmpty && fournisseur != article.fournisseur) {
      modifs.add('fournisseur → $fournisseur');
    }
    if (categorie.isNotEmpty && categorie != article.categorie) {
      modifs.add('catégorie → $categorie');
    }
    if (modifs.isEmpty) {
      throw EchecAction('Aucun changement à appliquer sur ${article.nom}.');
    }

    // On repart de l'article existant : une mise à jour de prix ne doit pas
    // effacer la photo ni la provenance parce qu'elles n'ont pas été répétées.
    final maj2 = article.copyWith(
      prixVente: prixVente ?? article.prixVente,
      prixAchat: prixAchat ?? article.prixAchat,
      stockMin: stockMin ?? article.stockMin,
      fournisseur: fournisseur.isEmpty ? article.fournisseur : fournisseur,
      categorie: categorie.isEmpty ? article.categorie : categorie,
    );

    await _stores.upsert('article', maj2);
    await _queue.enqueue('article', {
      'record': maj2.toJson(),
      if (article.rev != null) 'baseRev': article.rev,
    });
    return ResultatAction('${article.nom} : ${modifs.join(', ')}');
  }

  // ── Clients, dépenses, encaissements ────────────────────────────────────────

  Future<ResultatAction> _creerClient(Map<String, dynamic> p) async {
    final client = Client(
      id: const Uuid().v4(),
      nom: _txt(p['nom']),
      type: _txt(p['type']) == 'professionnel' ? 'professionnel' : 'particulier',
      telephone: _txt(p['telephone']),
      quartier: _txt(p['quartier']),
      ville: _txt(p['ville']),
      creeLe: DateTime.now().toIso8601String(),
    );
    await _stores.upsert('client', client);
    await _queue.enqueue('client', {'record': client.toJson()});
    return ResultatAction('Client créé : ${client.nom}');
  }

  /// Enregistre un fournisseur.
  ///
  /// Un doublon est refusé plutôt que créé : deux « Import Turquie » dans la
  /// liste et le gérant ne sait plus lequel choisir au moment d'un achat, ni à
  /// qui rattacher l'historique.
  Future<ResultatAction> _creerFournisseur(Map<String, dynamic> p) async {
    final nom = _txt(p['nom']);
    if (nom.isEmpty) throw EchecAction('Le nom du fournisseur est obligatoire.');

    final existants = await _stores.getFournisseurs();
    final deja = existants.where(
        (f) => f.nom.trim().toLowerCase() == nom.trim().toLowerCase());
    if (deja.isNotEmpty) {
      throw EchecAction('« ${deja.first.nom} » est déjà enregistré '
          'comme fournisseur.');
    }

    final fournisseur = Fournisseur(
      id: const Uuid().v4(),
      nom: nom,
      telephone: _txt(p['telephone']),
      email: _txt(p['email']),
      adresse: _txt(p['adresse']),
      quartier: _txt(p['quartier']),
      ville: _txt(p['ville']),
      creeLe: DateTime.now().toIso8601String(),
    );
    await _stores.upsert('fournisseur', fournisseur);
    await _queue.enqueue('fournisseur', {'record': fournisseur.toJson()});
    return ResultatAction('Fournisseur créé : ${fournisseur.nom}');
  }

  Future<ResultatAction> _creerDepense(Map<String, dynamic> p) async {
    final montant = _num(p['montant']);
    if (montant == null || montant <= 0) {
      throw EchecAction('Montant de la dépense invalide.');
    }
    final rawDate = _txt(p['date']);
    final parsedDate = rawDate.isNotEmpty ? DateTime.tryParse(rawDate) : null;
    final dateStr = (parsedDate ?? DateTime.now()).toIso8601String();
    final depense = Depense(
      id: const Uuid().v4(),
      date: dateStr,
      categorie: _txt(p['categorie']),
      libelle: _txt(p['libelle']),
      beneficiaire: _txt(p['beneficiaire']),
      montant: montant.round(),
      note: 'Saisie via l\'assistant',
    );
    await _stores.upsert('depense', depense);
    await _queue.enqueue('depense', {'record': depense.toJson()});
    return ResultatAction(
        'Dépense « ${depense.libelle} » ${fmtGNF(montant.round())}');
  }

  Future<ResultatAction> _encaisser(Map<String, dynamic> p) async {
    final cle = _txt(p['factureId'] ?? p['numero'] ?? p['facture']);
    final factures = _ref.read(toutesFacturesProvider).valueOrNull ?? const [];
    final trouvees = factures.where((f) =>
        f.id == cle || f.numero.toLowerCase() == cle.toLowerCase());
    if (trouvees.isEmpty) throw EchecAction('Facture introuvable : « $cle ».');
    final facture = trouvees.first;

    final montant = _num(p['montant']);
    if (montant == null || montant <= 0) {
      throw EchecAction('Montant du versement invalide.');
    }
    final reste = resteDu(facture);
    // Le trop-perçu existe et se gère ailleurs, mais il ne doit jamais naître
    // d'une proposition automatique : c'est presque toujours une erreur de
    // lecture d'un chiffre, pas une intention du client.
    if (montant > reste) {
      throw EchecAction('Versement de ${fmtGNF(montant.round())} supérieur au '
          'reste dû sur ${facture.numero} (${fmtGNF(reste)}).');
    }

    final paiement = Paiement(
      id: const Uuid().v4(),
      date: DateTime.now().toIso8601String(),
      montant: montant.round(),
      mode: _txt(p['mode']).isEmpty ? 'espèces' : _txt(p['mode']),
      note: _txt(p['note']),
      utilisateur: _nomUtilisateur,
    );

    await _stores.upsert('facture', facture.avecPaiement(paiement));
    await _queue.enqueue('facture_paiement', {
      'factureId': facture.id,
      'paiement': paiement.toJson(),
      if (facture.rev != null) 'baseRev': facture.rev,
    });
    return ResultatAction('${facture.numero} : versement de '
        '${fmtGNF(montant.round())} — reste '
        '${fmtGNF((reste - montant).round())}');
  }

  // ── Dépenses ────────────────────────────────────────────────────────────────

  /// Enregistre un règlement sur une dépense déjà saisie.
  ///
  /// Symétrique exact de `_encaisser`, dans l'autre sens : l'assistant savait
  /// créer une dépense mais pas la solder, si bien que toute dépense saisie par
  /// son intermédiaire restait éternellement « non réglée » — et faussait la
  /// dette fournisseur affichée partout ailleurs.
  Future<ResultatAction> _reglerDepense(Map<String, dynamic> p) async {
    final cle = _txt(p['depenseId'] ?? p['numero'] ?? p['depense']);
    if (cle.isEmpty) throw EchecAction('Aucune dépense désignée.');

    final depenses = await _stores.getDepenses();
    final trouvees = depenses.where((d) =>
        d.id == cle ||
        d.numero.toLowerCase() == cle.toLowerCase() ||
        d.libelle.toLowerCase() == cle.toLowerCase());
    if (trouvees.isEmpty) throw EchecAction('Dépense introuvable : « $cle ».');
    // Une désignation qui vise plusieurs dépenses n'en vise aucune : payer la
    // mauvaise est plus grave que de redemander laquelle.
    if (trouvees.length > 1) {
      throw EchecAction('« $cle » correspond à ${trouvees.length} dépenses. '
          'Précisez le numéro : '
          '${trouvees.take(4).map((d) => d.numero).join(', ')}.');
    }
    final depense = trouvees.first;

    final montant = _num(p['montant']);
    if (montant == null || montant <= 0) {
      throw EchecAction('Montant du règlement invalide.');
    }
    final reste = resteAPayer(depense);
    if (reste == 0) {
      throw EchecAction('${depense.numero} est déjà entièrement réglée.');
    }
    // Comme pour un encaissement : un trop-versé se décide, il ne se produit
    // pas par accident au détour d'un chiffre mal lu.
    if (montant > reste) {
      throw EchecAction('Règlement de ${fmtGNF(montant.round())} supérieur au '
          'reste à payer sur ${depense.numero} (${fmtGNF(reste)}).');
    }

    final reglement = Reglement(
      id: const Uuid().v4(),
      date: DateTime.now().toIso8601String(),
      montant: montant.round(),
      mode: _txt(p['mode']).isEmpty ? 'espèces' : _txt(p['mode']),
      note: _txt(p['note']),
      utilisateur: _nomUtilisateur,
    );

    await _stores.upsert('depense', depense.avecReglement(reglement));
    await _queue.enqueue('depense_reglement', {
      'depenseId': depense.id,
      'reglement': reglement.toJson(),
      if (depense.rev != null) 'baseRev': depense.rev,
    });

    final restant = (reste - montant).round();
    return ResultatAction('${depense.numero} : règlement de '
        '${fmtGNF(montant.round())} — '
        '${restant == 0 ? 'dépense soldée' : 'reste ${fmtGNF(restant)}'}');
  }

  // ── Recherche d'article, tolérante mais jamais devinée ──────────────────────

  /// Retrouve l'article visé — ou refuse, en disant pourquoi.
  ///
  /// La recherche passe par `resolution_article.dart`, qui lit une désignation
  /// de quincaillerie comme le magasin la lit : famille, section, épaisseur,
  /// longueur, finition. Un simple `contains` ne retrouvait pas « Cornière L
  /// 30×30×3 mm (6 m) » à partir de « cornière 30 » — et faisait donc créer un
  /// doublon —, tout en confondant volontiers une galva avec une noire.
  ///
  /// Le refus reste la règle dès qu'un doute subsiste : bouger le stock du
  /// mauvais article se répare, mais seulement si quelqu'un s'en aperçoit.
  Future<Article> _article(Map<String, dynamic> p) async {
    final cle =
        _txt(p['articleId'] ?? p['articleNom'] ?? p['nom'] ?? p['article']);
    if (cle.isEmpty) throw EchecAction('Aucun article indiqué.');
    final articles = await _stores.getArticles();
    final r = resoudreArticle(articles, cle);

    switch (r.verdict) {
      case VerdictArticle.exact:
        return r.article!;

      case VerdictArticle.ambigu:
        final choix = r.candidats
            .where((c) => c.compatible)
            .take(5)
            .map((c) => '${c.article.nom} [${c.article.ref}]')
            .join(', ');
        throw EchecAction('« $cle » correspond à plusieurs articles : $choix. '
            'Précisez la référence, l\'épaisseur ou la longueur.');

      case VerdictArticle.variante:
        final voisins = r.candidats
            .take(3)
            .map((c) => '${c.article.nom} [${c.article.ref}] — '
                '${c.conflits.join(' ; ')}')
            .join(' | ');
        throw EchecAction('Aucun article ne correspond exactement à « $cle ». '
            'Le catalogue a des déclinaisons voisines : $voisins. '
            'Choisissez-en une, ou créez la référence manquante.');

      case VerdictArticle.aucun:
        throw EchecAction('Aucun article ne correspond à « $cle ».');
    }
  }
}

String _txt(dynamic v) => (v ?? '').toString().trim();

double? _num(dynamic v) {
  final brut = _txt(v).replaceAll(RegExp(r'[^\d.,-]'), '').replaceAll(',', '.');
  if (brut.isEmpty) return null;
  return double.tryParse(brut);
}

final executeurActionsProvider =
    Provider<ExecuteurActions>((ref) => ExecuteurActions(ref));
