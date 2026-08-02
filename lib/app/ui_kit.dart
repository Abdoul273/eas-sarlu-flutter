// lib/app/ui_kit.dart
//
// Composants partagés de l'interface.
//
// Règle transverse : aucun composant de ce fichier ne doit pouvoir déborder de
// la place qu'on lui donne. Concrètement, tout texte susceptible d'être long
// porte `maxLines` + `overflow`, les valeurs numériques se réduisent au lieu
// de passer à la ligne, et aucune hauteur n'est déduite d'un calcul manuel.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'format.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Conteneurs
// ---------------------------------------------------------------------------

/// Carte générique de l'application.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? margin;

  /// Teinte d'accent appliquée au fond et au contour (état, sévérité…).
  final Color? accent;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Espace.lg),
    this.onTap,
    this.onLongPress,
    this.margin,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sombre = scheme.brightness == Brightness.dark;
    final borderRadius = Rayon.carte;

    return Container(
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: Espace.page,
            vertical: Espace.xs + 2,
          ),
      decoration: BoxDecoration(
        color: accent?.withValues(alpha: sombre ? 0.12 : 0.06) ??
            scheme.surfaceContainerLowest,
        borderRadius: borderRadius,
        border: Border.all(
          color: accent?.withValues(alpha: 0.35) ??
              scheme.outlineVariant.withValues(alpha: sombre ? 0.7 : 1.0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: sombre
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0x0A000000),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          child: Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

/// Titre de section, avec action facultative alignée à droite.
class SectionHeader extends StatelessWidget {
  final String titre;
  final IconData? icone;
  final Color? couleurIcone;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.titre,
    this.icone,
    this.couleurIcone,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleur = couleurIcone ?? theme.colorScheme.primary;

    return Row(
      children: [
        if (icone != null) ...[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Rayon.sm),
            ),
            child: Icon(icone, size: 18, color: couleur),
          ),
          const SizedBox(width: Espace.md),
        ],
        // Expanded : sans ça, un titre long pousse l'action hors de l'écran.
        Expanded(
          child: Text(
            titre,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: Espace.md, vertical: 4),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: couleur.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rayon.pilule),
              ),
            ),
            child: Text(
              actionLabel!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: couleur,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Boutons
// ---------------------------------------------------------------------------

/// Bouton standard de l'application.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isPrimary;
  final bool isDestructive;
  final bool isTonal;

  /// Occupe toute la largeur disponible.
  final bool expanded;

  /// Remplace le contenu par un indicateur de chargement.
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.isDestructive = false,
    this.isTonal = false,
    this.expanded = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actif = loading ? null : onPressed;

    final childWidget = _buildChild(context);

    if (isDestructive) {
      return FilledButton(
        onPressed: actif,
        style: FilledButton.styleFrom(
          minimumSize: Size(expanded ? double.infinity : 64, 50),
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rayon.md),
          ),
        ),
        child: childWidget,
      );
    }
    if (isTonal) {
      return FilledButton.tonal(
        onPressed: actif,
        style: FilledButton.styleFrom(
          minimumSize: Size(expanded ? double.infinity : 64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rayon.md),
          ),
        ),
        child: childWidget,
      );
    }

    // Modern gradient primary button
    return Container(
      decoration: (actif != null && isPrimary)
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(Rayon.md),
              gradient: LinearGradient(
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, Colors.orangeAccent, 0.25) ??
                      scheme.primary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            )
          : null,
      child: FilledButton(
        onPressed: actif,
        style: FilledButton.styleFrom(
          minimumSize: Size(expanded ? double.infinity : 64, 50),
          backgroundColor: (actif != null && isPrimary)
              ? Colors.transparent
              : null,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rayon.md),
          ),
        ),
        child: childWidget,
      ),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19),
          const SizedBox(width: Espace.sm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Indicateurs
// ---------------------------------------------------------------------------

/// Pastille de statut.
class BadgePastille extends StatelessWidget {
  final String texte;
  final Color couleur;
  final EdgeInsetsGeometry? padding;
  final IconData? icone;

  const BadgePastille({
    super.key,
    required this.texte,
    required this.couleur,
    this.padding =
        const EdgeInsets.symmetric(horizontal: Espace.md, vertical: 4),
    this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rayon.pilule),
        border: Border.all(color: couleur.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: couleur),
            const SizedBox(width: Espace.xs),
          ],
          Flexible(
            child: Text(
              texte,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: couleur,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                height: 1.15,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Largeur de référence d'une tuile statistique dans une liste horizontale.
const double kLargeurStatTile = 176;

/// Hauteur de la bande de tuiles statistiques.
const double kHauteurStatTile = 138;

/// Tuile statistique (valeur mise en avant + libellé).
class StatTile extends StatelessWidget {
  final String libelle;
  final String valeur;

  /// Ligne secondaire sous la valeur (ex. nombre d'opérations).
  final String? sousTitre;
  final IconData? icone;
  final double? variation; // positive = hausse, négative = baisse
  final Color? couleurValeur;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.libelle,
    required this.valeur,
    this.sousTitre,
    this.icone,
    this.variation,
    this.couleurValeur,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metier = context.metier;
    final couleur = couleurValeur ?? theme.colorScheme.primary;
    final couleurVariation =
        (variation ?? 0) >= 0 ? metier.succes : metier.danger;

    return AppCard(
      onTap: onTap,
      accent: couleur,
      margin: const EdgeInsets.symmetric(horizontal: Espace.xs + 2),
      padding: const EdgeInsets.all(Espace.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icone != null)
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        couleur.withValues(alpha: 0.25),
                        couleur.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(Rayon.md),
                    border: Border.all(color: couleur.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icone, color: couleur, size: 17),
                ),
              if (icone != null && variation != null) const Spacer(),
              if (variation != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: couleurVariation.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Rayon.pilule),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        variation! >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 12,
                        color: couleurVariation,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${variation!.abs().toStringAsFixed(1)} %',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: couleurVariation,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: Espace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valeur,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: couleur,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (sousTitre != null)
            Text(
              sousTitre!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            libelle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saisie
// ---------------------------------------------------------------------------

/// Barre de recherche.
class AppSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;

  const AppSearchBar({
    super.key,
    this.controller,
    this.hintText = 'Rechercher…',
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Espace.page,
        Espace.sm,
        Espace.page,
        Espace.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(Icons.search_rounded,
              size: 21, color: scheme.onSurfaceVariant),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: controller == null
              ? null
              : ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller!,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close_rounded, size: 19),
                      tooltip: 'Effacer',
                      onPressed: () {
                        controller!.clear();
                        onChanged?.call('');
                      },
                    );
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: Espace.md + 1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Rayon.pilule),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Rayon.pilule),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Rayon.pilule),
            borderSide: BorderSide(color: scheme.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Champ de saisie de montant en GNF avec séparateurs de milliers.
/// Champ de saisie de montant en GNF avec séparateurs de milliers.
class ChampMontant extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final ValueChanged<int>? onChangedMontant;
  final int? valeurInitiale; // en GNF
  final bool enabled;
  final bool autofocus;

  const ChampMontant({
    super.key,
    required this.controller,
    this.labelText = 'Montant *',
    this.hintText,
    this.onChangedMontant,
    this.valeurInitiale,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<ChampMontant> createState() => _ChampMontantState();
}

class _ChampMontantState extends State<ChampMontant> {
  bool _isFormatting = false;

  @override
  void initState() {
    super.initState();
    if (widget.valeurInitiale != null && widget.valeurInitiale! > 0) {
      widget.controller.text = fmtNombre(widget.valeurInitiale!);
    }
    widget.controller.addListener(_formatText);
  }

  void _formatText() {
    if (_isFormatting) return;

    final rawText = widget.controller.text;
    final cleanText = rawText.replaceAll(RegExp(r'[^\d]'), '');

    if (cleanText.isEmpty) {
      if (rawText.isNotEmpty) {
        _isFormatting = true;
        widget.controller.value = const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
        _isFormatting = false;
      }
      widget.onChangedMontant?.call(0);
      return;
    }

    final parsed = int.tryParse(cleanText);
    if (parsed != null) {
      final formatted = fmtNombre(parsed);
      if (rawText != formatted) {
        final oldSelection = widget.controller.selection;
        final digitsBefore = _compterChiffresAvant(rawText, oldSelection.end);
        final newOffset = _trouverOffsetPourChiffres(formatted, digitsBefore);

        _isFormatting = true;
        widget.controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: newOffset),
        );
        _isFormatting = false;
      }
      widget.onChangedMontant?.call(parsed);
    }
  }

  int _compterChiffresAvant(String s, int offset) {
    int count = 0;
    final maxIndex = offset.clamp(0, s.length);
    for (int i = 0; i < maxIndex; i++) {
      if (RegExp(r'\d').hasMatch(s[i])) count++;
    }
    return count;
  }

  int _trouverOffsetPourChiffres(String s, int nbChiffres) {
    if (nbChiffres <= 0) return 0;
    int count = 0;
    for (int i = 0; i < s.length; i++) {
      if (RegExp(r'\d').hasMatch(s[i])) {
        count++;
        if (count == nbChiffres) return i + 1;
      }
    }
    return s.length;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_formatText);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
      ],
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText ?? '0',
        suffixIcon: UnconstrainedBox(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'GNF',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// États
// ---------------------------------------------------------------------------

/// État vide.
class EtatVide extends StatelessWidget {
  final IconData icone;
  final String message;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Version resserrée, pour un état vide affiché à l'intérieur d'une carte.
  final bool compact;

  const EtatVide({
    super.key,
    this.icone = Icons.inbox_outlined,
    required this.message,
    this.description,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taille = compact ? 40.0 : 56.0;

    final contenu = Padding(
        padding: EdgeInsets.all(compact ? Espace.lg : Espace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: taille + 24,
              height: taille + 24,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icone,
                size: taille * 0.55,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? Espace.md : Espace.lg),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: Espace.xs),
              Text(
                description!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? Espace.md : Espace.xl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                isTonal: true,
              ),
            ],
          ],
        ),
      );

    // Centré quand la place le permet, défilant sinon.
    //
    // Le composant est utilisé aussi bien dans un `Expanded` pleine page que
    // dans une carte basse : sans ce double régime, le second cas déborde
    // (illustration + texte + bouton > hauteur disponible).
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return Center(child: contenu);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: contenu),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Feuilles modales
// ---------------------------------------------------------------------------

/// Affiche une feuille modale arrondie et défilable.
Future<T?> feuilleModale<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          const PoigneeFeuille(),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espace.lg,
                0,
                Espace.lg,
                Espace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              // Le clavier recouvre le bas de la feuille : sans cette réserve,
              // le dernier champ se retrouve masqué pendant la saisie.
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: builder(context),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Poignée de préhension d'une feuille modale.
class PoigneeFeuille extends StatelessWidget {
  const PoigneeFeuille({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espace.md),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(Rayon.pilule),
        ),
      ),
    );
  }
}
