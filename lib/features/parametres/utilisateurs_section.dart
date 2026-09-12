import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/auth/auth_state.dart';

// ─── Comptes et droits, vus du téléphone ──────────────────────────────────────
//
// Un compte modifié ici l'est POUR TOUT LE MONDE : la modification part au
// serveur, qui la range dans `app:users` et fait avancer la version des données.
// Chaque application — web comme téléphone — voit cette version bouger et
// rapatrie l'instantané. C'était déjà l'intention ; trois défauts l'empêchaient
// de tenir, et ils sont corrigés ici :
//
//   — activer ou désactiver un compte partait en PUT, une méthode que le serveur
//     n'expose pas. La requête tombait en 404 : le bouton ne faisait RIEN, sur
//     ce téléphone comme partout ailleurs. Et le même geste envoyait toujours
//     `actif: false`, si bien que réactiver un compte était impossible ;
//   — la liste était lue une seule fois, au premier affichage, et gardée telle
//     quelle. Un droit accordé depuis l'application web n'apparaissait jamais
//     sur le téléphone : l'écran montrait indéfiniment l'état d'avant. C'est ce
//     qui donnait le sentiment qu'une modification « ne s'appliquait qu'à
//     celui qui l'avait faite » — elle s'appliquait bien partout, mais les
//     autres écrans continuaient d'afficher l'ancienne version ;
//   — rien ne réclamait de synchronisation après une modification : il fallait
//     attendre le battement de fond pour que le téléphone qui venait d'écrire
//     se mette lui-même à jour.
//
// La liste vient désormais de la base locale, que le moteur de synchronisation
// réécrit à chaque instantané. Elle est donc vivante, et lisible hors ligne.

/// Les comptes, tels que le dernier instantané du serveur les a laissés.
///
/// Flux et non requête : c'est ce qui fait qu'un droit accordé ailleurs
/// apparaît ici tout seul, sans que personne ne rouvre l'écran.
final utilisateursProvider = StreamProvider<List<Utilisateur>>((ref) {
  return ref.watch(storesProvider).watchUtilisateurs();
});

/// Les écritures sur les comptes, et la remise à jour qui doit les suivre.
///
/// Chaque écriture fait trois choses, dans cet ordre : elle part au serveur —
/// qui seul décide —, sa réponse est rangée dans la base locale pour que
/// l'écran change à l'instant, et un cycle de synchronisation est réclamé pour
/// que le reste de l'application (les droits du compte connecté, notamment)
/// suive sans attendre le battement.
class UtilisateursRepo {
  final ApiClient _api;
  final Stores _stores;
  final SyncEngine _sync;

  UtilisateursRepo(this._api, this._stores, this._sync);

  Future<Utilisateur> creer({
    required String nom,
    required String email,
    required String motDePasse,
    required List<String> droits,
  }) async {
    final reponse = await _api.dio.post(kDataUsers, data: {
      'nom': nom,
      'email': email,
      'password': motDePasse,
      'droits': droits,
    });
    return _absorber(reponse.data);
  }

  /// Modification partielle — PATCH, la seule méthode qu'expose le serveur pour
  /// un compte. Les champs absents ne sont pas touchés.
  Future<Utilisateur> modifier(
    String id, {
    String? nom,
    bool? actif,
    bool? proprietaire,
    List<String>? droits,
    String? nouveauMotDePasse,
    bool? revoquerCodes,
  }) async {
    final reponse = await _api.dio.patch('$kDataUsersUpdate$id', data: {
      if (nom != null) 'nom': nom,
      if (actif != null) 'actif': actif,
      if (proprietaire != null) 'proprietaire': proprietaire,
      if (droits != null) 'droits': droits,
      if (nouveauMotDePasse != null && nouveauMotDePasse.isNotEmpty)
        'nouveauMotDePasse': nouveauMotDePasse,
      if (revoquerCodes != null) 'revoquerCodes': revoquerCodes,
    });
    return _absorber(reponse.data);
  }

  Future<void> supprimer(String id) async {
    await _api.dio.delete('$kDataUsersDelete$id');
    await _stores.supprimer('user', id);
    _sync.demanderSynchro();
  }

  /// Range la réponse du serveur dans la base locale et réclame un cycle.
  ///
  /// C'est le serveur qui a le dernier mot : on écrit ce qu'IL renvoie, jamais
  /// ce qu'on lui a demandé. Un droit qu'il aurait écarté se voit donc tout de
  /// suite à l'écran, au lieu de s'afficher comme accordé jusqu'au prochain
  /// rafraîchissement.
  Future<Utilisateur> _absorber(dynamic data) async {
    final user = Utilisateur.fromJson(Map<String, dynamic>.from(data as Map));
    await _stores.upsert('user', user);
    _sync.demanderSynchro();
    return user;
  }
}

final utilisateursRepoProvider = Provider<UtilisateursRepo>((ref) {
  return UtilisateursRepo(
    ref.watch(apiClientProvider),
    ref.watch(storesProvider),
    ref.watch(syncEngineProvider),
  );
});

class UtilisateursSection extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const UtilisateursSection({super.key, this.isEmbedded = false});

  @override
  ConsumerState<UtilisateursSection> createState() =>
      _UtilisateursSectionState();
}

class _UtilisateursSectionState extends ConsumerState<UtilisateursSection> {
  @override
  void initState() {
    super.initState();
    // Un instantané frais à l'ouverture : la base locale peut dater du dernier
    // battement, et on vient précisément ici pour voir l'état réel des comptes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncEngineProvider).demanderSynchro();
    });
  }

  Utilisateur? get _moi => ref.read(authStateProvider).value?.user;

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final utilisateursAsync = ref.watch(utilisateursProvider);
    final moi = ref.watch(authStateProvider).value?.user;

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
            Row(
              children: [
                IconButton(
                  tooltip: 'Rafraîchir',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () =>
                      ref.read(syncEngineProvider).forceSyncCycle(),
                ),
                TextButton.icon(
                  onPressed: () => _ajouterUtilisateur(context),
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
          ],
        ),
        // Ce qui est modifié ici vaut pour tous les appareils : le dire évite
        // de refaire le même réglage sur chaque téléphone.
        Text(
          'Les droits sont tenus par le serveur : une modification faite ici '
          "s'applique à tous les appareils, application web comprise.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Espace.sm),
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
              itemBuilder: (context, index) =>
                  _ligne(context, users[index], moi),
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

  Widget _ligne(BuildContext context, Utilisateur user, Utilisateur? moi) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actif = user.actif;
    final cestMoi = moi != null && moi.id == user.id;
    final initiales =
        user.nom.trim().isEmpty ? '?' : user.nom.trim()[0].toUpperCase();

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      cestMoi ? '${user.nom} (vous)' : user.nom,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (user.email.isNotEmpty)
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    // Ce que ce compte peut faire, dit sur la ligne : c'est la
                    // question qu'on se pose en regardant la liste, et il
                    // fallait ouvrir le formulaire pour y répondre.
                    Text(
                      user.proprietaire
                          ? 'Propriétaire · tous les droits'
                          : _resumeDroits(user.droits),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: user.proprietaire
                            ? context.metier.alerte
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              BadgePastille(
                texte: actif ? 'Actif' : 'Inactif',
                couleur:
                    actif ? context.metier.succes : context.metier.danger,
              ),
            ],
          ),
          const SizedBox(height: Espace.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: () => _modifierUtilisateur(context, user),
              ),
              // Se désactiver soi-même reviendrait à se mettre dehors depuis
              // l'écran d'où l'on administre : le serveur l'accepterait, mais
              // personne ne le veut vraiment. Le web pose la même garde.
              IconButton(
                tooltip: actif ? 'Désactiver' : 'Réactiver',
                icon: Icon(
                  actif
                      ? Icons.block_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: actif ? scheme.error : context.metier.succes,
                ),
                onPressed:
                    cestMoi ? null : () => _basculerActif(user),
              ),
              if (!cestMoi)
                IconButton(
                  tooltip: 'Supprimer le compte',
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: scheme.error),
                  onPressed: () => _supprimerUtilisateur(user),
                ),
            ],
          ),
        ],
      ),
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
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncEngineProvider).forceSyncCycle(),
        child: ListView(
          padding: const EdgeInsets.all(Espace.page),
          children: [_buildContent(context)],
        ),
      ),
    );
  }

  /// Les droits d'un compte en une ligne. Aucun droit se dit, plutôt que de
  /// laisser un blanc qu'on prendrait pour un défaut d'affichage.
  String _resumeDroits(List<String> brut) {
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
    final moi = _moi;
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
                    decoration:
                        const InputDecoration(labelText: 'Identifiant')),
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
                  final cree = await ref.read(utilisateursRepoProvider).creer(
                        nom: nomCtrl.text.trim(),
                        email: emailCtrl.text.trim(),
                        motDePasse: mdpCtrl.text,
                        droits: droits,
                      );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _verifierDroitsRetenus(droits, cree);
                } catch (e) {
                  _erreur(e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _modifierUtilisateur(BuildContext context, Utilisateur user) {
    final nomCtrl = TextEditingController(text: user.nom);
    final mdpCtrl = TextEditingController();
    final droits = normaliserDroits(user.droits);
    // Faux par défaut, et non vrai : un champ manquant ne doit pas faire passer
    // un compte ordinaire pour un propriétaire — ses droits ne seraient alors
    // jamais envoyés, et le formulaire ferait semblant de les enregistrer.
    final proprietaire = user.proprietaire;
    // Nommer un propriétaire est réservé aux propriétaires. Le serveur applique
    // la même règle ; la case n'est montrée que quand elle peut aboutir.
    final jePeuxNommerProprietaire = _moi?.proprietaire ?? false;
    final cestMoi = _moi?.id == user.id;
    var veutProprietaire = proprietaire;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Modifier ${user.nom}'),
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
                if (jePeuxNommerProprietaire && !cestMoi)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Propriétaire',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'Détient tous les droits en permanence et peut en '
                        'nommer d\'autres',
                        style: TextStyle(fontSize: 11)),
                    value: veutProprietaire,
                    onChanged: (v) =>
                        setDialogState(() => veutProprietaire = v ?? false),
                  ),
                if (veutProprietaire)
                  const Padding(
                    padding: EdgeInsets.only(top: Espace.sm),
                    child: Text(
                      'Un propriétaire détient tous les droits en permanence : '
                      'il n\'y a rien à cocher pour lui.',
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
                  final maj =
                      await ref.read(utilisateursRepoProvider).modifier(
                            user.id,
                            nom: nomCtrl.text.trim().isEmpty
                                ? null
                                : nomCtrl.text.trim(),
                            proprietaire: veutProprietaire != proprietaire
                                ? veutProprietaire
                                : null,
                            droits: veutProprietaire ? null : droits,
                            nouveauMotDePasse: mdpCtrl.text,
                            // Un mot de passe réinitialisé doit fermer les
                            // codes courts qu'il avait ouverts : sinon
                            // l'ancien code déverrouille encore le téléphone.
                            revoquerCodes:
                                mdpCtrl.text.isNotEmpty ? true : null,
                          );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!veutProprietaire) _verifierDroitsRetenus(droits, maj);
                } catch (e) {
                  _erreur(e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Le serveur peut répondre « c'est fait » en ayant écarté un droit qu'il ne
  /// connaît pas — il est alors plus ancien que cette application. Le taire
  /// ferait chercher longtemps pourquoi une case se décoche toute seule.
  void _verifierDroitsRetenus(List<String> demandes, Utilisateur obtenu) {
    if (obtenu.proprietaire) return;
    final retenus = obtenu.droitsEffectifs;
    final perdus = demandes.where((d) => !retenus.contains(d)).toList();
    if (perdus.isEmpty) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      content: Text(
        'Le serveur n\'a pas retenu : '
        '${perdus.map((d) => kLibelleDroit[d] ?? d).join(', ')}. '
        'Il est probablement plus ancien que cette application.',
      ),
    ));
  }

  /// Le message du serveur plutôt que la trace technique : « Vous n'avez pas le
  /// droit de… » se lit, « DioException [bad response] » non.
  void _erreur(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e is ApiException ? e.messageApi : 'Erreur : $e'),
    ));
  }

  void _basculerActif(Utilisateur user) async {
    final desactiver = user.actif;
    if (desactiver) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Désactiver l\'utilisateur'),
          content: Text(
              '${user.nom} ne pourra plus se connecter, sur aucun appareil. '
              'Son historique reste intact. Continuer ?'),
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
      if (confirm != true) return;
    }

    try {
      await ref
          .read(utilisateursRepoProvider)
          .modifier(user.id, actif: !user.actif);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(desactiver
            ? '${user.nom} est désactivé — son historique reste intact'
            : '${user.nom} peut se reconnecter'),
      ));
    } catch (e) {
      _erreur(e);
    }
  }

  void _supprimerUtilisateur(Utilisateur user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le compte'),
        content: Text(
            'Supprimer définitivement le compte de ${user.nom} ? Si des '
            'opérations sont enregistrées à son nom, désactivez-le plutôt : '
            'son nom doit rester lisible sur son historique.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          AppButton(
            label: 'Supprimer',
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(utilisateursRepoProvider).supprimer(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Compte supprimé')));
    } catch (e) {
      _erreur(e);
    }
  }
}
