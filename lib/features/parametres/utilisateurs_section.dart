import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/auth/auth_state.dart';

// Provider pour la liste des utilisateurs
final utilisateursProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final response = await apiClient.dio.get(kDataUsers);
  return List<Map<String, dynamic>>.from(response.data);
});

class UtilisateursSection extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const UtilisateursSection({super.key, this.isEmbedded = false});

  @override
  ConsumerState<UtilisateursSection> createState() =>
      _UtilisateursSectionState();
}

class _UtilisateursSectionState extends ConsumerState<UtilisateursSection> {
  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final utilisateursAsync = ref.watch(utilisateursProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'COMPTES UTILISATEURS',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            TextButton.icon(
              onPressed: () => _ajouterUtilisateur(context),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: Espace.xs),
        utilisateursAsync.when(
          data: (users) {
            if (users.isEmpty) {
              return const EtatVide(
                message: 'Aucun utilisateur configuré',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: Espace.xs),
              itemBuilder: (context, index) {
                final user = users[index];
                final actif = user['actif'] as bool? ?? true;
                final initiales = (user['nom'] as String? ?? '?')
                    .trim()
                    .substring(0, 1)
                    .toUpperCase();

                return AppCard(
                  margin: EdgeInsets.zero,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: actif
                            ? scheme.primary.withValues(alpha: 0.12)
                            : scheme.error.withValues(alpha: 0.12),
                        child: Text(
                          initiales,
                          style: TextStyle(
                            color: actif ? scheme.primary : scheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: Espace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['nom'] ?? '',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              user['email'] ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            // Ce que ce compte peut faire, dit sur la ligne :
                            // c'est la question qu'on se pose en regardant la
                            // liste, et il fallait ouvrir le formulaire pour y
                            // répondre.
                            Text(
                              (user['proprietaire'] as bool? ?? false)
                                  ? 'Propriétaire · tous les droits'
                                  : _resumeDroits(user['droits']),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: (user['proprietaire'] as bool? ?? false)
                                    ? context.metier.alerte
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      BadgePastille(
                        texte: actif ? 'Actif' : 'Inactif',
                        couleur: actif
                            ? context.metier.succes
                            : context.metier.danger,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        onPressed: () => _modifierUtilisateur(context, user),
                      ),
                      IconButton(
                        icon: Icon(
                          actif
                              ? Icons.block_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: actif ? scheme.error : context.metier.succes,
                        ),
                        onPressed: () =>
                            _desactiverUtilisateur(context, user['id']),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(Espace.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(Espace.md),
            child: Center(child: Text('Erreur: $e')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return _buildContent(context);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ajouterUtilisateur(context),
        child: const Icon(Icons.person_add),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Espace.page),
        child: _buildContent(context),
      ),
    );
  }

  /// Les droits d'un compte en une ligne. Aucun droit se dit, plutôt que de
  /// laisser un blanc qu'on prendrait pour un défaut d'affichage.
  String _resumeDroits(dynamic brut) {
    final droits = normaliserDroits(brut);
    if (droits.isEmpty) return 'Aucun droit';
    return droits.map((d) => kLibelleDroit[d] ?? d).join(' · ');
  }

  /// Sélecteur de droits, partagé par la création et la modification.
  ///
  /// On n'accorde que ce qu'on détient soi-même — le serveur applique la même
  /// règle et refuserait le reste ; grisé ici, l'utilisateur comprend pourquoi
  /// au lieu de buter sur un refus.
  Widget _selecteurDroits({
    required List<String> choisis,
    required void Function(String droit, bool coche) onBascule,
  }) {
    final moi = ref.read(authStateProvider).value?.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Espace.sm),
        Text('CE QUE CE COMPTE PEUT FAIRE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                )),
        for (final entree in kDroits.entries)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(kLibelleDroit[entree.key] ?? entree.key,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(entree.value, style: const TextStyle(fontSize: 11)),
            value: choisis.contains(entree.key),
            onChanged: (moi?.aLeDroit(entree.key) ?? false)
                ? (v) => onBascule(entree.key, v ?? false)
                : null,
          ),
      ],
    );
  }

  void _ajouterUtilisateur(BuildContext context) {
    final nomCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final mdpCtrl = TextEditingController();
    // Par défaut, le strict quotidien : un compte créé « pour dépanner » et
    // jamais revu ne doit pas garder des droits qu'il n'aura eus qu'un jour.
    final droits = <String>['vendre', 'depenses', 'finances'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nouvel utilisateur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nomCtrl,
                    decoration: const InputDecoration(labelText: 'Nom')),
                TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Identifiant')),
                TextField(
                    controller: mdpCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Mot de passe provisoire')),
                _selecteurDroits(
                  choisis: droits,
                  onBascule: (d, coche) => setDialogState(
                      () => coche ? droits.add(d) : droits.remove(d)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            AppButton(
              label: 'Créer',
              onPressed: () async {
                try {
                  final apiClient = ref.read(apiClientProvider);
                  await apiClient.dio.post(kDataUsers, data: {
                    'nom': nomCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'password': mdpCtrl.text,
                    'droits': droits,
                  });
                  ref.invalidate(utilisateursProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_messageErreur(e))));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _modifierUtilisateur(
      BuildContext context, Map<String, dynamic> user) {
    final nomCtrl = TextEditingController(text: user['nom'] as String? ?? '');
    final mdpCtrl = TextEditingController();
    final droits = normaliserDroits(user['droits']);
    final proprietaire = user['proprietaire'] as bool? ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Modifier ${user['nom']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: nomCtrl,
                    decoration: const InputDecoration(labelText: 'Nom')),
                TextField(
                    controller: mdpCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Nouveau mot de passe',
                        helperText: 'Laisser vide pour ne pas le changer')),
                if (proprietaire)
                  const Padding(
                    padding: EdgeInsets.only(top: Espace.sm),
                    child: Text(
                      'Ce compte est propriétaire : il détient tous les droits '
                      'en permanence. Ils se modifient depuis l\'application web.',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else
                  _selecteurDroits(
                    choisis: droits,
                    onBascule: (d, coche) => setDialogState(
                        () => coche ? droits.add(d) : droits.remove(d)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            AppButton(
              label: 'Enregistrer',
              onPressed: () async {
                try {
                  final apiClient = ref.read(apiClientProvider);
                  // PATCH, et non PUT : c'est la méthode qu'expose le serveur.
                  // Les noms de champs sont les siens, eux aussi — `nom`,
                  // `droits`, `nouveauMotDePasse`.
                  final payload = <String, dynamic>{
                    'nom': nomCtrl.text.trim(),
                    if (!proprietaire) 'droits': droits,
                    if (mdpCtrl.text.isNotEmpty)
                      'nouveauMotDePasse': mdpCtrl.text,
                  };
                  await apiClient.dio
                      .patch('$kDataUsersUpdate${user['id']}', data: payload);
                  ref.invalidate(utilisateursProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_messageErreur(e))));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Le message du serveur plutôt que la trace technique : « Vous n'avez pas le
  /// droit de… » se lit, « DioException [bad response] » non.
  String _messageErreur(Object e) =>
      e is ApiException ? e.messageApi : 'Erreur : $e';

  void _desactiverUtilisateur(BuildContext context, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Désactiver l\'utilisateur'),
        content: const Text(
            'L\'utilisateur ne pourra plus se connecter. Continuer ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
            label: 'Désactiver',
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.dio
            .put('$kDataUsers/$userId', data: {'actif': false});
        ref.invalidate(utilisateursProvider);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }
}
