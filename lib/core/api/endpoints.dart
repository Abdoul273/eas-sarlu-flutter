const kSupabaseProjectId = 'wqrfmmtavilyrnbjzhow';

/// Clé anon publique du projet Supabase — identique à celle utilisée par
/// l'application web (utils/supabase/info.tsx). Elle est publiable par
/// conception : les droits réels sont portés par le token de session.
const kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndxcmZtbXRhdmlseXJuYmp6aG93Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MzE1NzksImV4cCI6MjEwMDUwNzU3OX0.WIIsE39ggAPQTJSe1tbCbreGZAROuieQEveC6Z_E0BA';
const kApiBase =
    'https://$kSupabaseProjectId.supabase.co/functions/v1/server/make-server-54d9b660';

// Routes d'authentification
const kAuthLogin = '/auth/login';
const kAuthSetCode = '/auth/set-code';
const kAuthDevice = '/auth/device/'; // + :deviceId
const kAuthUnlock = '/auth/unlock';
const kAuthLogout = '/auth/logout';
const kAuthMe = '/auth/me';
const kAuthChangePassword = '/auth/change-password';

// Routes de données
const kDataVersion = '/data/version';
const kDataAll = '/data/all';
const kDataActivites = '/data/activites';
const kDataSync = '/data/sync';

// Écritures directes (préférer toujours /data/sync)
const kDataArticle = '/data/article';
const kDataArticleDelete = '/data/article/'; // + :id
const kDataClient = '/data/client';
const kDataVente = '/data/vente';
const kDataMouvement = '/data/mouvement';
const kDataFacturePaiement = '/data/facture-paiement';
const kDataFacturePaiementDelete =
    '/data/facture-paiement/'; // + :factureId/:paiementId
const kDataDepense = '/data/depense';
const kDataDepenseDelete = '/data/depense/'; // + :id
const kDataDepenseReglement = '/data/depense-reglement';
const kDataDepenseReglementDelete =
    '/data/depense-reglement/'; // + :depenseId/:reglementId
const kDataEntreprise = '/data/entreprise';

// Gestion
const kDataUsers = '/data/users';
const kDataUsersUpdate = '/data/users/'; // + :id (PATCH)
const kDataUsersDelete = '/data/users/'; // + :id (DELETE)
const kDataDevices = '/data/devices';
const kDataDevicesDelete = '/data/devices/'; // + :id (DELETE)
const kDataBackup = '/data/backup';
const kDataRestore = '/data/restore';
const kDataJournal = '/data/journal';

// Santé
const kHealth = '/health';
