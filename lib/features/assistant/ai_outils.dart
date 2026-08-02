import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../../app/format.dart';
import '../../core/models/models.dart';
import '../activite/activite_page.dart' show ActiviteEntree;

import 'ai_client.dart';
import 'ai_config.dart';
import 'resolution_article.dart';

// ─── Outils de l'assistant : interroger le magasin au lieu de le lire en bloc ──
//
// Transposition de `src/lib/ai-outils.ts` de l'application web.
//
// L'assistant Flutter partait jusqu'ici avec un contexte réduit à la chaîne
// « magasin matériaux métalliques Conakry » : il ne savait rien du stock, des
// ventes, des clients ni de la caisse, et répondait donc de mémoire — c'est-à-
// dire en inventant. Le relais n'était même pas configuré, si bien qu'aucune
// question n'aboutissait.
//
// Le principe repris du web : le contexte n'est qu'un tableau de bord court, et
// le modèle va chercher lui-même le détail dont il a besoin, outil par outil.
// Il peut enchaîner — bilan du mois, puis rentabilité des articles, puis fiche
// du client qui traîne — avant de répondre.
//
// Le protocole est volontairement textuel (`<outil>…</outil>`) plutôt que le
// « function calling » natif des fournisseurs : il traverse à l'identique
// Claude, Gemini et le relais serveur, qui n'a ni à connaître ces outils ni à
// détenir les données du magasin. Le calcul reste sur le téléphone du
// commerçant, donc les données ne sortent jamais.

/// L'instantané des données du magasin sur lequel les outils travaillent.
class DonneesMagasin {
  final List<Article> articles;
  final List<Vente> ventes;
  final List<Client> clients;
  final List<Facture> factures;
  final List<Depense> depenses;
  final List<MouvementStock> mouvements;
  final List<ActiviteEntree> activites;

  /// Faux pour un vendeur : les prix d'achat et les marges lui sont masqués.
  final bool voitPrixAchat;

  const DonneesMagasin({
    required this.articles,
    required this.ventes,
    required this.clients,
    required this.factures,
    required this.depenses,
    required this.mouvements,
    this.activites = const [],
    required this.voitPrixAchat,
  });
}

typedef ExecuteurOutil = String Function(
    Map<String, dynamic> args, DonneesMagasin d);

class OutilIA {
  final String nom;

  /// Ce que l'outil rend, et quand y recourir. Lu par le modèle, pas par l'humain.
  final String description;

  /// Paramètres acceptés, décrits en une ligne chacun.
  final Map<String, String> parametres;

  /// Vrai si l'outil expose des prix d'achat ou des marges.
  final bool confidentiel;
  final ExecuteurOutil executer;

  const OutilIA({
    required this.nom,
    required this.description,
    this.parametres = const {},
    this.confidentiel = false,
    required this.executer,
  });
}

// ─── Utilitaires communs ──────────────────────────────────────────────────────

String _jour(String? iso) =>
    (iso ?? '').length >= 10 ? iso!.substring(0, 10) : (iso ?? '');

num _nb(dynamic v, num defaut) {
  if (v is num) return v;
  final n = num.tryParse('$v');
  return n ?? defaut;
}

String _pct(num part, num tout) =>
    tout > 0 ? '${(part / tout * 100).toStringAsFixed(1)} %' : '—';

String _fmtDate(String? iso, {bool court = false}) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '—';
  return DateFormat(court ? 'd MMM' : 'd MMM yyyy', 'fr_FR').format(d);
}

/// Rapproche un texte libre d'un enregistrement : identifiant, référence, nom.
bool _correspond(List<String?> valeurs, String terme) {
  final t = terme.toLowerCase().trim();
  if (t.isEmpty) return false;
  return valeurs.any((v) {
    final s = (v ?? '').toLowerCase();
    return s.isNotEmpty && (s == t || s.contains(t));
  });
}

// `stockStatut`, `resteDu`, `resteAPayer`, `soldeClient` et `enRetard` viennent
// du moteur financier. L'assistant en avait sa propre copie de chacun : il
// pouvait donc répondre « en rupture » sur un article que l'écran Stock
// affichait « faible ». Un assistant qui contredit l'application vaut moins que
// pas d'assistant du tout.

int _joursDepuis(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return 0;
  return DateTime.now().difference(d).inDays;
}

// Les bornes de période viennent elles aussi du moteur (`Periode.mois`,
// `.annee`, `.derniersJours`). Attention : ces fabriques comptent les mois à
// partir de un, alors que les copies remplacées ici partaient de zéro.

/// Traduit la période demandée par le modèle en bornes de dates.
///
/// On accepte le vocabulaire naturel (« ce mois », « mois dernier », « année »)
/// parce qu'un modèle qui doit d'abord calculer des dates ISO se trompe de mois
/// une fois sur cinq — et une erreur de bornes fausse silencieusement tout un
/// bilan.
({Periode? periode, String libelle}) resoudrePeriode(Map<String, dynamic> args,
    [DateTime? maintenant]) {
  final now = maintenant ?? DateTime.now();
  final p = (args['periode'] ?? '').toString().toLowerCase().trim();

  if (args['debut'] != null && args['fin'] != null) {
    final debut = _jour('${args['debut']}');
    final fin = _jour('${args['fin']}');
    return (
      periode: Periode(debut: debut, fin: fin),
      libelle: 'du ${_fmtDate(debut)} au ${_fmtDate(fin)}',
    );
  }
  if (p.isEmpty || p == 'tout' || p == 'total' || p == 'historique') {
    return (periode: null, libelle: 'depuis l\'ouverture');
  }
  if (p == 'mois' || p == 'ce_mois' || p == 'mois_courant') {
    return (
      periode: Periode.mois(now.year, now.month),
      libelle:
          'mois en cours (${DateFormat('MMMM yyyy', 'fr_FR').format(now)})',
    );
  }
  if (p == 'mois_dernier' || p == 'mois_precedent') {
    final d = DateTime(now.year, now.month - 1, 1);
    return (
      periode: Periode.mois(d.year, d.month),
      libelle: 'mois précédent (${DateFormat('MMMM yyyy', 'fr_FR').format(d)})',
    );
  }
  if (p == 'annee' || p == 'année' || p == 'cette_annee') {
    return (periode: Periode.annee(now.year), libelle: 'année ${now.year}');
  }
  if (p == 'annee_derniere' || p == 'annee_precedente') {
    return (
      periode: Periode.annee(now.year - 1),
      libelle: 'année ${now.year - 1}'
    );
  }

  // « 7j », « 30j », « 90 jours » : le format le plus souvent produit.
  final jours = RegExp(r'^(\d+)\s*j').firstMatch(p);
  if (jours != null) {
    final n = (int.tryParse(jours.group(1)!) ?? 30).clamp(1, 3650);
    return (
      periode: Periode.derniersJours(n, now),
      libelle: '$n derniers jours'
    );
  }
  // Un mois nommé seul (« 2026-03 ») reste possible.
  final mm = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(p);
  if (mm != null) {
    return (
      periode: Periode.mois(int.parse(mm.group(1)!), int.parse(mm.group(2)!)),
      libelle: '${mm.group(1)}-${mm.group(2)}',
    );
  }
  return (periode: null, libelle: 'depuis l\'ouverture');
}

/// Ventes d'une période, du plus récent au plus ancien.
List<Vente> _ventesDe(List<Vente> ventes, Periode? p) =>
    ventes.where((v) => dansPeriode(v.date, p)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

Bilan _bilan(DonneesMagasin d, Periode? p) => calculerBilan(
      ventes: d.ventes,
      factures: d.factures,
      depenses: d.depenses,
      articles: d.articles,
      // Sans bornes, le bilan porte sur tout l'historique.
      periode: p,
    );

Map<String, Article> _parId(List<Article> articles) =>
    {for (final a in articles) a.id: a};

// ─── Les outils ───────────────────────────────────────────────────────────────

final _bilanFinancier = OutilIA(
  nom: 'bilan_financier',
  description:
      'Le compte de résultat et la trésorerie d\'une période : chiffre d\'affaires, coût des '
      'marchandises vendues, marge brute, charges d\'exploitation, résultat, encaissements, '
      'décaissements, créances clients et dettes fournisseurs, avec le détail par catégorie de '
      'dépense. C\'est le SEUL outil qui donne le bénéfice réel : la marge brute seule ignore le '
      'loyer, les salaires et le carburant.',
  parametres: {
    'periode':
        '« mois », « mois_dernier », « annee », « 30j », « 90j », ou « tout ». Par défaut : tout.',
    'debut':
        'Optionnel, date ISO aaaa-mm-jj, à utiliser avec « fin » pour une période sur mesure.',
    'fin': 'Optionnel, date ISO aaaa-mm-jj.',
  },
  confidentiel: true,
  executer: (args, d) {
    final r = resoudrePeriode(args);
    final b = _bilan(d, r.periode);
    final l = <String>['BILAN — ${r.libelle}', ''];

    l.add('Résultat (ce que le commerce gagne, qui que ce soit qui ait payé quand) :');
    l.add('- Chiffre d\'affaires : ${gnfCompact(b.chiffreAffaires)} sur ${b.nbVentes} ventes');
    l.add('- Coût d\'achat des marchandises vendues : ${gnfCompact(b.coutMarchandises)}');
    l.add('- Marge brute : ${gnfCompact(b.margeBrute)}'
        '${b.tauxMarge != null ? ' (${b.tauxMarge!.toStringAsFixed(1)} % du CA)' : ''}');
    l.add('- Charges d\'exploitation engagées : ${gnfCompact(b.chargesExploitation)}');
    l.add('- RÉSULTAT D\'EXPLOITATION : ${gnfCompact(b.resultatExploitation)} '
        '${b.resultatExploitation >= 0 ? '(bénéfice)' : '(PERTE)'}');
    l.add('');
    l.add('Trésorerie (ce qui est réellement passé par la caisse) :');
    l.add('- Encaissements clients : ${gnfCompact(b.encaissements)}');
    l.add('- Décaissements, toutes natures : ${gnfCompact(b.decaissements)}');
    l.add('- Flux net de trésorerie : ${gnfCompact(b.fluxTresorerie)}');
    l.add('');
    l.add('Sorties de caisse hors résultat (elles ne sont pas des charges de la période) :');
    l.add('- Achats de marchandise (partent au stock) : ${gnfCompact(b.achatsMarchandises)}');
    l.add('- Investissements (durent des années) : ${gnfCompact(b.investissements)}');
    l.add('');
    l.add('Position à la fin de la période :');
    l.add('- Créances clients (ils nous doivent) : ${gnfCompact(b.creancesClients)}');
    l.add('- Dettes fournisseurs (nous devons) : ${gnfCompact(b.dettesFournisseurs)}');
    l.add('- Position nette : ${gnfCompact(b.positionNette)}');

    if (b.parCategorie.isNotEmpty) {
      l.add('');
      l.add('Dépenses par catégorie (${b.nbDepenses} pièces) — engagé / décaissé :');
      for (final c in b.parCategorie.take(15)) {
        l.add('- ${c.categorie} [${libelleNature[c.nature]}] : engagé ${gnfCompact(c.engage)}, '
            'décaissé ${gnfCompact(c.decaisse)} (${c.nombre} pièce·s)');
      }
    }
    l.add('');
    l.add('Rappel : n\'additionne jamais le résultat et le flux de trésorerie, '
        'ce sont deux lectures du même mois.');
    return l.join('\n');
  },
);

final _rentabiliteArticles = OutilIA(
  nom: 'rentabilite_articles',
  description:
      'Classe les articles selon ce qu\'ils rapportent réellement sur une période : quantité '
      'vendue, chiffre d\'affaires, marge dégagée, taux de marge, et rotation du stock (en jours '
      'de couverture au rythme actuel). À utiliser pour savoir quoi mettre en avant, quoi arrêter '
      'de stocker, où l\'argent dort.',
  parametres: {
    'periode':
        '« mois », « mois_dernier », « annee », « 30j », « 90j » ou « tout ». Par défaut : 90j.',
    'tri':
        '« marge » (défaut), « ca », « quantite », « rotation » (les plus lents d\'abord), ou « dormant » (aucune vente).',
    'limite': 'Nombre de lignes, 10 par défaut, 40 au maximum.',
  },
  confidentiel: true,
  executer: (args, d) {
    final r = resoudrePeriode({
      'periode': args['periode'] ?? '90j',
      'debut': args['debut'],
      'fin': args['fin'],
    });
    final limite = _nb(args['limite'], 10).clamp(1, 40).toInt();
    final tri = (args['tri'] ?? 'marge').toString().toLowerCase();
    final ventes = _ventesDe(d.ventes, r.periode);

    // La couverture n'a de sens que rapportée à la durée réellement observée.
    // Sans période, on compte depuis la première vente enregistrée : prendre
    // une année forfaitaire sur un magasin ouvert depuis trois mois diviserait
    // le rythme par quatre et ferait passer une rupture imminente pour un stock
    // de plusieurs années.
    final int jours;
    if (r.periode != null) {
      final debut = DateTime.tryParse(r.periode!.debut);
      final fin = DateTime.tryParse(r.periode!.fin);
      jours = (debut != null && fin != null)
          ? math.max(1, fin.difference(debut).inDays + 1)
          : 1;
    } else {
      final premiere = ventes.isEmpty ? null : ventes.last.date;
      jours = premiere == null ? 1 : math.max(1, _joursDepuis(premiere));
    }

    final parArticle = <String, ({Article art, num qte, num ca, num marge})>{};
    for (final a in d.articles) {
      parArticle[a.id] = (art: a, qte: 0, ca: 0, marge: 0);
    }
    for (final v in ventes) {
      for (final li in v.lignes) {
        final e = parArticle[li.articleId];
        if (e == null) continue;
        parArticle[li.articleId] = (
          art: e.art,
          qte: e.qte + li.qte,
          ca: e.ca + li.total,
          marge: e.marge + li.total - e.art.prixAchat * li.qte,
        );
      }
    }

    var lignes = parArticle.values.toList();
    if (tri == 'dormant') {
      lignes = lignes.where((x) => x.qte == 0 && x.art.stock > 0).toList();
    } else {
      lignes = lignes.where((x) => x.qte > 0 || x.art.stock > 0).toList();
    }

    double couverture(({Article art, num qte, num ca, num marge}) x) =>
        x.qte > 0 ? x.art.stock * jours / x.qte : double.infinity;

    lignes.sort((a, b) {
      switch (tri) {
        case 'ca':
          return (b.ca - a.ca).sign.toInt();
        case 'quantite':
          return (b.qte - a.qte).sign.toInt();
        case 'rotation':
        case 'dormant':
          final c = couverture(b).compareTo(couverture(a));
          if (c != 0) return c;
          return (b.art.prixAchat * b.art.stock - a.art.prixAchat * a.art.stock)
              .sign
              .toInt();
        default:
          return (b.marge - a.marge).sign.toInt();
      }
    });

    final out = <String>[
      tri == 'dormant'
          ? 'ARTICLES DORMANTS (aucune vente sur ${r.libelle}, mais du stock immobilisé)'
          : 'RENTABILITÉ DES ARTICLES — ${r.libelle}, triés par $tri',
      '',
    ];
    for (final x in lignes.take(limite)) {
      final c = couverture(x);
      out.add('- ${x.art.nom} [${x.art.ref}] : ${fmtNombre(x.qte)} ${x.art.unite} vendus, '
          'CA ${gnfCompact(x.ca)}, marge ${gnfCompact(x.marge)} (${_pct(x.marge, x.ca)}) | '
          'stock ${fmtNombre(x.art.stock)} ${x.art.unite} = '
          '${gnfCompact(x.art.prixAchat * x.art.stock)} immobilisés | '
          'couverture ${c.isFinite ? '${c.round()} j' : 'aucune vente'}');
    }
    if (lignes.length > limite) {
      out.add('… et ${lignes.length - limite} autres articles.');
    }
    out.add('');
    out.add('Total immobilisé au prix d\'achat sur ces '
        '${math.min(limite, lignes.length)} lignes : '
        '${gnfCompact(lignes.take(limite).fold<num>(0, (s, x) => s + x.art.prixAchat * x.art.stock))}');
    return out.join('\n');
  },
);

final _ficheArticle = OutilIA(
  nom: 'fiche_article',
  description:
      'Tout ce que le magasin sait d\'un article : prix, stock, seuil d\'alerte, fournisseur, '
      'provenance, ses dernières ventes, ses derniers mouvements de stock, son rythme de vente et '
      'le nombre de jours qu\'il reste avant rupture.',
  parametres: {'terme': 'Nom, référence ou identifiant de l\'article. Obligatoire.'},
  confidentiel: true,
  executer: (args, d) {
    final terme = (args['terme'] ?? args['article'] ?? '').toString().trim();
    final trouves =
        d.articles.where((a) => _correspond([a.id, a.ref, a.nom], terme)).toList();
    if (trouves.isEmpty) {
      return 'Aucun article ne correspond à « $terme ». '
          'Utilise lister_articles pour voir le catalogue.';
    }
    if (trouves.length > 5) {
      return '« $terme » correspond à ${trouves.length} articles : '
          '${trouves.take(12).map((a) => '${a.nom} [${a.ref}]').join(', ')}… Précise.';
    }

    return trouves.map((a) {
      final lignes = <({Vente v, LigneVente l})>[
        for (final v in d.ventes)
          for (final l in v.lignes)
            if (l.articleId == a.id) (v: v, l: l),
      ];
      final qteTotale = lignes.fold<int>(0, (s, x) => s + x.l.qte);
      final caTotal = lignes.fold<int>(0, (s, x) => s + x.l.total);
      final dates = lignes.map((x) => x.v.date).toList()..sort();
      final joursActifs =
          dates.isEmpty ? 0 : math.max(1, _joursDepuis(dates.first));
      final parJour = joursActifs > 0 ? qteTotale / joursActifs : 0.0;

      final mvts = d.mouvements.where((m) => m.articleId == a.id).toList()
        ..sort((x, y) => y.date.compareTo(x.date));
      final dernieres = lignes.toList()
        ..sort((x, y) => y.v.date.compareTo(x.v.date));

      final out = <String>[
        'ARTICLE ${a.nom} [${a.ref}] — id ${a.id}',
        'Catégorie : ${a.categorie} | Unité : ${a.unite} | '
            'Provenance : ${a.provenance.isEmpty ? 'non renseignée' : a.provenance} | '
            'Fournisseur : ${a.fournisseur.isEmpty ? 'non renseigné' : a.fournisseur}',
        'Stock : ${fmtNombre(a.stock)} ${a.unite} (seuil d\'alerte ${fmtNombre(a.stockMin)}) '
            '→ ${stockStatut(a)}',
        if (d.voitPrixAchat)
          'Prix d\'achat : ${fmtNombre(a.prixAchat)} GNF | Prix de vente : ${fmtNombre(a.prixVente)} GNF | '
              'Marge unitaire : ${fmtNombre(a.prixVente - a.prixAchat)} GNF '
              '(${_pct(a.prixVente - a.prixAchat, a.prixVente)})'
        else
          'Prix de vente : ${fmtNombre(a.prixVente)} GNF',
        if (d.voitPrixAchat)
          'Trésorerie immobilisée dans cet article : ${gnfCompact(a.prixAchat * a.stock)}',
        'Historique : ${fmtNombre(qteTotale)} ${a.unite} vendus au total, CA ${gnfCompact(caTotal)}'
            '${d.voitPrixAchat ? ', marge ${gnfCompact(caTotal - a.prixAchat * qteTotale)}' : ''}',
        parJour > 0
            ? 'Rythme : ${parJour.toStringAsFixed(2)} ${a.unite}/jour sur $joursActifs jours '
                '→ ${(a.stock / parJour).round()} jours de stock restants'
            : 'Aucune vente enregistrée : impossible d\'estimer un rythme.',
        '',
        if (dernieres.isNotEmpty) 'Dernières ventes :' else 'Aucune vente.',
        for (final x in dernieres.take(8))
          '- ${_jour(x.v.date)} | ${x.v.numero} | ${fmtNombre(x.l.qte)} ${a.unite} '
              'à ${fmtNombre(x.l.prixUnitaire)} GNF | client '
              '${d.clients.where((c) => c.id == x.v.clientId).firstOrNull?.nom ?? x.v.clientId}',
        '',
        if (mvts.isNotEmpty) 'Derniers mouvements de stock :',
        for (final m in mvts.take(8))
          '- ${_jour(m.date)} | ${m.type} | ${fmtNombre(m.quantite)} '
              '(${fmtNombre(m.quantiteAvant ?? 0)} → ${fmtNombre(m.quantiteApres ?? 0)}) | '
              '${m.utilisateur} | ${m.note}',
      ];
      return out.where((x) => x.isNotEmpty).join('\n');
    }).join('\n\n───\n\n');
  },
);

final _resoudreArticle = OutilIA(
  nom: 'resoudre_article',
  description:
      'LE PASSAGE OBLIGÉ avant toute écriture qui touche un article. Prend la désignation telle '
      'que le commerçant l\'a dite (« cornière 30 », « tôle galva 1,5 », « 10 barres de tube carré '
      '40 ») et dit si cet article existe déjà, s\'il y en a plusieurs qui conviennent, ou s\'il '
      's\'agit d\'une déclinaison absente du catalogue. Rend aussi la consigne à suivre : ajouter '
      'du stock, poser une question, ou faire confirmer une création. À appeler AVANT addStock, '
      'removeStock, updateArticle et surtout createArticle.',
  parametres: {
    'terme':
        'La désignation dite par le commerçant, recopiée telle quelle. Obligatoire.',
  },
  executer: (args, d) {
    final terme =
        (args['terme'] ?? args['article'] ?? args['nom'] ?? '').toString().trim();
    if (terme.isEmpty) {
      return 'Aucune désignation fournie. Rappelle le paramètre « terme » avec '
          'les mots employés par le commerçant.';
    }
    return expliquerResolution(
      resoudreArticle(d.articles, terme),
      voitPrixAchat: d.voitPrixAchat,
    );
  },
);

final _ficheClient = OutilIA(
  nom: 'fiche_client',
  description:
      'Le compte complet d\'un client : coordonnées, chiffre d\'affaires, ce qu\'il achète, ses '
      'factures, son solde impayé, son ancienneté de retard et son historique de paiement. '
      'À utiliser avant toute relance ou tout crédit.',
  parametres: {'terme': 'Nom, téléphone ou identifiant du client. Obligatoire.'},
  executer: (args, d) {
    final terme = (args['terme'] ?? args['client'] ?? '').toString().trim();
    final trouves = d.clients
        .where((c) => _correspond([c.id, c.nom, c.telephone], terme))
        .toList();
    if (trouves.isEmpty) return 'Aucun client ne correspond à « $terme ».';
    if (trouves.length > 5) {
      return '« $terme » correspond à ${trouves.length} clients : '
          '${trouves.take(12).map((c) => c.nom).join(', ')}… Précise.';
    }

    final parIdArticle = _parId(d.articles);
    return trouves.map((c) {
      final ventes = d.ventes.where((v) => v.clientId == c.id).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final ca = ventes.fold<int>(0, (s, v) => s + v.totalNet);
      final cout =
          ventes.fold<int>(0, (s, v) => s + coutAchatVente(v, parIdArticle));
      final fs = d.factures.where((f) => f.clientId == c.id).toList()
        ..sort((a, b) => b.dateEmission.compareTo(a.dateEmission));
      final impayees = fs.where((f) => resteDu(f) > 0).toList();

      // Ce qu'il achète : sans cette ligne, « relancer le client » reste abstrait.
      final parArt = <String, int>{};
      for (final v in ventes) {
        for (final l in v.lignes) {
          parArt.update(l.articleNom, (m) => m + l.total,
              ifAbsent: () => l.total);
        }
      }
      final top = parArt.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final out = <String>[
        'CLIENT ${c.nom} — id ${c.id} (${c.type})',
        'Tél : ${c.telephone.isEmpty ? '—' : c.telephone} | '
            'Email : ${c.email.isEmpty ? '—' : c.email} | ${c.quartier} ${c.ville}'
                .trim(),
        'Client depuis : ${c.creeLe.isEmpty ? '—' : _fmtDate(c.creeLe)}',
        'Chiffre d\'affaires total : ${gnfCompact(ca)} sur ${ventes.length} ventes'
            '${d.voitPrixAchat ? ' | marge dégagée ${gnfCompact(ca - cout)} (${_pct(ca - cout, ca)})' : ''}',
        'Panier moyen : ${ventes.isEmpty ? '—' : gnfCompact((ca / ventes.length).round())}',
        'SOLDE IMPAYÉ : ${gnfCompact(soldeClient(d.factures, c.id))} '
            'sur ${impayees.length} facture·s',
        '',
        if (top.isNotEmpty) 'Ce qu\'il achète le plus :',
        for (final e in top.take(5)) '- ${e.key} : ${gnfCompact(e.value)}',
        '',
        if (impayees.isNotEmpty)
          'Factures non soldées :'
        else
          'Aucune facture impayée.',
        for (final f in impayees)
          '- ${f.numero} | émise ${_fmtDate(f.dateEmission)} | '
              'échéance ${_fmtDate(f.dateEcheance)} | TTC ${gnfCompact(f.montantTTC)} | '
              'payé ${gnfCompact(montantPaye(f))} | RESTE ${gnfCompact(resteDu(f))}'
              '${enRetard(f) ? ' | EN RETARD DE ${_joursDepuis(f.dateEcheance)} JOURS' : ''}',
        '',
        if (ventes.isNotEmpty) 'Dernières ventes :',
        for (final v in ventes.take(8))
          '- ${_jour(v.date)} | ${v.numero} | ${gnfCompact(v.totalNet)} | '
              '${v.lignes.map((l) => '${fmtNombre(l.qte)}× ${l.articleNom}').join(', ')}',
      ];
      return out.where((x) => x.isNotEmpty).join('\n');
    }).join('\n\n───\n\n');
  },
);

final _chercherVentes = OutilIA(
  nom: 'chercher_ventes',
  description:
      'Retrouve des ventes précises et en donne le total. Filtres cumulables : période, client, '
      'article, montant minimum. À utiliser dès qu\'une question porte sur autre chose que les '
      'toutes dernières ventes.',
  parametres: {
    'periode':
        '« mois », « mois_dernier », « annee », « 30j », « 90j » ou « tout ». Par défaut : tout.',
    'client': 'Optionnel : nom ou identifiant du client.',
    'article': 'Optionnel : nom ou référence d\'un article présent dans la vente.',
    'montant_min':
        'Optionnel : ne garder que les ventes au-dessus de ce montant en GNF.',
    'limite':
        'Nombre de ventes détaillées, 15 par défaut, 60 au maximum. Le total porte sur TOUTES les ventes filtrées.',
  },
  executer: (args, d) {
    final r = resoudrePeriode(args);
    final limite = _nb(args['limite'], 15).clamp(1, 60).toInt();
    final minimum = _nb(args['montant_min'], 0);
    var ventes =
        _ventesDe(d.ventes, r.periode).where((v) => v.totalNet >= minimum).toList();

    if (args['client'] != null) {
      final ids = d.clients
          .where((c) =>
              _correspond([c.id, c.nom, c.telephone], '${args['client']}'))
          .map((c) => c.id)
          .toSet();
      ventes = ventes.where((v) => ids.contains(v.clientId)).toList();
    }
    if (args['article'] != null) {
      final ids = d.articles
          .where((a) => _correspond([a.id, a.ref, a.nom], '${args['article']}'))
          .map((a) => a.id)
          .toSet();
      ventes = ventes
          .where((v) => v.lignes.any((l) => ids.contains(l.articleId)))
          .toList();
    }

    final parIdArticle = _parId(d.articles);
    final total = ventes.fold<int>(0, (s, v) => s + v.totalNet);
    final cout =
        ventes.fold<int>(0, (s, v) => s + coutAchatVente(v, parIdArticle));

    final out = <String>[
      'VENTES — ${r.libelle}'
          '${args['client'] != null ? ', client « ${args['client']} »' : ''}'
          '${args['article'] != null ? ', contenant « ${args['article']} »' : ''}',
      '${ventes.length} vente·s, total ${gnfCompact(total)}'
          '${d.voitPrixAchat ? ', coût d\'achat ${gnfCompact(cout)}, marge ${gnfCompact(total - cout)} (${_pct(total - cout, total)})' : ''}',
      if (ventes.isNotEmpty)
        'Panier moyen : ${gnfCompact((total / ventes.length).round())}',
      '',
      for (final v in ventes.take(limite))
        '- ${_jour(v.date)} | ${v.numero} | '
            '${d.clients.where((c) => c.id == v.clientId).firstOrNull?.nom ?? v.clientId} | '
            '${gnfCompact(v.totalNet)} | '
            '${v.lignes.map((l) => '${fmtNombre(l.qte)}× ${l.articleNom} à ${fmtNombre(l.prixUnitaire)}').join(', ')}',
      if (ventes.length > limite)
        '… ${ventes.length - limite} autres ventes non détaillées (mais comptées dans le total ci-dessus).',
    ];
    return out.where((x) => x.isNotEmpty).join('\n');
  },
);

final _chercherDepenses = OutilIA(
  nom: 'chercher_depenses',
  description:
      'Retrouve les dépenses : achats de marchandise, charges d\'exploitation, investissements. '
      'Indique pour chacune ce qui a été réglé et ce qui reste dû. Indispensable pour toute '
      'question sur les coûts, la caisse ou ce qu\'on doit aux fournisseurs.',
  parametres: {
    'periode':
        '« mois », « mois_dernier », « annee », « 30j », « 90j » ou « tout ». Par défaut : tout.',
    'categorie':
        'Optionnel : « Loyer », « Carburant », « Salaires »… recherche partielle acceptée.',
    'nature':
        'Optionnel : « marchandise », « exploitation » ou « investissement ».',
    'statut':
        'Optionnel : « non réglée », « partielle », « réglée », ou « impayées » pour tout ce qui reste dû.',
    'limite': 'Nombre de lignes détaillées, 20 par défaut, 60 au maximum.',
  },
  confidentiel: true,
  executer: (args, d) {
    final r = resoudrePeriode(args);
    final limite = _nb(args['limite'], 20).clamp(1, 60).toInt();
    var dep = d.depenses.where((x) => dansPeriode(x.date, r.periode)).toList();

    if (args['categorie'] != null) {
      dep = dep
          .where((x) => _correspond([x.categorie], '${args['categorie']}'))
          .toList();
    }
    if (args['nature'] != null) {
      final n = '${args['nature']}'.toLowerCase();
      dep = dep.where((x) => natureDe(x.categorie) == n).toList();
    }
    final st = (args['statut'] ?? '').toString().toLowerCase();
    if (st == 'impayées' || st == 'impayees' || st == 'dues') {
      dep = dep.where((x) => resteAPayer(x) > 0).toList();
    } else if (st.isNotEmpty) {
      dep = dep.where((x) => x.statut == st).toList();
    }

    dep.sort((a, b) => b.date.compareTo(a.date));
    final engage = dep.fold<int>(0, (s, x) => s + x.montant);
    final regle = dep.fold<int>(0, (s, x) => s + montantRegle(x));

    return <String>[
      'DÉPENSES — ${r.libelle}'
          '${args['categorie'] != null ? ', catégorie « ${args['categorie']} »' : ''}'
          '${args['nature'] != null ? ', nature ${args['nature']}' : ''}'
          '${st.isNotEmpty ? ', statut $st' : ''}',
      '${dep.length} pièce·s | engagé ${gnfCompact(engage)} | réglé ${gnfCompact(regle)} | '
          'RESTE À PAYER ${gnfCompact(engage - regle)}',
      '',
      for (final x in dep.take(limite))
        '- ${_jour(x.date)} | ${x.numero.isEmpty ? '—' : x.numero} | ${x.categorie} '
            '[${libelleNature[natureDe(x.categorie)]}] | ${x.libelle} | '
            'bénéficiaire ${x.beneficiaire.isEmpty ? '—' : x.beneficiaire} | '
            '${gnfCompact(x.montant)} | ${x.statut}'
            '${resteAPayer(x) > 0 ? ' — reste ${gnfCompact(resteAPayer(x))}' : ''}',
      if (dep.length > limite)
        '… ${dep.length - limite} autres dépenses non détaillées (comptées dans les totaux).',
      '',
      'Rappel comptable : « marchandise » et « investissement » sortent de la caisse '
          'mais ne sont PAS des charges de la période.',
    ].join('\n');
  },
);

final _creancesEtDettes = OutilIA(
  nom: 'creances_et_dettes',
  description:
      'L\'état de ce qui reste dehors, classé par ancienneté : factures clients non soldées '
      '(avec les jours de retard) et dépenses fournisseurs non réglées. À utiliser pour toute '
      'question de trésorerie, de relance ou de priorité de paiement.',
  confidentiel: true,
  executer: (args, d) {
    final impayees = d.factures
        .where((f) => resteDu(f) > 0)
        .map((f) => (
              f: f,
              reste: resteDu(f),
              retard: _joursDepuis(f.dateEcheance),
            ))
        .toList()
      ..sort((a, b) => b.retard != a.retard
          ? b.retard - a.retard
          : b.reste - a.reste);

    final dues = d.depenses
        .where((x) => resteAPayer(x) > 0)
        .map((x) => (x: x, reste: resteAPayer(x)))
        .toList()
      ..sort((a, b) => a.x.date.compareTo(b.x.date));

    final totalC = impayees.fold<int>(0, (s, x) => s + x.reste);
    final totalD = dues.fold<int>(0, (s, x) => s + x.reste);

    // Balance âgée : un impayé de 90 jours n'a pas la même valeur qu'un impayé
    // d'une semaine, et c'est la seule information qui dit lequel relancer.
    String tranche(int j) => j <= 0
        ? 'pas encore échu'
        : j <= 30
            ? '1 à 30 j'
            : j <= 60
                ? '31 à 60 j'
                : j <= 90
                    ? '61 à 90 j'
                    : 'plus de 90 j';
    final parTranche = <String, ({int n, int m})>{};
    for (final i in impayees) {
      final t = tranche(i.retard);
      final e = parTranche[t] ?? (n: 0, m: 0);
      parTranche[t] = (n: e.n + 1, m: e.m + i.reste);
    }

    return <String>[
      'CRÉANCES ET DETTES au ${_fmtDate(DateTime.now().toIso8601String())}',
      '',
      'Les clients nous doivent : ${gnfCompact(totalC)} sur ${impayees.length} facture·s',
      for (final e in parTranche.entries)
        '  · ${e.key} : ${e.value.n} facture·s, ${gnfCompact(e.value.m)}',
      '',
      for (final i in impayees.take(25))
        () {
          final c = d.clients.where((x) => x.id == i.f.clientId).firstOrNull;
          return '- ${c?.nom ?? i.f.clientId} | ${i.f.numero} | '
              'échéance ${_fmtDate(i.f.dateEcheance)} | reste ${gnfCompact(i.reste)}'
              '${i.retard > 0 ? ' | RETARD ${i.retard} j' : ' | pas encore échue'} | '
              'tél ${c?.telephone.isNotEmpty == true ? c!.telephone : '—'}';
        }(),
      if (impayees.length > 25) '… ${impayees.length - 25} autres.',
      '',
      'Nous devons aux fournisseurs : ${gnfCompact(totalD)} sur ${dues.length} dépense·s',
      for (final x in dues.take(25))
        '- ${x.x.beneficiaire.isEmpty ? x.x.libelle : x.x.beneficiaire} | '
            '${x.x.numero.isEmpty ? '—' : x.x.numero} | engagée ${_fmtDate(x.x.date)} | '
            '${x.x.categorie} | reste ${gnfCompact(x.reste)}',
      if (dues.length > 25) '… ${dues.length - 25} autres.',
      '',
      'Position nette (créances − dettes) : ${gnfCompact(totalC - totalD)}',
    ].where((x) => x.isNotEmpty).join('\n');
  },
);

final _reapprovisionnement = OutilIA(
  nom: 'reapprovisionnement',
  description:
      'Ce qu\'il faut racheter, et combien : articles en rupture ou sous le seuil, quantité '
      'conseillée pour couvrir un nombre de jours donné au rythme de vente constaté, coût d\'achat '
      'estimé et manque à gagner sur les ruptures.',
  parametres: {
    'jours': 'Nombre de jours de vente à couvrir. 30 par défaut.',
    'limite': 'Nombre d\'articles, 20 par défaut.',
  },
  confidentiel: true,
  executer: (args, d) {
    final cible = math.max(1, _nb(args['jours'], 30).toInt());
    final limite = _nb(args['limite'], 20).clamp(1, 60).toInt();
    // Le rythme se mesure sur 90 jours : assez long pour lisser une semaine
    // creuse, assez court pour ne pas traîner une saison révolue.
    final ventes = _ventesDe(d.ventes, Periode.derniersJours(90));

    final qte = <String, int>{};
    for (final v in ventes) {
      for (final l in v.lignes) {
        qte.update(l.articleId, (q) => q + l.qte, ifAbsent: () => l.qte);
      }
    }

    final candidats = d.articles
        .map((a) {
          final parJour = (qte[a.id] ?? 0) / 90;
          // Deux raisons de racheter, et il faut les deux : le rythme de vente
          // quand il y en a un, et le seuil d'alerte quand l'article ne s'est
          // pas vendu récemment. Ne garder que le rythme conseillerait
          // « commander 0 » sur un article en rupture depuis trois mois —
          // précisément celui dont l'absence explique qu'il ne se vende plus.
          final surRythme = (parJour * cible - a.stock).ceil();
          final statut = stockStatut(a);
          final surSeuil = statut != 'en-stock' ? a.stockMin - a.stock : 0;
          return (
            a: a,
            parJour: parJour,
            besoin: math.max(0, math.max(surRythme, surSeuil)),
            couverture: parJour > 0 ? a.stock / parJour : double.infinity,
            statut: statut,
            motif: surRythme >= surSeuil && parJour > 0
                ? 'rythme'
                : 'seuil d\'alerte',
          );
        })
        .where((x) => x.besoin > 0)
        .toList()
      ..sort((a, b) {
        final c = a.couverture.compareTo(b.couverture);
        if (c != 0) return c;
        return (b.besoin * b.a.prixAchat) - (a.besoin * a.a.prixAchat);
      });

    final out = <String>[
      'RÉAPPROVISIONNEMENT — couvrir $cible jours, rythme mesuré sur les 90 derniers jours',
      '${candidats.length} article·s concernés | coût d\'achat estimé des '
          '${math.min(limite, candidats.length)} premiers : '
          '${gnfCompact(candidats.take(limite).fold<int>(0, (s, x) => s + x.besoin * x.a.prixAchat))}',
      '',
      for (final x in candidats.take(limite))
        '- ${x.a.nom} [${x.a.ref}] : stock ${fmtNombre(x.a.stock)} ${x.a.unite} (${x.statut}), '
            'rythme ${x.parJour.toStringAsFixed(2)}/j, couverture '
            '${x.couverture.isFinite ? '${x.couverture.round()} j' : 'sans vente récente'} → '
            'COMMANDER ${fmtNombre(x.besoin)} ${x.a.unite} (d\'après le ${x.motif}) '
            '≈ ${gnfCompact(x.besoin * x.a.prixAchat)}'
            '${x.a.prixVente - x.a.prixAchat > 0 ? ', marge attendue ${gnfCompact(x.besoin * (x.a.prixVente - x.a.prixAchat))}' : ''} | '
            'fournisseur ${x.a.fournisseur.isEmpty ? '—' : x.a.fournisseur}',
      () {
        final rupturesVendeuses = candidats
            .where((x) => x.statut == 'rupture' && x.parJour > 0)
            .toList();
        if (rupturesVendeuses.isEmpty) return '';
        final perte = rupturesVendeuses.fold<double>(
            0, (s, x) => s + x.parJour * (x.a.prixVente - x.a.prixAchat));
        return '\nManque à gagner des ruptures actuelles : environ '
            '${gnfCompact(perte.round())} de marge par jour, sur '
            '${rupturesVendeuses.length} article·s qui se vendaient.';
      }(),
    ].where((x) => x.isNotEmpty).join('\n');
    return out;
  },
);

final _evolution = OutilIA(
  nom: 'evolution',
  description:
      'La série chronologique du chiffre d\'affaires, de la marge et des dépenses, mois par mois '
      'ou jour par jour. À utiliser pour comparer deux périodes, repérer une tendance, une '
      'saisonnalité ou un décrochage.',
  parametres: {
    'granularite': '« mois » (défaut) ou « jour ».',
    'n': 'Nombre de périodes à remonter. 6 par défaut, 24 au maximum.',
  },
  confidentiel: true,
  executer: (args, d) {
    final parJour =
        (args['granularite'] ?? 'mois').toString().toLowerCase().startsWith('j');
    final n = _nb(args['n'], parJour ? 14 : 6)
        .clamp(2, parJour ? 60 : 24)
        .toInt();
    final maintenant = DateTime.now();
    final out = <String>[
      'ÉVOLUTION — $n ${parJour ? 'derniers jours' : 'derniers mois'}',
      ''
    ];

    int? precedent;
    for (var i = n - 1; i >= 0; i--) {
      final Periode p;
      final String etiquette;
      if (parJour) {
        final dt = maintenant.subtract(Duration(days: i));
        final iso = isoJour(dt);
        p = Periode(debut: iso, fin: iso);
        etiquette = _fmtDate(iso, court: true);
      } else {
        final dt = DateTime(maintenant.year, maintenant.month - i, 1);
        p = Periode.mois(dt.year, dt.month);
        etiquette = DateFormat('MMM yy', 'fr_FR').format(dt);
      }
      final b = _bilan(d, p);
      final variation = (precedent != null && precedent > 0)
          ? ' (${b.chiffreAffaires >= precedent ? '+' : ''}'
              '${((b.chiffreAffaires - precedent) / precedent * 100).toStringAsFixed(0)} %)'
          : '';
      out.add('- $etiquette : CA ${gnfCompact(b.chiffreAffaires)}$variation | '
          'marge brute ${gnfCompact(b.margeBrute)} | charges ${gnfCompact(b.chargesExploitation)} | '
          'résultat ${gnfCompact(b.resultatExploitation)} | ${b.nbVentes} ventes');
      precedent = b.chiffreAffaires;
    }
    return out.join('\n');
  },
);

final _listerArticles = OutilIA(
  nom: 'lister_articles',
  description:
      'Le catalogue, filtrable. À utiliser pour retrouver une référence, lister une catégorie, '
      'ou sortir tout ce qui est en rupture ou sous le seuil d\'alerte.',
  parametres: {
    'filtre':
        'Optionnel : « rupture », « faible », « alerte » (rupture + faible), ou du texte libre '
            'cherché dans le nom, la référence, la catégorie et le fournisseur.',
    'limite': 'Nombre de lignes, 30 par défaut, 200 au maximum.',
  },
  confidentiel: true,
  executer: (args, d) {
    final limite = _nb(args['limite'], 30).clamp(1, 200).toInt();
    final f = (args['filtre'] ?? '').toString().toLowerCase().trim();
    var arts = d.articles;
    if (f == 'rupture') {
      arts = arts.where((a) => stockStatut(a) == 'rupture').toList();
    } else if (f == 'faible') {
      arts = arts.where((a) => stockStatut(a) == 'faible').toList();
    } else if (f == 'alerte') {
      arts = arts.where((a) => stockStatut(a) != 'en-stock').toList();
    } else if (f.isNotEmpty) {
      arts = arts
          .where((a) => _correspond(
              [a.id, a.ref, a.nom, a.categorie, a.fournisseur, a.provenance], f))
          .toList();
    }

    return <String>[
      'CATALOGUE${f.isNotEmpty ? ' — filtre « $f »' : ''} : ${arts.length} article·s',
      if (d.voitPrixAchat)
        'Valeur du stock : '
            '${gnfCompact(arts.fold<int>(0, (s, a) => s + a.prixAchat * a.stock))} au prix d\'achat, '
            '${gnfCompact(arts.fold<int>(0, (s, a) => s + a.prixVente * a.stock))} au prix de vente',
      '',
      for (final a in arts.take(limite))
        '- [${a.id}] ${a.ref} | ${a.nom} | ${a.categorie} | '
            'stock ${fmtNombre(a.stock)} ${a.unite} (seuil ${fmtNombre(a.stockMin)}, ${stockStatut(a)})'
            '${d.voitPrixAchat ? ' | achat ${fmtNombre(a.prixAchat)}' : ''} | '
            'vente ${fmtNombre(a.prixVente)} GNF | ${a.fournisseur.isEmpty ? '—' : a.fournisseur}',
      if (arts.length > limite)
        '… ${arts.length - limite} autres. Affine le filtre ou augmente la limite.',
    ].where((x) => x.isNotEmpty).join('\n');
  },
);

final _listerClients = OutilIA(
  nom: 'lister_clients',
  description:
      'La liste des clients avec leur chiffre d\'affaires et leur solde impayé, triable. '
      'À utiliser pour les classements et les relances groupées.',
  parametres: {
    'tri':
        '« ca » (défaut), « impaye », « recent » (derniers créés), ou « inactif » (n\'ont plus acheté depuis longtemps).',
    'limite': 'Nombre de lignes, 20 par défaut, 100 au maximum.',
  },
  executer: (args, d) {
    final limite = _nb(args['limite'], 20).clamp(1, 100).toInt();
    final tri = (args['tri'] ?? 'ca').toString().toLowerCase();

    final lignes = d.clients.map((c) {
      final ventes = d.ventes.where((v) => v.clientId == c.id).toList();
      final ca = ventes.fold<int>(0, (s, v) => s + v.totalNet);
      final dates = ventes.map((v) => v.date).toList()..sort();
      return (
        c: c,
        ca: ca,
        n: ventes.length,
        solde: soldeClient(d.factures, c.id),
        derniere: dates.isEmpty ? null : dates.last,
        jours: dates.isEmpty ? null : _joursDepuis(dates.last),
      );
    }).toList();

    lignes.sort((a, b) {
      switch (tri) {
        case 'impaye':
        case 'impayé':
          return b.solde - a.solde;
        case 'recent':
          return (b.c.creeLe).compareTo(a.c.creeLe);
        case 'inactif':
          return (b.jours ?? 99999) - (a.jours ?? 99999);
        default:
          return b.ca - a.ca;
      }
    });

    return <String>[
      'CLIENTS — ${d.clients.length} au total, triés par $tri',
      'Total impayé toutes clientèles : '
          '${gnfCompact(lignes.fold<int>(0, (s, x) => s + x.solde))}',
      '',
      for (final x in lignes.take(limite))
        '- ${x.c.nom} [${x.c.id}] (${x.c.type}) | '
            'tél ${x.c.telephone.isEmpty ? '—' : x.c.telephone} | '
            'CA ${gnfCompact(x.ca)} sur ${x.n} ventes | impayé ${gnfCompact(x.solde)} | '
            'dernier achat ${x.derniere != null ? '${_fmtDate(x.derniere)} (il y a ${x.jours} j)' : 'jamais'}',
      if (lignes.length > limite) '… ${lignes.length - limite} autres clients.',
    ].where((x) => x.isNotEmpty).join('\n');
  },
);

final _journalActivite = OutilIA(
  nom: 'journal_activite',
  description:
      'Le journal de tout ce qui a été fait dans l\'application : ventes encaissées, paiements, '
      'mouvements de stock, articles créés ou modifiés, clients ajoutés — par qui, et quand. '
      'À utiliser pour « qu\'est-ce qu\'on a fait aujourd\'hui ? », « qui a modifié ce prix ? », '
      'ou « qu\'a fait tel vendeur hier ? ».',
  parametres: {
    'periode':
        '« jour » (aujourd\'hui, par défaut), « hier », « 7j », « mois », « mois_dernier » ou « tout ».',
    'utilisateur':
        'Optionnel : nom du membre de l\'équipe dont on veut l\'activité.',
    'type':
        'Optionnel : vente, facture, mouvement, article, prix, client, depense, utilisateur, parametres.',
    'limite': 'Nombre de lignes détaillées, 30 par défaut, 100 au maximum.',
  },
  executer: (args, d) {
    final p = (args['periode'] ?? 'jour').toString().toLowerCase().trim();
    Periode? periode;
    String libelle;
    if (p.isEmpty || p == 'jour' || p == 'aujourdhui' || p == 'aujourd\'hui') {
      final a = isoJour(DateTime.now());
      periode = Periode(debut: a, fin: a);
      libelle = 'aujourd\'hui';
    } else if (p == 'hier') {
      final h = isoJour(DateTime.now().subtract(const Duration(days: 1)));
      periode = Periode(debut: h, fin: h);
      libelle = 'hier';
    } else {
      final r = resoudrePeriode(args);
      periode = r.periode;
      libelle = r.libelle;
    }

    var acts =
        d.activites.where((a) => dansPeriode(a.date, periode)).toList();
    if (args['utilisateur'] != null) {
      acts = acts
          .where((a) => _correspond([a.auteur], '${args['utilisateur']}'))
          .toList();
    }
    if (args['type'] != null) {
      final t = '${args['type']}'.toLowerCase().trim();
      acts = acts.where((a) => a.type == t).toList();
    }
    acts.sort((a, b) => b.date.compareTo(a.date));

    if (acts.isEmpty) {
      return 'JOURNAL D\'ACTIVITÉ — $libelle : aucune action enregistrée.';
    }

    final limite = _nb(args['limite'], 30).clamp(1, 100).toInt();
    final parQui = <String, int>{};
    final parType = <String, int>{};
    for (final a in acts) {
      final qui = a.auteur.isEmpty ? '?' : a.auteur;
      parQui.update(qui, (v) => v + 1, ifAbsent: () => 1);
      parType.update(a.type, (v) => v + 1, ifAbsent: () => 1);
    }
    String resume(Map<String, int> m) => (m.entries.toList()
          ..sort((x, y) => y.value.compareTo(x.value)))
        .map((e) => '${e.key} (${e.value})')
        .join(', ');

    return <String>[
      'JOURNAL D\'ACTIVITÉ — $libelle'
          '${args['utilisateur'] != null ? ', par « ${args['utilisateur']} »' : ''}',
      '${acts.length} action·s | par personne : ${resume(parQui)} | '
          'par nature : ${resume(parType)}',
      '',
      for (final a in acts.take(limite))
        '- ${_jour(a.date)} ${a.date.length >= 16 ? a.date.substring(11, 16) : ''} | '
            '${a.auteur.isEmpty ? '?' : a.auteur} | [${a.type}] ${a.description}'
            '${a.horsLigne ? ' (saisie hors ligne)' : ''}',
      if (acts.length > limite)
        '… ${acts.length - limite} autres actions non détaillées (mais comptées ci-dessus).',
    ].where((x) => x.isNotEmpty).join('\n');
  },
);

final List<OutilIA> kOutils = [
  _resoudreArticle,
  _bilanFinancier,
  _creancesEtDettes,
  _rentabiliteArticles,
  _reapprovisionnement,
  _evolution,
  _ficheArticle,
  _ficheClient,
  _chercherVentes,
  _chercherDepenses,
  _listerArticles,
  _listerClients,
  _journalActivite,
];

/// La notice remise au modèle.
///
/// Les outils confidentiels disparaissent purement de la liste quand
/// l'utilisateur n'a pas le droit de voir les prix d'achat : ne pas les
/// documenter est la seule façon fiable de ne pas les voir appelés.
String documenterOutils(bool voitPrixAchat) {
  final dispo =
      kOutils.where((o) => voitPrixAchat || !o.confidentiel).toList();
  final blocs = dispo.map((o) {
    final params = o.parametres.entries;
    return [
      '▸ ${o.nom}',
      '  ${o.description}',
      params.isNotEmpty
          ? params.map((e) => '  · ${e.key} : ${e.value}').join('\n')
          : '  · aucun paramètre',
    ].join('\n');
  });

  // L'exemple d'appel doit citer un outil que l'utilisateur a le droit
  // d'appeler. Le gabarit web y met « bilan_financier » en toutes lettres,
  // y compris dans la notice d'un vendeur : cela lui apprend le nom d'un outil
  // confidentiel, que l'exécution refusera ensuite. On prend un exemple
  // conforme à ses droits.
  final exemple = voitPrixAchat
      ? '<outil nom="bilan_financier">{"periode":"mois"}</outil>'
      : '<outil nom="lister_clients">{"tri":"impaye"}</outil>';

  return '''═══════════ OUTILS À TA DISPOSITION ═══════════
Tu n'as PAS toutes les données du magasin sous les yeux : le contexte ci-dessus n'en est qu'un résumé. Pour tout le reste — une vente d'il y a trois mois, une dépense, le bénéfice réel, le compte d'un client, la rentabilité d'un article — tu dois interroger le magasin avec les outils suivants.

Pour appeler un outil, écris UNIQUEMENT ceci, sans autre texte autour :
$exemple

Tu peux en appeler plusieurs d'un coup (un bloc chacun). Le résultat te revient immédiatement et tu peux alors en appeler d'autres, jusqu'à $kMaxToursOutils fois, avant de rédiger ta réponse. Le commerçant ne voit pas ces appels : il ne lit que ta réponse finale.

Règles :
- Ne réponds JAMAIS « je n'ai pas cette information » sans avoir essayé l'outil correspondant.
- Dès qu'un article est nommé — pour une entrée de stock, une sortie, une modification, une création, une vente —, commence par resoudre_article. Le catalogue n'écrit pas les articles comme le commerçant les dit : « cornière 30 » y figure sous « Cornière L 30×30×3 mm (6 m) ». Conclure sans cet outil, c'est créer un doublon ou mouvementer le stock du voisin.
${voitPrixAchat ? '''- Une question sur le bénéfice, le résultat, la rentabilité réelle ou « est-ce que je gagne de l'argent » exige bilan_financier : la marge brute du résumé ignore le loyer, les salaires et le carburant.
- Croise avant de conclure. Un conseil de réapprovisionnement sans regarder la trésorerie disponible est un mauvais conseil.''' : '''- Cet utilisateur n'a pas accès aux prix d'achat, aux marges ni aux résultats financiers. Ne les évoque pas et n'essaie pas de les reconstituer : renvoie-le vers le responsable.'''}
- N'invente jamais un chiffre qu'un outil pourrait donner. Appelle-le.

${blocs.join('\n\n')}''';
}

// ─── La boucle ────────────────────────────────────────────────────────────────

/// Nombre d'allers-retours d'outils autorisés pour une même question. Les outils
/// sont locaux et gratuits ; la seule limite est le temps d'attente et le nombre
/// d'appels au modèle, qui, lui, se facture.
const int kMaxToursOutils = 4;

class AppelOutil {
  final String nom;
  final Map<String, dynamic> args;
  const AppelOutil(this.nom, this.args);
}

final _motifOutil =
    RegExp(r'''<outil\s+nom=["']?([a-z_]+)["']?\s*>([\s\S]*?)</outil>''',
        caseSensitive: false);

/// Repère les appels d'outils dans une réponse.
///
/// Tolérant à dessein : les modèles enrobent volontiers le bloc de ``` ou
/// oublient les guillemets autour du nom.
({List<AppelOutil> appels, String reste}) extraireAppels(String texte) {
  final appels = <AppelOutil>[];
  for (final m in _motifOutil.allMatches(texte)) {
    var brut = (m.group(2) ?? '').trim();
    brut = brut
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'```$'), '')
        .trim();
    var args = <String, dynamic>{};
    if (brut.isNotEmpty) {
      try {
        final p = jsonDecode(brut);
        if (p is Map<String, dynamic>) args = p;
      } catch (_) {
        // Arguments illisibles : l'outil tournera avec ses valeurs par défaut.
      }
    }
    appels.add(AppelOutil(m.group(1)!.toLowerCase(), args));
  }
  return (
    appels: appels,
    reste: texte.replaceAll(_motifOutil, '').trim(),
  );
}

/// Exécute un appel.
///
/// Une erreur est racontée au modèle plutôt que remontée : il corrige ses
/// arguments au tour suivant, au lieu de laisser le commerçant devant un
/// message technique.
String executerOutil(AppelOutil appel, DonneesMagasin d) {
  final outil = kOutils.where((o) => o.nom == appel.nom).firstOrNull;
  if (outil == null) {
    final dispo = kOutils
        .where((o) => d.voitPrixAchat || !o.confidentiel)
        .map((o) => o.nom)
        .join(', ');
    return 'Outil « ${appel.nom} » inconnu. Outils disponibles : $dispo.';
  }
  if (outil.confidentiel && !d.voitPrixAchat) {
    return 'Accès refusé : cet utilisateur n\'a pas le droit de consulter les prix '
        'd\'achat ni les marges. Réponds sans ces éléments.';
  }
  try {
    final r = outil.executer(appel.args, d).trim();
    return r.isEmpty ? 'Aucun résultat.' : r;
  } catch (e) {
    return 'L\'outil ${appel.nom} a échoué : $e. '
        'Vérifie tes arguments ou passe par un autre outil.';
  }
}

class ReponseAssistant {
  final String texte;

  /// Les outils employés, affichés sous la réponse : le commerçant doit pouvoir
  /// vérifier d'où sort un chiffre qui l'engage à commander ou à relancer.
  final List<String> trace;
  const ReponseAssistant(this.texte, this.trace);
}

/// Pose la question au modèle et lui laisse interroger le magasin autant de fois
/// qu'il en a besoin avant de répondre.
Future<ReponseAssistant> repondreAvecOutils(
  ClientIA client,
  ConfigIA cfg,
  String systeme,
  List<TourIA> tours,
  DonneesMagasin donnees, {
  void Function(String etape)? surEtape,
  dynamic annulation,
}) async {
  final fil = [...tours];
  final trace = <String>[];

  for (var tour = 0; tour <= kMaxToursOutils; tour++) {
    final brut =
        await client.demander(cfg, systeme, fil, annulation: annulation);
    final extrait = extraireAppels(brut);

    if (extrait.appels.isEmpty) return ReponseAssistant(brut, trace);

    // Dernier tour : le modèle réclame encore des données mais n'en aura plus.
    // On lui rend la main avec ce qu'il a déjà plutôt que de rendre un message
    // vide, et on le lui dit explicitement.
    if (tour == kMaxToursOutils) {
      fil.add(TourIA('assistant',
          extrait.reste.isEmpty ? '(consultation en cours)' : extrait.reste));
      fil.add(const TourIA(
          'user',
          'Limite d\'outils atteinte. Réponds maintenant avec les données déjà '
              'obtenues, sans nouvel appel d\'outil.'));
      final finale =
          await client.demander(cfg, systeme, fil, annulation: annulation);
      final net = extraireAppels(finale).reste.trim();
      if (net.isNotEmpty) return ReponseAssistant(net, trace);
      // Le modèle a redemandé un outil au lieu de conclure. Plutôt qu'une bulle
      // vide, on rend ce qu'il avait déjà écrit ; à défaut, on le dit.
      if (extrait.reste.trim().isNotEmpty) {
        return ReponseAssistant(extrait.reste.trim(), trace);
      }
      throw ErreurIA(
          'L\'assistant a consulté ${trace.length} outils sans parvenir à '
          'conclure. Reformulez votre question de façon plus précise.',
          CodeErreurIA.api);
    }

    final resultats = <String>[];
    for (final a in extrait.appels) {
      final etiquette = a.nom +
          (a.args.isNotEmpty
              ? ' (${a.args.entries.map((e) => '${e.key}=${e.value}').join(', ')})'
              : '');
      trace.add(etiquette);
      surEtape?.call(etiquette);
      resultats.add(
          '<resultat nom="${a.nom}">\n${executerOutil(a, donnees)}\n</resultat>');
    }

    fil.add(TourIA('assistant', brut));
    fil.add(TourIA('user', resultats.join('\n\n')));
  }

  // Inatteignable : la boucle rend toujours au dernier tour. On lève plutôt
  // que de rendre un texte vide, qui ne dirait rien à personne.
  throw ErreurIA('L\'assistant n\'a pas pu conclure. Réessayez.',
      CodeErreurIA.api);
}
