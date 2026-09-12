import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import 'ai_actions.dart';

// ─── La fiche de confirmation ─────────────────────────────────────────────────
//
// Ce que l'assistant propose ne s'exécute jamais tout seul. Cette feuille est
// le passage obligé : elle dit en toutes lettres ce qui va changer, réclame ce
// que le modèle a laissé vide, et attend un appui.
//
// Elle affiche des phrases, pas des paramètres. Un récapitulatif écrit
// « addStock · articleId=A001 · quantite=10 » ne se lit pas, donc ne se vérifie
// pas, donc ne protège de rien : on confirme par lassitude. « Le stock passera
// de 24 à 34 barres » se vérifie d'un coup d'œil.

/// Le résultat de la feuille : les actions complétées par l'humain, ou `null`
/// s'il a annulé.
typedef ResultatFiche = List<AppelAction>?;

Future<ResultatFiche> ouvrirFicheActions(
  BuildContext context, {
  required List<AppelAction> actions,
  required ContexteResume contexte,
  required List<ChampAction> Function(AppelAction) manquantsDe,
}) {
  return showModalBottomSheet<List<AppelAction>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (_) => _FicheActions(
      actions: actions,
      contexte: contexte,
      manquantsDe: manquantsDe,
    ),
  );
}

class _FicheActions extends ConsumerStatefulWidget {
  final List<AppelAction> actions;
  final ContexteResume contexte;
  final List<ChampAction> Function(AppelAction) manquantsDe;

  const _FicheActions({
    required this.actions,
    required this.contexte,
    required this.manquantsDe,
  });

  @override
  ConsumerState<_FicheActions> createState() => _FicheActionsState();
}

class _FicheActionsState extends ConsumerState<_FicheActions> {
  /// Les valeurs saisies, indexées « rang.champ ».
  final Map<String, TextEditingController> _controleurs = {};
  final Map<String, String> _choix = {};

  late final List<List<ChampAction>> _manquants;

  @override
  void initState() {
    super.initState();
    _manquants = widget.actions.map(widget.manquantsDe).toList();
    for (var i = 0; i < _manquants.length; i++) {
      for (final c in _manquants[i]) {
        if (c.choix == null) {
          _controleurs['$i.${c.nom}'] = TextEditingController()
            ..addListener(() => setState(() {}));
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controleurs.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _valeur(int i, ChampAction c) =>
      (c.choix != null ? _choix['$i.${c.nom}'] : _controleurs['$i.${c.nom}']?.text)
          ?.trim() ??
      '';

  /// Tant qu'un champ obligatoire manque, on ne confirme pas. Le modèle ne doit
  /// pas combler ces trous : un prix qu'il aurait inventé passerait inaperçu au
  /// milieu d'un récapitulatif que l'on croit vérifié.
  bool get _complet {
    for (var i = 0; i < _manquants.length; i++) {
      for (final c in _manquants[i]) {
        if (_valeur(i, c).isEmpty) return false;
      }
    }
    return true;
  }

  void _confirmer() {
    HapticFeedback.mediumImpact();
    final completees = <AppelAction>[];
    for (var i = 0; i < widget.actions.length; i++) {
      final a = widget.actions[i];
      final params = Map<String, dynamic>.from(a.params);
      for (final c in _manquants[i]) {
        final v = _valeur(i, c);
        if (v.isNotEmpty) params[c.nom] = v;
      }
      // C'est le seul endroit qui transforme une proposition IA en ordre
      // exécutable. Une transcription vocale, même si elle contient « oui »,
      // n'est jamais une confirmation : il faut cet appui explicite.
      completees.add(AppelAction(
        a.type,
        params,
        a.libelle,
        confirmationHumaine: true,
      ));
    }
    Navigator.pop(context, completees);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final multiple = widget.actions.length > 1;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + Espace.lg,
        left: Espace.page,
        right: Espace.page,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_rounded, color: scheme.primary),
                const SizedBox(width: Espace.sm),
                Expanded(
                  child: Text(
                    multiple
                        ? 'À confirmer — ${widget.actions.length} actions'
                        : 'À confirmer',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espace.xs),
            Text(
              'Rien n\'est enregistré tant que vous n\'avez pas confirmé.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Espace.md),

            for (var i = 0; i < widget.actions.length; i++)
              _BlocAction(
                rang: multiple ? i + 1 : null,
                appel: widget.actions[i],
                contexte: widget.contexte,
                manquants: _manquants[i],
                controleurs: _controleurs,
                choix: _choix,
                index: i,
                surChoix: (cle, v) => setState(() => _choix[cle] = v),
              ),

            const SizedBox(height: Espace.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: Espace.sm),
                Expanded(
                  child: AppButton(
                    label: multiple ? 'Tout confirmer' : 'Confirmer',
                    icon: Icons.check_rounded,
                    expanded: true,
                    onPressed: _complet ? _confirmer : null,
                  ),
                ),
              ],
            ),
            if (!_complet) ...[
              const SizedBox(height: Espace.xs),
              Text(
                'Renseignez les champs demandés pour pouvoir confirmer.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BlocAction extends StatelessWidget {
  final int? rang;
  final AppelAction appel;
  final ContexteResume contexte;
  final List<ChampAction> manquants;
  final Map<String, TextEditingController> controleurs;
  final Map<String, String> choix;
  final int index;
  final void Function(String cle, String valeur) surChoix;

  const _BlocAction({
    required this.rang,
    required this.appel,
    required this.contexte,
    required this.manquants,
    required this.controleurs,
    required this.choix,
    required this.index,
    required this.surChoix,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = trouverAction(appel.type);

    // Un résumé qui échoue ne doit pas emporter la confirmation avec lui :
    // mieux vaut une fiche sans détail qu'un écran blanc.
    List<String> lignes;
    try {
      lignes = action?.resume(appel.params, contexte) ?? const [];
    } catch (_) {
      lignes = const [];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: Espace.sm),
      padding: const EdgeInsets.all(Espace.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Rayon.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${rang == null ? '' : '$rang. '}'
            '${action?.titre ?? appel.libelle}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: Espace.xs),
          for (final l in lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                l,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: l.contains('ATTENTION')
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                  fontWeight:
                      l.contains('ATTENTION') ? FontWeight.bold : null,
                ),
              ),
            ),

          if (manquants.isNotEmpty) ...[
            const SizedBox(height: Espace.sm),
            const Divider(height: 1),
            const SizedBox(height: Espace.sm),
            Text(
              'À PRÉCISER',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: Espace.xs),
            for (final c in manquants)
              Padding(
                padding: const EdgeInsets.only(bottom: Espace.sm),
                child: c.choix != null
                    ? DropdownButtonFormField<String>(
                        initialValue: choix['$index.${c.nom}'],
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: c.libelle,
                          helperText: c.aide,
                          helperMaxLines: 2,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final o in c.choix!)
                            DropdownMenuItem(value: o, child: Text(o)),
                        ],
                        onChanged: (v) =>
                            v == null ? null : surChoix('$index.${c.nom}', v),
                      )
                    : TextField(
                        controller: controleurs['$index.${c.nom}'],
                        keyboardType: c.type == TypeChamp.nombre
                            ? const TextInputType.numberWithOptions(
                                decimal: true)
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: c.libelle,
                          suffixText: c.suffixe,
                          helperText: c.aide,
                          helperMaxLines: 2,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
              ),
          ],
        ],
      ),
    );
  }
}
