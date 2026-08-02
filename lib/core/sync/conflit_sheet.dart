import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart' show Conflit;
import 'op_queue.dart';
import 'sync_engine.dart';

/// Arbitrage d'un conflit de synchronisation.
///
/// Deux personnes ont modifié le même enregistrement. L'opération locale a été
/// retirée de la file — sans quoi elle referait échouer chaque synchronisation
/// — et déposée dans le registre des conflits. Rien n'est jeté avant que
/// l'utilisateur ait vu les deux versions et tranché.
class ConflictSheet extends ConsumerWidget {
  final Conflit conflit;

  const ConflictSheet({super.key, required this.conflit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final locale = _lire(conflit.tentativeJson);
    final serveur = _lire(conflit.serveurJson);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Conflit de synchronisation', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${conflit.libelle} — modifié ailleurs pendant que vous étiez hors ligne.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            Text('Votre version', style: theme.textTheme.titleMedium),
            ..._champs(_enregistrement(locale)),
            const Divider(height: 24),
            Text('Version du serveur', style: theme.textTheme.titleMedium),
            ..._champs(serveur),
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
    for (final cle in ['record', 'vente', 'mouvement', 'paiement', 'reglement']) {
      final valeur = payload[cle];
      if (valeur is Map<String, dynamic>) return valeur;
    }
    return payload;
  }

  List<Widget> _champs(Map<String, dynamic> data) {
    const techniques = {'_rev', '_updatedAt', '_updatedBy', 'baseRev', 'id'};
    final visibles =
        data.entries.where((e) => !techniques.contains(e.key)).toList();
    if (visibles.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('(aucun détail disponible)'),
        )
      ];
    }
    return [
      for (final e in visibles)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.key} : ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Flexible(child: Text('${e.value}')),
            ],
          ),
        ),
    ];
  }

  Future<void> _resoudre(BuildContext context, WidgetRef ref,
      {required bool garderLocal}) async {
    final navigateur = Navigator.of(context);
    final opQueue = ref.read(opQueueProvider);
    final registre = ref.read(registreConflitsProvider);

    if (garderLocal) {
      // On remet l'opération dans la file, mais rebasée sur la révision du
      // serveur : renvoyer l'ancienne `baseRev` reproduirait le même conflit à
      // l'identique, indéfiniment.
      final payload = Map<String, dynamic>.from(_lire(conflit.tentativeJson));
      final revServeur = _lire(conflit.serveurJson)['_rev'];
      if (revServeur != null) {
        payload['baseRev'] = revServeur;
        final record = payload['record'];
        if (record is Map) record['_rev'] = revServeur;
      }
      await opQueue.enqueue(conflit.type, payload, libelle: conflit.libelle);
    }
    // « Prendre celle du serveur » ne demande aucune écriture : la version du
    // serveur arrivera d'elle-même à la prochaine récupération.

    await registre.retirer(conflit.id);
    ref.read(syncEngineProvider).demanderSynchro();
    navigateur.pop();
  }
}
