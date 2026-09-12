import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';
import '../api/api_client.dart';
import 'auth_repository.dart';

// --- Providers de base ---

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(
      // Quand la clé du coffre change sous nos pieds (réinstallation,
      // restauration de sauvegarde, mise à jour système), tout ce qui y est
      // devient illisible : BAD_DECRYPT au démarrage, écran rouge, et rien
      // d'autre ne s'affiche plus jamais. On efface plutôt le coffre : le
      // vendeur se reconnecte, et l'application repart.
      resetOnError: true,
      encryptedSharedPreferences: true,
    ),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return ApiClient(secureStorage: secureStorage);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final secureStorage = ref.watch(secureStorageProvider);
  return AuthRepository(apiClient: apiClient, secureStorage: secureStorage);
});

// --- État d'authentification ---

/// Clé du profil conservé sur l'appareil.
///
/// Sans lui, l'application n'avait aucun moyen de savoir QUI était connecté
/// sans appeler le serveur — et c'est exactement ce qui renvoyait le magasin
/// vers la page de connexion dès que le réseau manquait.
const _cleUtilisateur = 'session_utilisateur';

@immutable
class AuthState {
  final Utilisateur? user;
  final bool isLoading;
  final String? error;

  /// La session locale existe mais le serveur l'a rejetée : il faudra se
  /// reconnecter. On ne coupe pas l'accès pour autant — les données du
  /// téléphone restent consultables et la file d'attente reste intacte.
  final bool sessionExpiree;

  /// Pourquoi le serveur a rejeté la session, quand il le dit — un appareil
  /// retiré des appareils de confiance, typiquement. Nul quand c'est une simple
  /// expiration : dans ce cas, il n'y a rien à expliquer.
  final String? motifDeconnexion;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.sessionExpiree = false,
    this.motifDeconnexion,
  });

  bool get estConnecte => user != null;

  AuthState copyWith({
    Utilisateur? user,
    bool? isLoading,
    String? error,
    bool? sessionExpiree,
    String? motifDeconnexion,
    bool effacerUtilisateur = false,
    bool effacerErreur = false,
  }) =>
      AuthState(
        user: effacerUtilisateur ? null : (user ?? this.user),
        isLoading: isLoading ?? this.isLoading,
        error: effacerErreur ? null : (error ?? this.error),
        sessionExpiree: sessionExpiree ?? this.sessionExpiree,
        motifDeconnexion: motifDeconnexion ?? this.motifDeconnexion,
      );
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  FlutterSecureStorage get _stockage => ref.read(secureStorageProvider);
  AuthRepository get _authRepo => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    // Un 401 sur une route de données signifie que le jeton n'est plus accepté.
    // On le signale sans détruire la session : le magasin doit pouvoir
    // continuer à consulter ses données et à saisir hors ligne. La reconnexion
    // sera demandée au moment où elle est possible, c'est-à-dire en ligne.
    ref.read(apiClientProvider).onUnauthorized = _signalerSessionExpiree;

    // 1. La session enregistrée fait foi au démarrage. Elle est lue localement,
    //    donc l'application s'ouvre sans réseau, immédiatement, sur les données
    //    déjà présentes.
    final utilisateur = await _lireUtilisateurEnregistre();
    final jeton = await _stockage.read(key: 'session_token');

    if (utilisateur == null || jeton == null || jeton.isEmpty) {
      return const AuthState();
    }

    // 2. La revalidation auprès du serveur se fait en arrière-plan. Qu'elle
    //    échoue faute de réseau ne change rien : on est déjà entré.
    unawaited(_revaliderEnArrierePlan());

    return AuthState(user: utilisateur);
  }

  /// Confronte le profil local au serveur, sans jamais bloquer le démarrage.
  Future<void> _revaliderEnArrierePlan() async {
    try {
      final donnees = await _authRepo.me();
      if (donnees == null) return; // Hors ligne : on garde la session locale.
      if (donnees['id'] == null) return;
      final aJour = Utilisateur.fromJson(donnees);
      await _enregistrerUtilisateur(aJour);
      final actuel = state.value;
      if (actuel != null) {
        state = AsyncValue.data(
            actuel.copyWith(user: aJour, sessionExpiree: false));
      }
    } catch (_) {
      // Réseau absent ou serveur indisponible : la session locale reste valable.
    }
  }

  /// Applique les droits venus d'un instantané du serveur.
  ///
  /// Appelée à chaque synchronisation, c'est elle qui fait qu'un droit accordé
  /// ou retiré depuis l'application web prend effet sur le téléphone **sans le
  /// redémarrer**. Auparavant le compte n'était relu qu'au démarrage : nommer
  /// quelqu'un propriétaire n'avait aucun effet tant qu'il n'avait pas fermé et
  /// rouvert l'application — ce que personne ne devine.
  ///
  /// Un compte désactivé entre-temps est déconnecté sur-le-champ : le serveur
  /// le refuserait de toute façon, autant le dire tout de suite.
  Future<void> appliquerUtilisateurs(List<Utilisateur> utilisateurs) async {
    final actuel = state.value;
    final moi = actuel?.user;
    if (moi == null) return;

    Utilisateur? frais;
    for (final u in utilisateurs) {
      if (u.id == moi.id) {
        frais = u;
        break;
      }
    }
    // Compte absent de l'instantané : supprimé côté serveur, ou liste partielle
    // reçue par un compte qui ne gère pas les utilisateurs. On ne déduit rien.
    if (frais == null) return;

    if (!frais.actif) {
      await logout();
      return;
    }

    // Comparaison sur le JSON : les droits sont une liste, et deux listes
    // identiques ne sont pas le même objet.
    if (jsonEncode(frais.toJson()) == jsonEncode(moi.toJson())) return;

    await _enregistrerUtilisateur(frais);
    state = AsyncValue.data(actuel!.copyWith(user: frais));
  }

  void _signalerSessionExpiree(String? motif) {
    final actuel = state.value;
    if (actuel == null || !actuel.estConnecte) return;
    if (actuel.sessionExpiree && actuel.motifDeconnexion == motif) return;
    state = AsyncValue.data(
        actuel.copyWith(sessionExpiree: true, motifDeconnexion: motif));
  }

  Future<Utilisateur?> _lireUtilisateurEnregistre() async {
    try {
      final brut = await _stockage.read(key: _cleUtilisateur);
      if (brut == null || brut.isEmpty) return null;
      final json = jsonDecode(brut);
      if (json is! Map<String, dynamic> || json['id'] == null) return null;
      return Utilisateur.fromJson(json);
    } catch (_) {
      // Un profil illisible ne doit pas empêcher l'ouverture : on l'ignore et
      // l'application demandera une connexion.
      return null;
    }
  }

  Future<void> _enregistrerUtilisateur(Utilisateur user) async {
    await _stockage.write(
        key: _cleUtilisateur, value: jsonEncode(user.toJson()));
  }

  Future<void> login(String email, String password, {String? deviceNom}) async {
    state = const AsyncValue.data(AuthState(isLoading: true));
    try {
      final data = await _authRepo.login(email, password, deviceNom: deviceNom);
      final user = Utilisateur.fromJson(data['user'] as Map<String, dynamic>);
      await _enregistrerUtilisateur(user);
      state = AsyncValue.data(AuthState(user: user));
    } catch (e) {
      state = AsyncValue.data(AuthState(error: _message(e)));
    }
  }

  Future<void> unlock(String deviceId, String userId, String code) async {
    state = const AsyncValue.data(AuthState(isLoading: true));
    try {
      final data = await _authRepo.unlock(deviceId, userId, code);
      final user = Utilisateur.fromJson(data['user'] as Map<String, dynamic>);
      await _enregistrerUtilisateur(user);
      state = AsyncValue.data(AuthState(user: user));
    } catch (e) {
      state = AsyncValue.data(AuthState(error: _message(e)));
    }
  }

  /// Déconnexion volontaire. C'est le seul chemin qui efface le profil local :
  /// une panne de réseau, elle, ne doit jamais déconnecter.
  Future<void> logout() async {
    await _authRepo.logout();
    await _stockage.delete(key: _cleUtilisateur);
    state = const AsyncValue.data(AuthState());
  }

  String _message(Object e) =>
      e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', '');
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Vrai dès que l'application dispose d'une session utilisable, en ligne comme
/// hors ligne. C'est ce que le routeur doit regarder.
final estConnecteProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).value?.estConnecte ?? false;
});

// --- État de la porte d'entrée (Auth Gate) ---

enum AuthGateStep { initial, loading, login, unlock }

class AuthGateState {
  final AuthGateStep step;
  final Map<String, dynamic>? deviceInfo; // contient nom, comptes...
  final String? error;

  const AuthGateState({required this.step, this.deviceInfo, this.error});

  factory AuthGateState.initial() =>
      const AuthGateState(step: AuthGateStep.initial);
}

class AuthGateNotifier extends StateNotifier<AuthGateState> {
  final AuthRepository _authRepo;

  AuthGateNotifier(this._authRepo) : super(AuthGateState.initial());

  Future<void> decide() async {
    state = const AuthGateState(step: AuthGateStep.loading);
    try {
      final deviceId = await _authRepo.getDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        // Aucun appareil enrôlé → login
        state = const AuthGateState(step: AuthGateStep.login);
        return;
      }
      final info = await _authRepo.getDeviceInfo(deviceId);
      if (info == null || (info['comptes'] as List?)?.isEmpty == true) {
        // Appareil inconnu, sans comptes, ou serveur injoignable → login.
        state = const AuthGateState(step: AuthGateStep.login);
        return;
      }
      // Comptes trouvés → unlock
      state = AuthGateState(step: AuthGateStep.unlock, deviceInfo: info);
    } catch (e) {
      state = AuthGateState(step: AuthGateStep.login, error: e.toString());
    }
  }

  /// Bascule vers la connexion par mot de passe (depuis l'écran de
  /// déverrouillage par code).
  void allerVersLogin() {
    state = const AuthGateState(step: AuthGateStep.login);
  }
}

final authGateProvider =
    StateNotifierProvider<AuthGateNotifier, AuthGateState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return AuthGateNotifier(authRepo);
});
