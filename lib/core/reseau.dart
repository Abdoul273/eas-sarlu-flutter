import 'package:connectivity_plus/connectivity_plus.dart';

/// Vrai si au moins une interface réseau est active.
///
/// `connectivity_plus` 6.x renvoie une **liste** d'interfaces : comparer le
/// résultat directement à [ConnectivityResult.none] compile mais est toujours
/// faux, ce qui ferait croire à l'application qu'elle est en permanence en
/// ligne. Passer systématiquement par ce helper.
bool estConnecte(List<ConnectivityResult> resultats) {
  return resultats.any((r) => r != ConnectivityResult.none);
}

/// Teste l'état réseau courant de l'appareil.
Future<bool> aUneConnexion() async {
  return estConnecte(await Connectivity().checkConnectivity());
}
