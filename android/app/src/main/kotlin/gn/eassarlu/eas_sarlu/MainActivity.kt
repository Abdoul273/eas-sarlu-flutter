package gn.eassarlu.eas_sarlu

import io.flutter.embedding.android.FlutterFragmentActivity

// `FlutterFragmentActivity` et non `FlutterActivity` : le déverrouillage
// biométrique passe par androidx.biometric, qui affiche sa boîte de dialogue
// dans un FragmentManager. Sur une FlutterActivity ordinaire, l'appel échoue
// avec « no_fragment_activity » — une erreur invisible à la compilation, qui ne
// se manifeste que sur l'appareil, au moment précis où l'utilisateur pose son
// doigt sur le capteur.
class MainActivity : FlutterFragmentActivity()
