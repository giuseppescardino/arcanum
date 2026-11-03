// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get languageTitle => 'Lingua';

  @override
  String get languageSystem => 'Predefinita di sistema';

  @override
  String get cancel => 'Annulla';

  @override
  String get copy => 'Copia';

  @override
  String get delete => 'Elimina';

  @override
  String get password => 'Password';

  @override
  String get masterPassword => 'Master password';

  @override
  String get secretKey => 'Secret Key';

  @override
  String get reconnect => 'Riconnetti';

  @override
  String get syncTitle => 'Sincronizzazione';

  @override
  String get syncNow => 'Sincronizza ora';

  @override
  String get noGroup => 'Senza gruppo';

  @override
  String get untitled => '(senza titolo)';

  @override
  String get username => 'Nome utente';

  @override
  String get passwordsDontMatch => 'Le password non coincidono';

  @override
  String get show => 'Mostra';

  @override
  String get hide => 'Nascondi';

  @override
  String vaultPasswordOf(String title) {
    return 'Password di \"$title\"';
  }

  @override
  String vaultDeleteGroupTitle(String group) {
    return 'Eliminare il gruppo \"$group\"?';
  }

  @override
  String get vaultDeleteGroupBody =>
      'Gli elementi non vengono eliminati: passano in \"Senza gruppo\".';

  @override
  String get vaultDeleteGroup => 'Elimina gruppo';

  @override
  String get vaultForgetSecretKeyTitle => 'Rimuovere la Secret Key?';

  @override
  String get vaultForgetSecretKeyBody =>
      'Al prossimo sblocco su questo dispositivo servirà la Secret Key dell\'Emergency Kit. Assicurati di averla.';

  @override
  String get vaultRemove => 'Rimuovi';

  @override
  String get vaultTitle => 'Vault';

  @override
  String get vaultLock => 'Blocca';

  @override
  String vaultEnableQuickUnlock(String method) {
    return 'Attiva sblocco con $method';
  }

  @override
  String vaultDisableQuickUnlock(String method) {
    return 'Disattiva sblocco con $method';
  }

  @override
  String get vaultEnableAutofill => 'Attiva compilazione automatica';

  @override
  String get vaultChangeMasterPassword => 'Cambia master password';

  @override
  String get vaultForgetSecretKey => 'Rimuovi Secret Key da questo dispositivo';

  @override
  String get vaultSearchHint => 'Cerca · Invio copia la password';

  @override
  String vaultSearchHintWithShortcut(String shortcut) {
    return 'Cerca · Invio copia la password · $shortcut da ovunque';
  }

  @override
  String get vaultNew => 'Nuovo';

  @override
  String get vaultSessionExpired =>
      'La sincronizzazione è sospesa: questo dispositivo deve riconnettersi al server.';

  @override
  String get vaultAllGroups => 'Tutti';

  @override
  String get vaultGroupActions => 'Azioni gruppo';

  @override
  String get vaultRenameGroup => 'Rinomina gruppo';

  @override
  String get vaultGroupName => 'Nome';

  @override
  String get vaultGroupMergeHint =>
      'Il gruppo esiste già: gli elementi verranno uniti.';

  @override
  String get vaultRename => 'Rinomina';

  @override
  String get vaultCopyTotp => 'Copia codice 2FA';

  @override
  String get vaultTotpCode => 'Codice 2FA';

  @override
  String get vaultCopyUsername => 'Copia nome utente';

  @override
  String get vaultCopyPassword => 'Copia password';

  @override
  String get vaultNoResults => 'Nessun risultato.';

  @override
  String get vaultEmpty =>
      'Il vault è vuoto.\nAggiungi la tua prima password con \"Nuovo\".';

  @override
  String get vaultMasterPasswordChanged => 'Master password aggiornata.';

  @override
  String get vaultCurrentPassword => 'Password attuale';

  @override
  String get vaultRequired => 'Obbligatoria';

  @override
  String get vaultNewPassword => 'Nuova password';

  @override
  String vaultMinLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Almeno $count caratteri',
      one: 'Almeno 1 carattere',
    );
    return '$_temp0';
  }

  @override
  String get vaultRepeatNewPassword => 'Ripeti nuova password';

  @override
  String get vaultChange => 'Cambia';

  @override
  String get editorDeleteTitle => 'Eliminare questo elemento?';

  @override
  String get editorDeleteBody => 'L\'operazione non può essere annullata.';

  @override
  String get editorNewTitle => 'Nuovo elemento';

  @override
  String get editorEditTitle => 'Modifica';

  @override
  String get editorRemoveFavorite => 'Rimuovi dai preferiti';

  @override
  String get editorFavorite => 'Preferito';

  @override
  String get editorSave => 'Salva';

  @override
  String get editorKindLogin => 'Login';

  @override
  String get editorKindSecureNote => 'Nota sicura';

  @override
  String get editorTitleLabel => 'Titolo';

  @override
  String get editorTitleRequired => 'Il titolo è obbligatorio';

  @override
  String get editorUsernameLabel => 'Nome utente / email';

  @override
  String get editorGenerate => 'Genera';

  @override
  String get editorWebsites => 'Siti web';

  @override
  String get editorWebsitesHelper => 'Uno per riga';

  @override
  String get editorTotpLabel => 'Chiave 2FA (TOTP)';

  @override
  String get editorTotpHelper => 'Chiave segreta o URI otpauth:// del sito';

  @override
  String get editorTotpInvalid => 'Chiave 2FA non valida';

  @override
  String get editorNotes => 'Note';

  @override
  String get editorGroup => 'Gruppo';

  @override
  String get editorGroupHelper => 'Scegline uno esistente o scrivine uno nuovo';

  @override
  String get totpCopyCode => 'Copia codice';

  @override
  String get totpCode => 'Codice 2FA';

  @override
  String get strengthVeryWeak => 'Molto debole';

  @override
  String get strengthWeak => 'Debole';

  @override
  String get strengthFair => 'Discreta';

  @override
  String get strengthStrong => 'Forte';

  @override
  String get strengthVeryStrong => 'Molto forte';

  @override
  String strengthLabelWithBits(String label, int bits) {
    return '$label · $bits bit';
  }

  @override
  String get syncDisconnectTitle => 'Disconnettere questo dispositivo?';

  @override
  String get syncDisconnectBody =>
      'Il vault resta su questo dispositivo ma smette di sincronizzarsi. I dati sul server e sugli altri dispositivi non vengono toccati.';

  @override
  String get syncDisconnect => 'Disconnetti';

  @override
  String get syncActive => 'Sincronizzazione attiva';

  @override
  String syncAccount(String email) {
    return 'Account: $email';
  }

  @override
  String syncServer(String url) {
    return 'Server: $url';
  }

  @override
  String get syncNotYetSynced => 'Non ancora sincronizzato in questa sessione.';

  @override
  String syncLastSync(String time) {
    return 'Ultima sincronizzazione: $time';
  }

  @override
  String syncLastSyncSummary(String time, int pulled, int pushed) {
    return 'Ultima sincronizzazione: $time ($pulled ricevuti, $pushed inviati)';
  }

  @override
  String syncLastSyncSummaryConflicts(
    String time,
    int pulled,
    int pushed,
    int conflicts,
  ) {
    return 'Ultima sincronizzazione: $time ($pulled ricevuti, $pushed inviati, $conflicts conflitti)';
  }

  @override
  String get syncDisconnectDevice => 'Disconnetti questo dispositivo';

  @override
  String get syncEncryptionNote =>
      'I dati vengono cifrati su questo dispositivo prima dell\'invio: il server conserva solo dati illeggibili e non conosce né la master password né la Secret Key.';

  @override
  String get syncEnableTitle => 'Sincronizza tra i tuoi dispositivi';

  @override
  String get syncEnableBody =>
      'Crea un account sul tuo server di sincronizzazione. Tutto viene cifrato qui prima di partire: il server vede solo dati illeggibili. Sugli altri dispositivi scegli \"Ho già un account\".';

  @override
  String get syncConfirmMasterPassword => 'Master password (per conferma)';

  @override
  String get syncEnable => 'Attiva sincronizzazione';

  @override
  String get syncReconnectTitle => 'Riconnetti questo dispositivo';

  @override
  String get syncReconnectBody =>
      'Inserisci la master password attuale dell\'account. Se l\'hai cambiata su un altro dispositivo, usa quella nuova: da ora varrà anche qui.';

  @override
  String get signInTitle => 'Accedi';

  @override
  String get signInIntro =>
      'Collega questo dispositivo al tuo account. Servono la Secret Key dell\'Emergency Kit e la master password.';

  @override
  String get unlockTitle => 'Sblocca il vault';

  @override
  String get unlockButton => 'Sblocca';

  @override
  String unlockWithMethod(String method) {
    return 'Sblocca con $method';
  }

  @override
  String get unlockEnterSecretKeyManually =>
      'Inserisci la Secret Key manualmente';

  @override
  String get setupTitle => 'Crea il tuo vault';

  @override
  String get setupIntro =>
      'La master password cifra tutti i tuoi dati sul dispositivo. Nessuno, nemmeno noi, può recuperarla: sceglila lunga e memorabile.';

  @override
  String setupMinLength(int count) {
    return 'Almeno $count caratteri';
  }

  @override
  String get setupRepeatMasterPassword => 'Ripeti master password';

  @override
  String get setupCreate => 'Crea vault';

  @override
  String get setupHaveAccount => 'Ho già un account: accedi';

  @override
  String get kitTitle => 'La tua Secret Key';

  @override
  String get kitIntro =>
      'Insieme alla master password, la Secret Key serve per aprire il vault su un nuovo dispositivo o dopo una reinstallazione. È salvata nel portachiavi di questo dispositivo, ma se lo perdi senza averla annotata i dati sono irrecuperabili.';

  @override
  String get kitWriteItDown =>
      'Scrivila su carta o salvala in un luogo sicuro, separato dalla master password.';

  @override
  String get kitSavedConfirm => 'Ho salvato la Secret Key in un luogo sicuro';

  @override
  String get kitContinue => 'Continua';

  @override
  String get commonEnterMasterPassword => 'Inserisci la master password';

  @override
  String get commonInvalidSecretKey => 'Secret Key non valida';

  @override
  String get commonSyncServer => 'Server di sincronizzazione';

  @override
  String get commonSyncServerHint => 'https://sync.esempio.it';

  @override
  String get commonSyncServerInvalid =>
      'Indirizzo completo, ad es. https://sync.esempio.it';

  @override
  String get commonEmail => 'Email';

  @override
  String get commonInvalidEmail => 'Email non valida';

  @override
  String get generatorTitle => 'Genera password';

  @override
  String get generatorPassphrase => 'Passphrase';

  @override
  String get generatorRegenerate => 'Rigenera';

  @override
  String get generatorUse => 'Usa';

  @override
  String get generatorLength => 'Lunghezza';

  @override
  String get generatorLowercase => 'Minuscole (a-z)';

  @override
  String get generatorUppercase => 'Maiuscole (A-Z)';

  @override
  String get generatorDigits => 'Numeri (0-9)';

  @override
  String get generatorSymbols => 'Simboli (!@#…)';

  @override
  String get generatorAvoidAmbiguous => 'Evita caratteri ambigui (l, 1, O, 0…)';

  @override
  String get generatorWords => 'Parole';

  @override
  String get generatorSeparator => 'Separatore';

  @override
  String get generatorSeparatorSpace => 'spazio';

  @override
  String get generatorCapitalize => 'Iniziali maiuscole';

  @override
  String get generatorIncludeNumber => 'Aggiungi un numero';

  @override
  String get autofillNoVault =>
      'Non c\'è ancora un vault su questo dispositivo. Apri Arcanum per crearlo o accedere al tuo account.';

  @override
  String get autofillClose => 'Chiudi';

  @override
  String get autofillDifferentSiteTitle => 'Sito diverso';

  @override
  String autofillDifferentSiteBody(String title, String domain) {
    return '\"$title\" non è salvato per $domain. Compilare comunque? Fallo solo se sei sicuro che il sito sia autentico.';
  }

  @override
  String get autofillFill => 'Compila';

  @override
  String get autofillPickerTitle => 'Scegli le credenziali';

  @override
  String autofillRequestedBy(String requester) {
    return 'Richiesto da: $requester';
  }

  @override
  String get autofillSearch => 'Cerca';

  @override
  String get autofillNoCredentials => 'Nessuna credenziale trovata.';

  @override
  String get autofillSuggested => 'Suggeriti';

  @override
  String get autofillAllCredentials => 'Tutte le credenziali';

  @override
  String get autofillOthers => 'Altre';

  @override
  String get errorWrongCredentials => 'Master password o Secret Key errata.';

  @override
  String get errorInvalidSecretKey =>
      'Secret Key non valida: controlla di averla copiata per intero.';

  @override
  String get errorLocked => 'Il vault è bloccato.';

  @override
  String get errorNotInitialized => 'Nessun vault trovato.';

  @override
  String get errorAlreadyInitialized => 'Il vault esiste già.';

  @override
  String get errorNotFound => 'Elemento non trovato.';

  @override
  String get errorInvalidLogin => 'Email, master password o Secret Key errati.';

  @override
  String get errorEmailTaken => 'Esiste già un account con questa email.';

  @override
  String get errorSessionExpired =>
      'La sessione di sincronizzazione è scaduta: riconnetti questo dispositivo.';

  @override
  String get errorTooManyRequests =>
      'Troppi tentativi. Riprova tra qualche minuto.';

  @override
  String get errorInvalidServerUrl =>
      'Indirizzo del server non valido: deve iniziare con https://';

  @override
  String get errorNetwork =>
      'Server non raggiungibile. Controlla la connessione e l\'indirizzo.';

  @override
  String get errorNotLinked => 'Questo vault non è collegato a un server.';

  @override
  String errorInvalidInput(String details) {
    return 'Valore non valido: $details';
  }

  @override
  String get errorPasswordRequired =>
      'Per sicurezza serve la master password (almeno ogni 14 giorni e dopo un cambio password).';

  @override
  String errorInternal(String details) {
    return 'Errore interno: $details';
  }

  @override
  String errorUnexpected(String details) {
    return 'Errore imprevisto: $details';
  }

  @override
  String get controllerDefaultDevice => 'Dispositivo';

  @override
  String get controllerMissingSecretKey => 'Secret Key mancante';

  @override
  String get quickUnlockReason => 'Sblocca il vault';

  @override
  String get quickUnlockFingerprint => 'impronta digitale';

  @override
  String get quickUnlockCancelled => 'Verifica annullata';

  @override
  String clipboardCopied(String label, int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondi',
    );
    return '$label copiato. Verrà cancellato tra $_temp0.';
  }
}
