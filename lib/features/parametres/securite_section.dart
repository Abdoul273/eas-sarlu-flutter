import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/auth/verrou_local.dart';

// ─── Sécurité de l'appareil ───────────────────────────────────────────────────
// Cette rubrique n'est protégée par aucun droit, et c'est délibéré. Le verrou et
// l'empreinte protègent le téléphone de celui qui le tient, pas les données des
// autres : un vendeur sans aucun droit d'écriture pose le même téléphone sur le
// même comptoir que le gérant. Lui refuser l'empreinte au motif qu'il ne peut
// rien modifier reviendrait à lui imposer six chiffres cent fois par jour pour
// protéger ce qu'il a le droit de lire.
//
// Rien ici ne touche au compte ni au serveur : tout est local à l'appareil.

class SecuriteSection extends ConsumerStatefulWidget {
  const SecuriteSection({super.key});

  @override
  ConsumerState<SecuriteSection> createState() => _SecuriteSectionState();
}

class _SecuriteSectionState extends ConsumerState<SecuriteSection> {
  @override
  void initState() {
    super.initState();
    // L'empreinte a pu être enrôlée depuis le démarrage — souvent parce que
    // c'est cette page qui l'a demandé.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(verrouProvider.notifier).rafraichirBiometrie());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verrou = ref.watch(verrouProvider);
    final notifier = ref.read(verrouProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Le code à ${verrou.longueurCode} chiffres est demandé à chaque '
          'ouverture. Il est vérifié sur l\'appareil : il fonctionne sans '
          'réseau.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Espace.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.fingerprint_rounded,
              color: verrou.biometrieDisponible ? scheme.primary : scheme.outline),
          value: verrou.biometrieActive,
          // Une bascule qui ne peut pas aboutir doit être éteinte, pas active
          // et sans effet : sur un téléphone sans empreinte enrôlée, on la
          // désactive et on dit pourquoi.
          onChanged: verrou.biometrieDisponible
              ? (actif) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await notifier.definirBiometrie(actif);
                  if (!ok && actif) {
                    messenger.showSnackBar(const SnackBar(
                        content:
                            Text('Authentification biométrique refusée.')));
                  }
                }
              : null,
          title: const Text('Déverrouiller par empreinte'),
          subtitle: Text(verrou.biometrieDisponible
              ? 'Le code à ${verrou.longueurCode} chiffres reste utilisable en '
                  'secours.'
              : 'Aucune empreinte n\'est enregistrée sur ce téléphone. '
                  'Ajoutez-en une dans les réglages Android, puis revenez ici.'),
        ),
        if (verrou.longueurCode != longueurCodeRequise) ...[
          const SizedBox(height: Espace.sm),
          Container(
            padding: const EdgeInsets.all(Espace.md),
            decoration: BoxDecoration(
              color: context.metier.alerte.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Rayon.md),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 20, color: context.metier.alerte),
                const SizedBox(width: Espace.sm),
                Expanded(
                  child: Text(
                    'Votre code ne compte que ${verrou.longueurCode} chiffres. '
                    'Les nouveaux codes en font $longueurCodeRequise, cent fois '
                    'plus difficiles à deviner.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Espace.sm),
        AppButton(
          label: 'Changer le code de déverrouillage',
          icon: Icons.password_rounded,
          isTonal: true,
          expanded: true,
          onPressed: () => _changerCode(context),
        ),
      ],
    );
  }

  Future<void> _changerCode(BuildContext context) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer le code'),
        content: const Text(
          'L\'application va se verrouiller et vous demander un nouveau code de '
          '$longueurCodeRequise chiffres, à saisir deux fois. Aucune donnée '
          'n\'est perdue.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
            label: 'Continuer',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    // On repasse par l'écran de création : c'est lui qui impose la confirmation
    // du nouveau code et qui le réaligne avec le serveur, sans quoi une faute de
    // frappe enfermerait l'utilisateur dehors dès la prochaine ouverture.
    await ref.read(verrouProvider.notifier).effacer();
  }
}
