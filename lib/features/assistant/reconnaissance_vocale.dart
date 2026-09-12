// ─── Nettoyage prudent des sous-titres vocaux ────────────────────────────────
//
// La reconnaissance audio confond souvent les noms de profilés dans un dépôt
// bruyant. On améliore la lisibilité sans jamais inventer une quantité, une
// dimension ou un prix : ces valeurs restent affichées dans la fiche à relire.

String normaliserTranscriptionMetier(String texte) {
  var s = texte.trim();
  if (s.isEmpty) return s;

  const remplacements = <String, String>{
    'fer a beton': 'fer à béton',
    'fer à bétons': 'fer à béton',
    'tole': 'tôle',
    'tôles': 'tôles',
    'corniere': 'cornière',
    'poteau ip en': 'poteau IPN',
    'ip en': 'IPN',
    'i p n': 'IPN',
    'u p n': 'UPN',
    'mètre carré': 'm²',
    'metre carre': 'm²',
  };
  for (final e in remplacements.entries) {
    s = s.replaceAll(
      RegExp('\\b${RegExp.escape(e.key)}\\b', caseSensitive: false),
      e.value,
    );
  }
  // Un « 30 fois 30 » oral désigne la section 30×30, pas une multiplication.
  s = s.replaceAllMapped(
    RegExp(r'\b(\d+(?:[,.]\d+)?)\s*(?:fois|x)\s*(\d+(?:[,.]\d+)?)\b',
        caseSensitive: false),
    (m) => '${m.group(1)}×${m.group(2)}',
  );
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
