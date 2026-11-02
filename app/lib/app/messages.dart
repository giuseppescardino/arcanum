import '../src/rust/api/vault.dart';

String failureMessage(Object error) {
  if (error is VaultFailure) {
    return switch (error.code) {
      VaultFailureCode.wrongCredentials =>
        'Master password o Secret Key errata.',
      VaultFailureCode.invalidSecretKey =>
        'Secret Key non valida: controlla di averla copiata per intero.',
      VaultFailureCode.locked => 'Il vault è bloccato.',
      VaultFailureCode.notInitialized => 'Nessun vault trovato.',
      VaultFailureCode.alreadyInitialized => 'Il vault esiste già.',
      VaultFailureCode.notFound => 'Elemento non trovato.',
      VaultFailureCode.invalidLogin =>
        'Email, master password o Secret Key errati.',
      VaultFailureCode.emailTaken => 'Esiste già un account con questa email.',
      VaultFailureCode.sessionExpired => 'La sessione di sincronizzazione è scaduta: riconnetti questo dispositivo.',
      VaultFailureCode.tooManyRequests =>
        'Troppi tentativi. Riprova tra qualche minuto.',
      VaultFailureCode.invalidServerUrl =>
        'Indirizzo del server non valido: deve iniziare con https://',
      VaultFailureCode.network =>
        'Server non raggiungibile. Controlla la connessione e l\'indirizzo.',
      VaultFailureCode.notLinked => 'Questo vault non è collegato a un server.',
      VaultFailureCode.invalidInput => 'Valore non valido: ${error.message}',
      VaultFailureCode.passwordRequired =>
        'Per sicurezza serve la master password (almeno ogni 14 giorni '
            'e dopo un cambio password).',
      VaultFailureCode.internal => 'Errore interno: ${error.message}',
    };
  }
  if (error is StateError) return error.message;
  return 'Errore imprevisto: $error';
}
