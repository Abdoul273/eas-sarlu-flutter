import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../assistant/ai_config.dart';
import '../assistant/live/live_config.dart';
import '../assistant/voix.dart';
import '../assistant/voix_neurale.dart';

/// Réglages de l'assistant : fournisseur, clé et voix de lecture.
///
/// L'assistant ne partait jusqu'ici jamais : l'adresse du relais valait
/// « À_REMPLIR » et aucun écran ne permettait de saisir une clé. On répare les
/// deux ici, avec les mêmes fournisseurs et les mêmes modèles que
/// l'application web.
///
/// Le verrou et l'empreinte, eux, ont quitté cette rubrique pour la leur
/// (`SecuriteSection`) : ils n'ont rien à voir avec l'assistant et se
/// cherchaient sous un titre où personne ne pensait à regarder.
class AssistantSection extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const AssistantSection({super.key, this.isEmbedded = false});

  @override
  ConsumerState<AssistantSection> createState() => _AssistantSectionState();
}

class _AssistantSectionState extends ConsumerState<AssistantSection> {
  final _cleController = TextEditingController();
  final _serpController = TextEditingController();
  bool _cleVisible = false;
  bool _serpVisible = false;
  FournisseurIA? _fournisseurAffiche;
  bool _serpInitialise = false;

  @override
  void dispose() {
    _cleController.dispose();
    _serpController.dispose();
    super.dispose();
  }

  /// Recharge le champ quand on change de fournisseur : chaque fournisseur a sa
  /// propre clé, et afficher celle de l'autre inviterait à l'écraser.
  void _synchroniserChamp(ConfigIA cfg) {
    if (_fournisseurAffiche != cfg.fournisseur) {
      _fournisseurAffiche = cfg.fournisseur;
      _cleController.text = cfg.cles[cfg.fournisseur] ?? '';
    }
    // La clé SerpAPI ne dépend pas du fournisseur : on ne la remplit qu'une
    // fois, sinon chaque frappe se ferait écraser par la valeur enregistrée.
    if (!_serpInitialise) {
      _serpInitialise = true;
      _serpController.text = cfg.cleSerpapi;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cfg = ref.watch(configIAProvider);
    final notifier = ref.read(configIAProvider.notifier);
    _synchroniserChamp(cfg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cfg.relaisActif)
          Container(
            padding: const EdgeInsets.all(Espace.md),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Rayon.md),
            ),
            child: Text(
              'Les appels passent par votre serveur, qui détient les clés. '
              'Rien à saisir ici.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else ...[
          Text('Fournisseur',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: Espace.xs),
          SegmentedButton<FournisseurIA>(
            segments: [
              for (final f in FournisseurIA.values)
                ButtonSegment(
                  value: f,
                  label: Text(kFournisseurs[f]!.nom),
                ),
            ],
            selected: {cfg.fournisseur},
            onSelectionChanged: (s) => notifier.changerFournisseur(s.first),
          ),
          const SizedBox(height: Espace.md),

          Text('Modèle',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: Espace.xs),
          DropdownButtonFormField<String>(
            initialValue: cfg.modele,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final m in cfg.info.modeles)
                DropdownMenuItem(
                  value: m.id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.libelle, overflow: TextOverflow.ellipsis),
                      if (m.note != null)
                        Text(m.note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => v == null ? null : notifier.changerModele(v),
          ),
          const SizedBox(height: Espace.md),

          Text('Clé API',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: Espace.xs),
          TextField(
            controller: _cleController,
            obscureText: !_cleVisible,
            maxLines: 1,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: cfg.info.exempleCle,
              helperText: 'Plusieurs clés séparées par une virgule : '
                  'une clé épuisée laisse sa place à la suivante.',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(_cleVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _cleVisible = !_cleVisible),
              ),
            ),
            onChanged: (v) => notifier.definirCle(cfg.fournisseur, v),
          ),
          const SizedBox(height: Espace.xs),
          Row(
            children: [
              Expanded(
                child: Text(cfg.info.aideCle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(cfg.info.urlCle),
                    mode: LaunchMode.externalApplication),
                child: const Text('Obtenir'),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.recherche,
            onChanged: notifier.activerRecherche,
            title: const Text('Autoriser la recherche web'),
            subtitle: const Text(
                'Prix du marché, taux de change, fournisseurs. Sans elle, '
                'l\'assistant ne connaît que les données du magasin.'),
          ),

          // Sans cette clé, l'assistant se voyait proposer un outil de
          // recherche qui répondait toujours « indisponible » : il reformulait
          // sa recherche jusqu'à épuiser ses tours, et rendait une bulle vide.
          // Le champ manquait tout simplement à cet écran.
          if (cfg.recherche && !cfg.relaisActif) ...[
            const SizedBox(height: Espace.md),
            Text('Clé SerpAPI',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: Espace.xs),
            TextField(
              controller: _serpController,
              obscureText: !_serpVisible,
              maxLines: 1,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '64 caractères hexadécimaux',
                helperText: cfg.rechercheDisponible
                    ? 'Recherche active : prix du marché, actualités et '
                        'fournisseurs, cadrés sur la Guinée.'
                    : 'Sans cette clé, l\'assistant répond de mémoire — donc '
                        'avec des prix périmés — et le dit.',
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  icon: Icon(_serpVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  onPressed: () => setState(() => _serpVisible = !_serpVisible),
                ),
              ),
              onChanged: notifier.definirCleSerpapi,
            ),
            const SizedBox(height: Espace.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                      'Le plan gratuit accorde 100 recherches par mois. '
                      'Les résultats sont gardés six heures : reposer la même '
                      'question ne coûte rien.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                      Uri.parse('https://serpapi.com/manage-api-key'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Obtenir'),
                ),
              ],
            ),
          ],
        ],

        const Divider(height: Espace.xl),
        const _SectionModeVocal(),
        const Divider(height: Espace.xl),
        const _SectionVoix(),
      ],
    );
  }
}

/// Réglages du mode vocal (Gemini Live) : la conversation en direct.
class _SectionModeVocal extends ConsumerWidget {
  const _SectionModeVocal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cfg = ref.watch(configLiveProvider);
    final notifier = ref.read(configLiveProvider.notifier);
    final cleGemini =
        (ref.watch(configIAProvider).cles[FournisseurIA.gemini] ?? '')
            .trim()
            .isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text('Mode vocal',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: Espace.xs),
        Text(
          'Une vraie conversation : vous parlez, l\'assistant répond de vive '
          'voix, vous pouvez le couper. Il consulte le magasin et propose des '
          'écritures que vous confirmez à l\'écran. Fonctionne avec Gemini Live, '
          'sur la clé Gemini.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (!cleGemini) ...[
          const SizedBox(height: Espace.sm),
          Container(
            padding: const EdgeInsets.all(Espace.sm + 2),
            decoration: BoxDecoration(
              color: context.metier.alerteFond,
              borderRadius: BorderRadius.circular(Rayon.sm),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: context.metier.alerte),
                const SizedBox(width: Espace.sm),
                Expanded(
                  child: Text(
                    'Aucune clé Gemini enregistrée : le mode vocal restera '
                    'indisponible, même avec Claude pour le texte.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Espace.md),
        Text('Voix de l\'assistant',
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Espace.xs),
        DropdownButtonFormField<String>(
          initialValue: cfg.voix,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final v in kVoixLive)
              DropdownMenuItem(value: v.id, child: Text(v.libelle)),
          ],
          onChanged: (v) => v == null ? null : notifier.choisirVoix(v),
        ),
        const SizedBox(height: Espace.sm),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Sous-titres'),
          subtitle: const Text('Afficher ce qui se dit, des deux côtés'),
          value: cfg.sousTitres,
          onChanged: notifier.activerSousTitres,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Vibration'),
          subtitle: const Text('Un léger retour quand l\'assistant prend la parole'),
          value: cfg.retourHaptique,
          onChanged: notifier.activerHaptique,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Garder dans l\'historique'),
          subtitle: const Text('La conversation vocale rejoint la discussion écrite'),
          value: cfg.journaliser,
          onChanged: notifier.activerJournal,
        ),
      ],
    );
  }
}

/// Réglages de la lecture à voix haute des réponses.
class _SectionVoix extends ConsumerWidget {
  const _SectionVoix();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final etat = ref.watch(voixProvider);
    final notifier = ref.read(voixProvider.notifier);
    final cfg = etat.config;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lecture à voix haute',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: Espace.xs),
        Text(
          'Deux voix au choix : celle de Gemini, qu\'on ne distingue pas d\'une '
          'personne, et celle du téléphone, qui fonctionne hors ligne.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Espace.sm),

        if (etat.indisponible)
          Container(
            padding: const EdgeInsets.all(Espace.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Rayon.md),
            ),
            child: Text(
              'Aucune voix française n\'est installée sur ce téléphone. '
              'Ajoutez le français dans Réglages → Synthèse vocale, puis '
              'rouvrez cette page.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.active,
            onChanged: notifier.activer,
            title: const Text('Proposer d\'écouter les réponses'),
            subtitle: const Text(
                'Un bouton « Écouter » apparaît sous chaque réponse.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: cfg.lectureAuto,
            // Sans lecture du tout, la lecture automatique n'a pas de sens :
            // on l'éteint plutôt que de la laisser cochée et sans effet.
            onChanged: cfg.active ? notifier.activerLectureAuto : null,
            title: const Text('Lire chaque réponse dès son arrivée'),
            subtitle: const Text(
                'Pratique les mains prises ; à couper en présence de clients.'),
          ),

          if (cfg.active) ...[
            const SizedBox(height: Espace.sm),
            SegmentedButton<MoteurVoix>(
              segments: const [
                ButtonSegment(
                  value: MoteurVoix.neurale,
                  label: Text('Naturelle'),
                  icon: Icon(Icons.auto_awesome_rounded),
                ),
                ButtonSegment(
                  value: MoteurVoix.appareil,
                  label: Text('Téléphone'),
                  icon: Icon(Icons.phone_android_rounded),
                ),
              ],
              selected: {cfg.moteur},
              onSelectionChanged: (s) => notifier.choisirMoteur(s.first),
            ),
            const SizedBox(height: Espace.xs),
            Text(
              cfg.moteur == MoteurVoix.neurale
                  ? 'Voix de Gemini, sur la clé déjà saisie plus haut. Hors '
                      'ligne ou quota atteint, le téléphone prend le relais '
                      'tout seul.'
                  : 'Synthèse installée sur l\'appareil : gratuite, instantanée '
                      'et disponible sans réseau.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),

            // Le repli est silencieux à l'usage — c'est voulu — mais il doit
            // s'expliquer ici : sans ce mot, on croit que le réglage n'a pas
            // été pris en compte.
            if (etat.repliVoix != null) ...[
              const SizedBox(height: Espace.sm),
              Container(
                padding: const EdgeInsets.all(Espace.sm),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(Rayon.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: Espace.sm),
                    Expanded(
                      child: Text(etat.repliVoix!,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: Espace.md),
            Text('Voix',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: Espace.xs),

            if (cfg.moteur == MoteurVoix.neurale)
              DropdownButtonFormField<String>(
                initialValue: cfg.voixNeurale,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final v in kVoixNeurales)
                    DropdownMenuItem(
                      value: v.id,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(v.libelle, overflow: TextOverflow.ellipsis),
                          Text(v.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) =>
                    v == null ? null : notifier.choisirVoixNeurale(v),
              )
            else
              DropdownButtonFormField<String?>(
                initialValue: cfg.voix,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('La meilleure voix française trouvée',
                        overflow: TextOverflow.ellipsis),
                  ),
                  for (final v in etat.voixDisponibles)
                    DropdownMenuItem<String?>(
                      value: v.nom,
                      child: Text(v.libelle, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: notifier.choisirVoix,
              ),

            const SizedBox(height: Espace.md),
            _Curseur(
              titre: 'Débit',
              valeur: cfg.vitesse,
              gauche: 'Posé',
              droite: 'Rapide',
              onChanged: notifier.changerVitesse,
            ),
            // Le timbre est un réglage du moteur du téléphone : la voix
            // neuronale porte le sien, et le curseur n'aurait aucun effet.
            if (cfg.moteur == MoteurVoix.appareil)
              _Curseur(
                titre: 'Timbre',
                valeur: cfg.hauteur,
                gauche: 'Grave',
                droite: 'Aigu',
                onChanged: notifier.changerHauteur,
              ),

            const SizedBox(height: Espace.sm),
            AppButton(
              // La voix neuronale met une seconde ou deux à arriver : sans ce
              // mot, on réappuie, ce qui annule la lecture qu'on attendait.
              label: etat.prepare
                  ? 'Préparation de la voix…'
                  : etat.enLecture == '_essai'
                      ? 'Arrêter'
                      : 'Écouter un exemple',
              icon: etat.enLecture == '_essai'
                  ? Icons.stop_rounded
                  : Icons.volume_up_rounded,
              isTonal: true,
              expanded: true,
              onPressed: notifier.essayer,
            ),
          ],
        ],
      ],
    );
  }
}

class _Curseur extends StatelessWidget {
  final String titre;
  final double valeur;
  final String gauche;
  final String droite;
  final ValueChanged<double> onChanged;

  const _Curseur({
    required this.titre,
    required this.valeur,
    required this.gauche,
    required this.droite,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titre, style: theme.textTheme.labelLarge),
            Text('×${valeur.toStringAsFixed(2)}', style: style),
          ],
        ),
        Slider(
          value: valeur,
          min: 0.5,
          max: 2.0,
          divisions: 30,
          label: '×${valeur.toStringAsFixed(2)}',
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Espace.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(gauche, style: style), Text(droite, style: style)],
          ),
        ),
      ],
    );
  }
}
