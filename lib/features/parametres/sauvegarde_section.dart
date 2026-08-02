// lib/features/parametres/sauvegarde_section.dart
//
// Sauvegarder tout le magasin dans un fichier, et le restaurer.
//
// Le fichier part par le partage du téléphone : Google Drive y figure comme
// destination, au même titre que Dropbox, WhatsApp ou une clé USB. Aucune
// connexion à configurer, aucun jeton qui expire — et la sauvegarde reste
// lisible par l'application web, qui écrit le même format.
//
// La restauration ne s'exécute JAMAIS en aveugle : le fichier est d'abord lu et
// résumé, puis comparé à ce qui est en place, et l'utilisateur voit les deux
// avant de trancher. Restaurer sans voir, c'est découvrir qu'on a chargé la
// sauvegarde du mois dernier une fois le mois en cours perdu.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../../core/db/stores.dart';
import '../../core/sauvegarde/sauvegarde.dart';
import '../../core/sync/sync_engine.dart';

/// Une étape du travail en cours, avec sa progression quand elle est connue.
class _Avancement {
  final String etape;

  /// De 0 à 1, ou `null` quand la durée n'est pas mesurable (le serveur
  /// n'annonce pas toujours la taille de ce qu'il envoie).
  final double? part;

  const _Avancement(this.etape, [this.part]);
}

class SauvegardeSection extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const SauvegardeSection({super.key, this.isEmbedded = false});

  @override
  ConsumerState<SauvegardeSection> createState() => _SauvegardeSectionState();
}

class _SauvegardeSectionState extends ConsumerState<SauvegardeSection> {
  _Avancement? _enCours;

  void _avancer(String etape, [double? part]) {
    if (mounted) setState(() => _enCours = _Avancement(etape, part));
  }

  void _termine() {
    if (mounted) setState(() => _enCours = null);
  }

  // ── Sauvegarder ────────────────────────────────────────────────────────────

  Future<void> _sauvegarder() async {
    _avancer('Préparation…');
    try {
      final api = ref.read(apiClientProvider);

      _avancer('Récupération des données du serveur…');
      final reponse = await api.dio.get<String>(
        kDataBackup,
        options: Options(responseType: ResponseType.plain),
        onReceiveProgress: (recu, total) {
          // Le serveur n'annonce pas toujours la taille : sans elle, on montre
          // une barre indéterminée plutôt qu'une fausse progression.
          _avancer('Récupération des données du serveur…',
              total > 0 ? recu / total : null);
        },
      );

      _avancer('Écriture du fichier…');
      final donnees =
          Map<String, dynamic>.from(jsonDecode(reponse.data ?? '{}') as Map);
      final enveloppe = construireEnveloppe(donnees);
      final resume = resumerSauvegarde(donnees);

      final dossier = await getTemporaryDirectory();
      final nom = nomFichierSauvegarde();
      final fichier = File('${dossier.path}/$nom');
      await fichier.writeAsString(
          const JsonEncoder.withIndent('  ').convert(enveloppe));

      _avancer('Ouverture du partage…');
      final taille = await fichier.length();
      await Share.shareXFiles(
        [XFile(fichier.path, mimeType: 'application/json')],
        subject: nom,
        text: 'Sauvegarde E.A.S Sarlu — ${resume.total} enregistrements',
      );

      if (!mounted) return;
      _message(
        'Sauvegarde prête (${_poids(taille)}) — ${resume.total} '
        'enregistrements. Choisissez Google Drive pour la conserver.',
        succes: true,
      );
    } on ApiException catch (e) {
      _message(e.messageApi);
    } catch (e) {
      _message('Sauvegarde impossible : $e');
    } finally {
      _termine();
    }
  }

  // ── Restaurer ──────────────────────────────────────────────────────────────

  Future<void> _restaurer() async {
    try {
      final choix = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final fichier = choix?.files.firstOrNull;
      if (fichier == null) return; // annulé : rien à dire.

      _avancer('Lecture du fichier…');
      final octets = fichier.bytes ??
          (fichier.path != null
              ? await File(fichier.path!).readAsBytes()
              : null);
      if (octets == null) {
        _message('Fichier illisible sur cet appareil.');
        return;
      }

      final lu = lireSauvegarde(utf8.decode(octets));
      _termine();

      if (!mounted) return;
      final confirme = await _confirmerRestauration(lu);
      if (confirme != true) return;

      _avancer('Envoi au serveur…');
      final api = ref.read(apiClientProvider);
      await api.dio.post(
        kDataRestore,
        data: lu.donnees,
        onSendProgress: (envoye, total) => _avancer(
            'Envoi au serveur…', total > 0 ? envoye / total : null),
      );

      // Le serveur fait foi : on reprend son instantané au lieu de recopier le
      // fichier localement. C'est ce qui garantit que le téléphone montre
      // exactement ce que le serveur a retenu.
      _avancer('Application sur cet appareil…');
      await ref.read(syncEngineProvider).forceSyncCycle();

      if (!mounted) return;
      _message(
        'Sauvegarde restaurée : ${lu.resume.total} enregistrements appliqués.',
        succes: true,
      );
    } on SauvegardeInvalide catch (e) {
      _message(e.message);
    } on ApiException catch (e) {
      _message(e.messageApi);
    } catch (e) {
      _message('Restauration impossible : $e');
    } finally {
      _termine();
    }
  }

  /// Montre ce que contient le fichier ET ce qu'il y a actuellement, avant
  /// d'écraser quoi que ce soit.
  Future<bool?> _confirmerRestauration(SauvegardeLue lu) async {
    final stores = ref.read(storesProvider);
    // Ce que l'appareil détient aujourd'hui, pour le mettre en regard du
    // fichier. Les flux rendent l'état courant à leur première valeur.
    final actuel = <String, int>{
      'articles': (await stores.getArticles()).length,
      'ventes': (await stores.watchVentes().first).length,
      'clients': (await stores.watchClients().first).length,
      'factures': (await stores.watchFactures().first).length,
      'depenses': (await stores.watchDepenses().first).length,
    };
    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lu.resume.entreprise.isNotEmpty)
                Text(lu.resume.entreprise,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              if (lu.exportDate.isNotEmpty)
                Text('Sauvegarde du ${fmtDateHeureExacteIso(lu.exportDate)}',
                    style: const TextStyle(fontSize: 12)),
              const SizedBox(height: Espace.md),
              const Text('Ce que contient le fichier, et ce que vous avez :',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: Espace.xs),
              for (final c in kCollectionsSauvegarde)
                if (lu.resume[c] > 0 || (actuel[c] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(c, style: const TextStyle(fontSize: 13)),
                        Text(
                          '${lu.resume[c]}  ←  ${actuel[c] ?? '—'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: lu.resume[c] < (actuel[c] ?? 0)
                                ? Theme.of(ctx).colorScheme.error
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
              for (final a in lu.avertissements) ...[
                const SizedBox(height: Espace.sm),
                Text('⚠ $a',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(ctx).colorScheme.error)),
              ],
              const SizedBox(height: Espace.md),
              Text(
                'Toutes les données actuelles du serveur seront remplacées, '
                'pour vous comme pour les autres appareils. Cette opération ne '
                "s'annule pas.",
                style: TextStyle(
                    fontSize: 12, color: Theme.of(ctx).colorScheme.error),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
  }

  // ── Présentation ───────────────────────────────────────────────────────────

  String _poids(int octets) => octets < 1024
      ? '$octets o'
      : octets < 1024 * 1024
          ? '${(octets / 1024).toStringAsFixed(0)} Ko'
          : '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';

  void _message(String texte, {bool succes = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: succes ? 6 : 8),
      backgroundColor: succes ? null : scheme.error,
      content: Text(texte,
          style: succes ? null : TextStyle(color: scheme.onError)),
    ));
  }

  Widget _contenu(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peut =
        ref.watch(authStateProvider).value?.user?.aLeDroit('maintenance') ??
            false;
    final occupe = _enCours != null;

    if (!peut) {
      return Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Espace.sm),
          Expanded(
            child: Text(
              'Les sauvegardes sont réservées aux comptes autorisés.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enregistre tout le magasin dans un fichier : articles, ventes, '
          'factures, clients, dépenses et réglages. Choisissez Google Drive '
          'au moment du partage pour le conserver hors du téléphone.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Espace.md),
        if (occupe) ...[
          Text(_enCours!.etape, style: theme.textTheme.bodySmall),
          const SizedBox(height: Espace.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rayon.pilule),
            child: LinearProgressIndicator(
              value: _enCours!.part,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: Espace.md),
        ],
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Sauvegarder',
                icon: Icons.cloud_upload_outlined,
                onPressed: occupe ? null : _sauvegarder,
                expanded: true,
              ),
            ),
            const SizedBox(width: Espace.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: occupe ? null : _restaurer,
                icon: const Icon(Icons.settings_backup_restore_rounded,
                    size: 18),
                label: const Text('Restaurer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) return _contenu(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Espace.page),
        child: _contenu(context),
      ),
    );
  }
}
