import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/verrou_local.dart';

// ─── Écran de verrouillage ────────────────────────────────────────────────────
// La porte que l'on pousse à chaque ouverture de l'application. Elle ne parle
// jamais au serveur : le code est vérifié sur l'appareil, donc le magasin entre
// dans ses données qu'il ait du réseau ou non.
//
// Le pavé numérique est dessiné plutôt que confié au clavier système : sur un
// téléphone d'entrée de gamme, le clavier met parfois une seconde à monter, et
// la saisie du code est le geste le plus répété de la journée.

class VerrouPage extends ConsumerStatefulWidget {
  const VerrouPage({super.key});

  @override
  ConsumerState<VerrouPage> createState() => _VerrouPageState();
}

class _VerrouPageState extends ConsumerState<VerrouPage>
    with SingleTickerProviderStateMixin {
  String _saisie = '';

  /// Première saisie mémorisée pendant la définition du code : on le fait
  /// confirmer avant de l'enregistrer. Un code mal tapé la première fois
  /// enfermerait l'utilisateur dehors dès la prochaine ouverture.
  String? _premiereSaisie;
  String? _message;
  bool _erreur = false;
  bool _occupe = false;
  Timer? _minuterieAttente;

  late final AnimationController _secousse;

  @override
  void initState() {
    super.initState();
    _secousse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    WidgetsBinding.instance.addPostFrameCallback((_) => _tenterBiometrie());
  }

  @override
  void dispose() {
    _minuterieAttente?.cancel();
    _secousse.dispose();
    super.dispose();
  }

  bool get _definition =>
      ref.read(verrouProvider).etat == EtatVerrou.aDefinir;

  /// Longueur attendue. À la création, c'est toujours six : la saisie part
  /// d'elle-même au sixième chiffre, sans touche « Valider ». Au
  /// déverrouillage, c'est celle du code réellement enregistré — quatre ou cinq
  /// pour un code hérité, que l'on continue d'accepter tel quel.
  int get _longueurAttendue => _definition
      ? longueurCodeRequise
      : ref.read(verrouProvider).longueurCode;

  Future<void> _tenterBiometrie() async {
    final verrou = ref.read(verrouProvider);
    if (_definition || !verrou.biometrieActive || verrou.enAttente) return;
    final resultat =
        await ref.read(verrouProvider.notifier).deverrouillerAvecBiometrie();
    if (resultat == ResultatVerrou.ouvert && mounted) {
      setState(() => _message = null);
    }
  }

  void _chiffre(int n) {
    if (_occupe) return;
    if (_saisie.length >= _longueurAttendue) return;
    HapticFeedback.selectionClick();
    setState(() {
      _saisie += '$n';
      _erreur = false;
      _message = null;
    });
    if (_saisie.length == _longueurAttendue) _valider();
  }

  void _effacer() {
    if (_occupe || _saisie.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _saisie = _saisie.substring(0, _saisie.length - 1);
      _erreur = false;
    });
  }

  Future<void> _valider() async {
    if (_occupe || _saisie.isEmpty) return;
    setState(() => _occupe = true);
    try {
      if (_definition) {
        await _validerDefinition();
      } else {
        await _validerDeverrouillage();
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _validerDefinition() async {
    final notifier = ref.read(verrouProvider.notifier);

    if (_premiereSaisie == null) {
      if (!VerrouNotifier.estCodeValide(_saisie)) {
        _refuser('Le code doit compter $longueurCodeRequise chiffres.');
        return;
      }
      if (VerrouNotifier.estCodeFaible(_saisie)) {
        _refuser('Évitez une suite ou des chiffres identiques.');
        return;
      }
      setState(() {
        _premiereSaisie = _saisie;
        _saisie = '';
        _message = 'Saisissez à nouveau le même code pour le confirmer.';
        _erreur = false;
      });
      return;
    }

    if (_saisie != _premiereSaisie) {
      setState(() => _premiereSaisie = null);
      _refuser('Les deux codes diffèrent. Reprenons depuis le début.');
      return;
    }

    await notifier.definirCode(_saisie);
    // Le même code sert de code d'appareil côté serveur : le déverrouillage
    // en ligne depuis un autre poste reste ainsi cohérent avec celui d'ici.
    unawaited(_enregistrerCodeServeur(_saisie));
    if (mounted) setState(() => _saisie = '');
  }

  Future<void> _enregistrerCodeServeur(String code) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final deviceId = await repo.getDeviceId();
      if (deviceId == null || deviceId.isEmpty) return;
      await repo.setCode(deviceId, code);
    } catch (_) {
      // Hors ligne : le verrou local fonctionne déjà. Le code sera réaligné
      // avec le serveur à la prochaine modification depuis les paramètres.
    }
  }

  Future<void> _validerDeverrouillage() async {
    final notifier = ref.read(verrouProvider.notifier);
    final resultat = await notifier.deverrouillerAvecCode(_saisie);
    switch (resultat) {
      case ResultatVerrou.ouvert:
        if (mounted) setState(() => _saisie = '');
      case ResultatVerrou.codeIncorrect:
        final essais = ref.read(verrouProvider);
        _refuser(essais.enAttente
            ? 'Trop d\'essais. Patientez avant de réessayer.'
            : 'Code incorrect.');
        _demarrerDecompte();
      case ResultatVerrou.enAttente:
        _refuser('Patientez avant de réessayer.');
        _demarrerDecompte();
      case ResultatVerrou.indisponible:
        _refuser('Aucun code enregistré. Définissez-en un.');
    }
  }

  void _refuser(String message) {
    HapticFeedback.heavyImpact();
    _secousse.forward(from: 0);
    setState(() {
      _saisie = '';
      _erreur = true;
      _message = message;
    });
  }

  /// Rafraîchit le décompte d'attente chaque seconde, puis s'arrête de
  /// lui-même : une minuterie qui tourne en permanence userait la batterie
  /// pour rien.
  void _demarrerDecompte() {
    _minuterieAttente?.cancel();
    if (!ref.read(verrouProvider).enAttente) return;
    _minuterieAttente = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      ref.read(verrouProvider.notifier).rafraichirAttente();
      if (!ref.read(verrouProvider).enAttente) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verrou = ref.watch(verrouProvider);
    final utilisateur = ref.watch(authStateProvider).value?.user;
    final definition = verrou.etat == EtatVerrou.aDefinir;
    final attente = verrou.secondesAttente;

    final titre = definition
        ? (_premiereSaisie == null ? 'Créez votre code' : 'Confirmez le code')
        : 'Code de déverrouillage';
    final sousTitre = definition
        ? '$longueurCodeRequise chiffres. Il sera demandé à chaque ouverture.'
        : (utilisateur?.nom.trim().isNotEmpty ?? false)
            ? 'Bonjour ${utilisateur!.nom}'
            : 'Saisissez votre code';

    return PopScope(
      // On ne sort pas de l'écran de verrouillage par le bouton retour :
      // ce serait rouvrir l'application sans avoir passé la porte.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espace.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: Espace.xxl),
                      Icon(Icons.warehouse_rounded,
                          size: 56, color: scheme.primary),
                      const SizedBox(height: Espace.lg),
                      Text(titre,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      const SizedBox(height: Espace.xs),
                      Text(sousTitre,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center),
                      const SizedBox(height: Espace.xl),
                      _Pastilles(
                        saisie: _saisie.length,
                        total: _longueurAttendue,
                        erreur: _erreur,
                        secousse: _secousse,
                      ),
                      const SizedBox(height: Espace.md),
                      SizedBox(
                        height: 40,
                        child: attente > 0
                            ? Text('Réessayez dans $attente s',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.error,
                                    fontWeight: FontWeight.w600))
                            : _message != null
                                ? Text(_message!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _erreur
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                      fontWeight: _erreur
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ))
                                : null,
                      ),
                      const SizedBox(height: Espace.sm),
                      _Pave(
                        actif: !_occupe && attente == 0,
                        surChiffre: _chiffre,
                        surEffacement: _effacer,
                        // La longueur du code étant connue, la saisie part
                        // toute seule au dernier chiffre : il n'y a plus de
                        // touche « Valider ». La place libérée revient à
                        // l'empreinte, quand elle peut réellement aboutir.
                        actionSecondaire: !definition && verrou.biometrieActive
                            ? _ActionPave.biometrie
                            : _ActionPave.aucune,
                        surActionSecondaire: _tenterBiometrie,
                      ),
                      const SizedBox(height: Espace.lg),
                      if (!definition)
                        TextButton(
                          onPressed: _occupe ? null : _confirmerDeconnexion,
                          child: const Text('Utiliser un autre compte'),
                        ),
                      const SizedBox(height: Espace.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmerDeconnexion() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer de compte ?'),
        content: const Text(
            'Vous devrez vous reconnecter avec votre adresse et votre mot de passe, '
            'ce qui exige une connexion internet. Les saisies non encore '
            'synchronisées seraient perdues.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (confirme != true) return;
    await ref.read(verrouProvider.notifier).effacer();
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Vous êtes déconnecté.')));
    }
  }
}

/// Les pastilles qui matérialisent les chiffres déjà saisis.
class _Pastilles extends StatelessWidget {
  final int saisie;
  final int total;
  final bool erreur;
  final AnimationController secousse;

  const _Pastilles({
    required this.saisie,
    required this.total,
    required this.erreur,
    required this.secousse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: secousse,
      builder: (context, child) {
        // Trois allers-retours amortis : le mouvement dit « non » sans texte.
        final t = secousse.value;
        final decalage = t == 0 ? 0.0 : (1 - t) * 12 * _oscillation(t);
        return Transform.translate(offset: Offset(decalage, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: Duree.rapide,
              margin: const EdgeInsets.symmetric(horizontal: Espace.sm),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < saisie
                    ? (erreur ? scheme.error : scheme.primary)
                    : Colors.transparent,
                border: Border.all(
                  color: erreur
                      ? scheme.error
                      : (i < saisie ? scheme.primary : scheme.outlineVariant),
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static double _oscillation(double t) {
    const cycles = 3;
    return (t * cycles * 2 * 3.14159).remainder(2 * 3.14159) < 3.14159 ? 1 : -1;
  }
}

enum _ActionPave { aucune, biometrie }

class _Pave extends StatelessWidget {
  final bool actif;
  final void Function(int) surChiffre;
  final VoidCallback surEffacement;
  final _ActionPave actionSecondaire;
  final VoidCallback surActionSecondaire;

  const _Pave({
    required this.actif,
    required this.surChiffre,
    required this.surEffacement,
    required this.actionSecondaire,
    required this.surActionSecondaire,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        children: [
          for (final rangee in const [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final n in rangee)
                  _Touche(
                      label: '$n',
                      onTap: actif ? () => surChiffre(n) : null),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              switch (actionSecondaire) {
                _ActionPave.biometrie => _Touche(
                    icone: Icons.fingerprint_rounded,
                    onTap: actif ? surActionSecondaire : null),
                _ActionPave.aucune => const _Touche(),
              },
              _Touche(label: '0', onTap: actif ? () => surChiffre(0) : null),
              _Touche(
                  icone: Icons.backspace_outlined,
                  onTap: actif ? surEffacement : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _Touche extends StatelessWidget {
  final String? label;
  final IconData? icone;
  final VoidCallback? onTap;

  const _Touche({this.label, this.icone, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vide = label == null && icone == null;

    return Padding(
      padding: const EdgeInsets.all(Espace.sm),
      child: SizedBox(
        width: 72,
        height: 64,
        child: vide
            ? const SizedBox.shrink()
            : Material(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(Rayon.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Center(
                    child: label != null
                        ? Text(label!,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: onTap == null
                                  ? scheme.onSurfaceVariant
                                      .withValues(alpha: 0.4)
                                  : scheme.onSurface,
                            ))
                        : Icon(icone,
                            color: onTap == null
                                ? scheme.onSurfaceVariant
                                    .withValues(alpha: 0.4)
                                : scheme.onSurfaceVariant),
                  ),
                ),
              ),
      ),
    );
  }
}
