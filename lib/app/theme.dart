// lib/app/theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Provider pour SharedPreferences (sera overridé dans main.dart)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Doit être overridé avec une instance');
});

// ---------------------------------------------------------------------------
// Jetons de design
//
// Toutes les mesures de l'interface passent par ces constantes : c'est ce qui
// donne le rythme visuel régulier d'un écran à l'autre. Ne pas écrire de
// valeurs « en dur » dans les pages.
// ---------------------------------------------------------------------------

/// Échelle d'espacement (base 4).
abstract final class Espace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Marge latérale de référence pour le contenu d'une page.
  static const double page = 16;

  /// Réserve basse des listes : la barre de navigation et le bouton flottant
  /// recouvrent le bas de l'écran, sans ça le dernier élément est inatteignable.
  static const double basDeListe = 96;
}

/// Rayons d'arrondi.
abstract final class Rayon {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pilule = 999;

  static BorderRadius get carte => BorderRadius.circular(lg);
  static BorderRadius get champ => BorderRadius.circular(md);
  static BorderRadius get feuille =>
      const BorderRadius.vertical(top: Radius.circular(xl));
}

/// Durées d'animation communes.
abstract final class Duree {
  static const Duration rapide = Duration(milliseconds: 150);
  static const Duration moyenne = Duration(milliseconds: 260);
  static const Duration lente = Duration(milliseconds: 380);
}

/// Couleurs sémantiques stables entre les deux thèmes.
@immutable
class CouleursMetier extends ThemeExtension<CouleursMetier> {
  final Color succes;
  final Color succesFond;
  final Color alerte;
  final Color alerteFond;
  final Color danger;
  final Color dangerFond;
  final Color info;
  final Color infoFond;

  const CouleursMetier({
    required this.succes,
    required this.succesFond,
    required this.alerte,
    required this.alerteFond,
    required this.danger,
    required this.dangerFond,
    required this.info,
    required this.infoFond,
  });

  static const clair = CouleursMetier(
    succes: Color(0xFF10B981),
    succesFond: Color(0xFFD1FAE5),
    alerte: Color(0xFFF59E0B),
    alerteFond: Color(0xFFFEF3C7),
    danger: Color(0xFFEF4444),
    dangerFond: Color(0xFFFEE2E2),
    info: Color(0xFF3B82F6),
    infoFond: Color(0xFFDBEAFE),
  );

  static const sombre = CouleursMetier(
    succes: Color(0xFF34D399),
    succesFond: Color(0xFF064E3B),
    alerte: Color(0xFFFBBF24),
    alerteFond: Color(0xFF78350F),
    danger: Color(0xFFF87171),
    dangerFond: Color(0xFF7F1D1D),
    info: Color(0xFF60A5FA),
    infoFond: Color(0xFF1E3A8A),
  );

  @override
  CouleursMetier copyWith({
    Color? succes,
    Color? succesFond,
    Color? alerte,
    Color? alerteFond,
    Color? danger,
    Color? dangerFond,
    Color? info,
    Color? infoFond,
  }) {
    return CouleursMetier(
      succes: succes ?? this.succes,
      succesFond: succesFond ?? this.succesFond,
      alerte: alerte ?? this.alerte,
      alerteFond: alerteFond ?? this.alerteFond,
      danger: danger ?? this.danger,
      dangerFond: dangerFond ?? this.dangerFond,
      info: info ?? this.info,
      infoFond: infoFond ?? this.infoFond,
    );
  }

  @override
  CouleursMetier lerp(ThemeExtension<CouleursMetier>? other, double t) {
    if (other is! CouleursMetier) return this;
    return CouleursMetier(
      succes: Color.lerp(succes, other.succes, t)!,
      succesFond: Color.lerp(succesFond, other.succesFond, t)!,
      alerte: Color.lerp(alerte, other.alerte, t)!,
      alerteFond: Color.lerp(alerteFond, other.alerteFond, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerFond: Color.lerp(dangerFond, other.dangerFond, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoFond: Color.lerp(infoFond, other.infoFond, t)!,
    );
  }
}

/// Raccourci d'accès aux couleurs métier depuis un widget.
extension CouleursMetierContext on BuildContext {
  CouleursMetier get metier =>
      Theme.of(this).extension<CouleursMetier>() ?? CouleursMetier.clair;
}

// ---------------------------------------------------------------------------
// Thèmes
// ---------------------------------------------------------------------------

/// Orange vibrant ultra cool pour la marque.
const Color kCouleurMarque = Color(0xFFFF5E1A);

ThemeData buildLightTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: kCouleurMarque,
    primary: kCouleurMarque,
    brightness: Brightness.light,
  );
  final colorScheme = base.copyWith(
    surface: const Color(0xFFF8FAFC),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF1F5F9),
    surfaceContainer: const Color(0xFFE2E8F0),
    surfaceContainerHigh: const Color(0xFFCBD5E1),
    surfaceContainerHighest: const Color(0xFF94A3B8),
    outlineVariant: const Color(0xFFE2E8F0),
  );
  return _buildTheme(colorScheme, CouleursMetier.clair);
}

ThemeData buildDarkTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: kCouleurMarque,
    primary: kCouleurMarque,
    brightness: Brightness.dark,
  );
  final colorScheme = base.copyWith(
    surface: const Color(0xFF090D16),
    surfaceContainerLowest: const Color(0xFF111726),
    surfaceContainerLow: const Color(0xFF172033),
    surfaceContainer: const Color(0xFF1E293D),
    surfaceContainerHigh: const Color(0xFF27344D),
    surfaceContainerHighest: const Color(0xFF334155),
    outlineVariant: const Color(0xFF1F2A3E),
  );
  return _buildTheme(colorScheme, CouleursMetier.sombre);
}

ThemeData _buildTheme(ColorScheme colorScheme, CouleursMetier metier) {
  final sombre = colorScheme.brightness == Brightness.dark;
  final textTheme = _buildTextTheme(colorScheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    textTheme: textTheme,
    extensions: [metier],

    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleSpacing: Espace.sm,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      systemOverlayStyle:
          sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),

    // Cartes sans ombre : la hiérarchie passe par la teinte de surface et un
    // filet de contour. Les ombres M3 rendaient l'écran « sale » en liste.
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Rayon.carte,
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
      margin: const EdgeInsets.symmetric(
        horizontal: Espace.page,
        vertical: Espace.xs + 2,
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colorScheme.primary.withValues(alpha: sombre ? 0.24 : 0.14),
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      // Deux lignes de libellé feraient déborder les 68 px de la barre : la
      // taille est verrouillée ici et les libellés sont volontairement courts.
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11.5,
          height: 1.1,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        );
      }),
    ),

    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),

    drawerTheme: DrawerThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      scrimColor: Colors.black.withValues(alpha: 0.45),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(Rayon.xl)),
      ),
      width: 312,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 3,
      focusElevation: 4,
      hoverElevation: 5,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.lg)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Espace.lg,
        vertical: Espace.md + 2,
      ),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      border: OutlineInputBorder(
        borderRadius: Rayon.champ,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Rayon.champ,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Rayon.champ,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: Rayon.champ,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: Rayon.champ,
        borderSide: BorderSide(color: colorScheme.error, width: 1.6),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        padding: const EdgeInsets.symmetric(horizontal: Espace.xl),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        padding: const EdgeInsets.symmetric(horizontal: Espace.xl),
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.sm)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      selectedColor: colorScheme.primary.withValues(alpha: sombre ? 0.26 : 0.14),
      side: BorderSide(color: colorScheme.outlineVariant),
      // `labelPadding` verticale nulle + densité compacte : le chip tient dans
      // 36 px de haut, ce qui évite le débordement des barres de filtres.
      labelPadding: const EdgeInsets.symmetric(horizontal: Espace.sm),
      padding: const EdgeInsets.symmetric(horizontal: Espace.xs, vertical: 6),
      labelStyle: TextStyle(
        fontSize: 13,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      secondaryLabelStyle: TextStyle(fontSize: 13, color: colorScheme.primary),
      showCheckmark: false,
      shape: const StadiumBorder(),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
      minVerticalPadding: Espace.sm + 2,
    ),

    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 1,
      color: colorScheme.outlineVariant,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: colorScheme.surfaceContainerLow,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: colorScheme.outlineVariant,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: Rayon.feuille),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.xl)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(Espace.lg),
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
      elevation: 2,
    ),

    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: colorScheme.outlineVariant,
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.primary.withValues(alpha: 0.06),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHigh,
      circularTrackColor: Colors.transparent,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(Rayon.sm),
      ),
      textStyle: TextStyle(color: colorScheme.onInverseSurface, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: Espace.md, vertical: 6),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor:
            colorScheme.primary.withValues(alpha: sombre ? 0.26 : 0.14),
        selectedForegroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.onPrimary : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
    ),
  );
}

/// Typographie : chaque style porte une `height` explicite.
///
/// C'est la première défense contre les « bottom overflowed by N pixels » :
/// sans hauteur de ligne fixée, la mesure d'un texte varie avec la police
/// réellement résolue sur l'appareil et fait sauter les hauteurs calculées.
TextTheme _buildTextTheme(ColorScheme colorScheme) {
  final onSurface = colorScheme.onSurface;
  final onVariant = colorScheme.onSurfaceVariant;
  return TextTheme(
    displaySmall: TextStyle(
      fontSize: 30,
      height: 1.18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: onSurface,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: onSurface,
    ),
    headlineSmall: TextStyle(
      fontSize: 20,
      height: 1.22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: onSurface,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: onSurface,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    titleSmall: TextStyle(
      fontSize: 13.5,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    bodyLarge: TextStyle(fontSize: 15, height: 1.4, color: onSurface),
    bodyMedium: TextStyle(fontSize: 13.5, height: 1.4, color: onSurface),
    bodySmall: TextStyle(fontSize: 12, height: 1.35, color: onVariant),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: onSurface,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: onVariant,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: onVariant,
    ),
  );
}

// Provider pour le mode de thème (persisté)
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final modeString = prefs.getString('themeMode');
    if (modeString == 'light') return ThemeMode.light;
    if (modeString == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    switch (mode) {
      case ThemeMode.light:
        await prefs.setString('themeMode', 'light');
        break;
      case ThemeMode.dark:
        await prefs.setString('themeMode', 'dark');
        break;
      case ThemeMode.system:
        await prefs.remove('themeMode');
        break;
    }
    state = mode;
  }
}
