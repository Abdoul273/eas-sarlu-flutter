import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart' show Conflit;
import '../db/stores.dart';
import '../models/models.dart';
import 'op_queue.dart';
import 'sync_engine.dart';

// ─── Arbitrage d'un conflit de synchronisation ────────────────────────────────
//
// Deux personnes ont modifié le même enregistrement. L'opération locale a été
// retirée de la file — sans quoi elle referait échouer chaque synchronisation —
// et déposée dans le registre des conflits. Rien n'est jeté avant que
// l'utilisateur ait vu les deux versions et tranché.
//
// Cet écran affichait jusqu'ici le contenu BRUT des deux enregistrements, champ
// par champ, valeur telle quelle. Sur une fiche entreprise, cela déversait le
// logo et la signature encodés en base64 : des milliers de caractères illisibles
// sous le titre « Conflit de synchronisation ». Impossible de comparer quoi que
// ce soit, donc impossible d'arbitrer.
//
// Deux principes maintenant :
//   — on ne montre QUE ce qui diffère. Un arbitrage porte sur le désaccord, pas
//     sur les quarante champs identiques de part et d'autre ;
//   — aucune valeur n'est affichée brute. Une image se dit « image (12 ko) »,
//     un texte long est coupé. Ce qu'on montre doit tenir sur un téléphone.

/// Intitulés lisibles des champs. Un champ absent de cette table s'affiche sous
/// son nom technique : mieux vaut un nom brut qu'un champ escamoté.
const _libelles = <String, String>{
  'nom': 'Nom',
  'slogan': 'Slogan',
  'adresse': 'Adresse',
  'quartier': 'Quartier',
  'ville': 'Ville',
  'telephone': 'Téléphone',
  'email': 'E-mail',
  'siteWeb': 'Site web',
  'rccm': 'RCCM',
  'nif': 'NIF',
  'logo': 'Logo',
  'devise': 'Devise',
  'conditionsPaiement': 'Conditions de paiement',
  'mentionsLegales': 'Mentions légales',
  'signataire': 'Signataire',
  'signatureImage': 'Signature',
  'rib': 'Compte bancaire',
  'banque': 'Banque',
  'swift': 'SWIFT',
  'couleurAccent': 'Couleur',
  'tauxTVA': 'Taux de TVA',
  'ref': 'Référence',
  'prixVente': 'Prix de vente',
  'prixAchat': "Prix d'achat",
  'stock': 'Stock',
  'unite': 'Unité',
  'categorie': 'Catégorie',
  'seuilAlerte': "Seuil d'alerte",
  'note': 'Note',
  'montantTTC': 'Montant',
  'date': 'Date',
};

/// Champs qui portent une image encodée : jamais affichés tels quels.
const _champsImage = {'logo', 'signatureImage'};

/// Champs purement techniques : ils ne se comparent pas à l'œil.
const _champsTechniques = {
  '_rev',
  '_updatedAt',
  '_updatedBy',
  'baseRev',
  'id',
};

class ConflictSheet extends ConsumerWidget {
  final Conflit conflit;

  const ConflictSheet({super.key, required this.conflit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = _enregistrement(_lire(conflit.tentativeJson));
    final serveur = _lire(conflit.serveurJson);
    final differences = _differences(locale, serveur);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Conflit de synchronisation',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${conflit.libelle} a été modifié ailleurs pendant que vous '
              'travailliez. Choisissez la version à garder.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            if (differences.isEmpty)
              Text(
                'Les deux versions ont le même contenu — seul le numéro de '
                'révision diffère. « Prendre celle du serveur » règle la '
                'situation sans rien perdre.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Text('CE QUI DIFFÈRE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  )),
              const SizedBox(height: 8),
              for (final champ in differences)
                _LigneDifference(
                  libelle: _libelles[champ] ?? champ,
                  valeurLocale: _apercu(champ, locale[champ]),
                  valeurServeur: _apercu(champ, serveur[champ]),
                ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resoudre(context, ref, garderLocal: true),
                    child: const Text('Garder ma version'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _resoudre(context, ref, garderLocal: false),
                    child: const Text('Prendre celle du serveur'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _lire(String json) {
    try {
      final decode = jsonDecode(json);
      return decode is Map<String, dynamic> ? decode : {};
    } catch (_) {
      return {};
    }
  }

  /// La charge utile enveloppe l'enregistrement selon le type d'opération.
  /// On montre le contenu métier, pas l'enveloppe technique.
  static Map<String, dynamic> _enregistrement(Map<String, dynamic> payload) {
    for (final cle in [
      'record',
      'entreprise',
      'vente',
      'mouvement',
      'paiement',
      'reglement'
    ]) {
      final valeur = payload[cle];
      if (valeur is Map<String, dynamic>) return valeur;
    }
    return payload;
  }

  /// Les champs sur lesquels les deux versions ne s'accordent pas.
  static List<String> _differences(
      Map<String, dynamic> locale, Map<String, dynamic> serveur) {
    final cles = {...locale.keys, ...serveur.keys}
      ..removeWhere(_champsTechniques.contains);
    final liste = cles
        .where((c) => jsonEncode(locale[c]) != jsonEncode(serveur[c]))
        .toList()
      ..sort();
    return liste;
  }

  /// Ce qu'on affiche d'une valeur — jamais la valeur elle-même quand elle est
  /// illisible.
  static String _apercu(String champ, dynamic valeur) {
    if (valeur == null) return '(absent)';

    if (_champsImage.contains(champ)) {
      final texte = valeur.toString().trim();
      if (texte.isEmpty) return 'aucune';
      // Le base64 gonfle d'un tiers le poids réel du fichier.
      final ko = (texte.length * 3 / 4 / 1024).round();
      return ko <= 0 ? 'image' : 'image ($ko ko)';
    }

    if (valeur is List) {
      return valeur.isEmpty ? '(vide)' : '${valeur.length} élément(s)';
    }
    if (valeur is Map) return '${valeur.length} champ(s)';

    final texte = valeur.toString().trim();
    if (texte.isEmpty) return '(vide)';
    if (texte.length <= 90) return texte;
    return '${texte.substring(0, 90)}…';
  }

  Future<void> _resoudre(BuildContext context, WidgetRef ref,
      {required bool garderLocal}) async {
    final navigateur = Navigator.of(context);
    final opQueue = ref.read(opQueueProvider);
    final registre = ref.read(registreConflitsProvider);
    final stores = ref.read(storesProvider);
    final moteur = ref.read(syncEngineProvider);

    if (garderLocal) {
      await opQueue.enqueue(
          conflit.type,
          payloadRebase(conflit.tentativeJson, conflit.serveurJson),
          libelle: conflit.libelle);
    } else {
      // « Prendre celle du serveur » n'écrivait RIEN et s'en remettait à la
      // prochaine récupération. Or un conflit ne fait pas avancer la version du
      // serveur : le téléphone se croyait à jour, ne rapatriait rien, gardait sa
      // fiche et sa révision périmées — et rouvrait le même conflit à la
      // sauvegarde suivante. Sans fin.
      //
      // On écrit donc la version du serveur ici, tout de suite. Elle est déjà
      // sous la main : c'est le corps de sa réponse.
      await _appliquerVersionServeur(stores);
    }

    await registre.retirer(conflit.id);
    // Et on réclame un instantané complet, que la version ait bougé ou non :
    // c'est ce qui remet les deux côtés d'accord pour de bon.
    moteur.demanderRecuperationComplete();
    navigateur.pop();
  }

  Future<void> _appliquerVersionServeur(Stores stores) =>
      appliquerVersionServeur(stores, conflit.type, conflit.serveurJson);

  /// L'opération à remettre en file quand l'utilisateur garde SA version.
  ///
  /// Elle est rebasée sur la révision du serveur : renvoyer celle qu'il vient
  /// de refuser reproduirait le même conflit à l'identique, indéfiniment.
  ///
  /// Et quand le serveur n'a pas dit où il en était, on n'en envoie AUCUNE —
  /// sans révision il n'arbitre pas et accepte l'écriture, ce qui est
  /// exactement ce que l'utilisateur demande en cliquant « Garder ma version ».
  /// C'est la porte de sortie qui garantit qu'un conflit finit toujours par se
  /// clore.
  @visibleForTesting
  static Map<String, dynamic> payloadRebase(
      String tentativeJson, String serveurJson) {
    final payload = Map<String, dynamic>.from(_lire(tentativeJson));
    final revServeur = _lire(serveurJson)['_rev'];
    for (final cle in ['record', 'entreprise']) {
      final record = payload[cle];
      if (record is! Map) continue;
      if (revServeur != null) {
        record['_rev'] = revServeur;
      } else {
        record.remove('_rev');
      }
    }
    if (revServeur != null) {
      payload['baseRev'] = revServeur;
    } else {
      payload.remove('baseRev');
    }
    return payload;
  }

  /// Écrit localement l'enregistrement que le serveur a renvoyé avec son refus.
  ///
  /// Les types absents de ce tri ne perdent rien : l'instantané réclamé juste
  /// après les rapportera. C'est la fiche entreprise qui avait absolument besoin
  /// d'être écrite tout de suite — c'est elle qui porte la révision sur laquelle
  /// le désaccord se rejouait.
  @visibleForTesting
  static Future<void> appliquerVersionServeur(
      Stores stores, String type, String serveurJson) async {
    final serveur = _lire(serveurJson);
    if (serveur.isEmpty) return;
    try {
      switch (type) {
        case 'entreprise':
          await stores.upsert('entreprise', Entreprise.fromJson(serveur));
        case 'client':
          await stores.upsert('client', Client.fromJson(serveur));
        case 'article':
          await stores.upsert('article', Article.fromJson(serveur));
        case 'fournisseur':
          await stores.upsert('fournisseur', Fournisseur.fromJson(serveur));
        case 'depense':
          await stores.upsert('depense', Depense.fromJson(serveur));
      }
    } catch (_) {
      // Un enregistrement illisible ne doit pas bloquer l'arbitrage : la
      // récupération complète qui suit rétablira la vérité du serveur.
    }
  }
}

/// Un champ en désaccord : l'intitulé, puis les deux valeurs l'une sous l'autre.
///
/// Deux lignes plutôt que deux colonnes : sur un téléphone, deux colonnes de
/// texte coupent chaque valeur en accordéon.
class _LigneDifference extends StatelessWidget {
  final String libelle;
  final String valeurLocale;
  final String valeurServeur;

  const _LigneDifference({
    required this.libelle,
    required this.valeurLocale,
    required this.valeurServeur,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget cote(String qui, String valeur, Color couleur) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 62,
                child: Text(qui,
                    style: theme.textTheme.bodySmall?.copyWith(color: couleur)),
              ),
              Expanded(
                child: Text(valeur, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(libelle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          cote('Vous', valeurLocale, scheme.primary),
          cote('Serveur', valeurServeur, scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
