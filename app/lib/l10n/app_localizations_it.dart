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
      'Gli elementi non vengono eliminati: quelli del gruppo e dei suoi sottogruppi passano in \"Senza gruppo\".';

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
  String get vaultAbout => 'Informazioni';

  @override
  String aboutVersion(String version) {
    return 'Versione $version';
  }

  @override
  String get aboutDescription =>
      'Password manager zero-knowledge: i dati vengono cifrati su questo dispositivo prima della sincronizzazione.';

  @override
  String get breachTitle => 'Password compromesse';

  @override
  String get breachExplanation =>
      'Arcanum confronta le tue password con l\'archivio di Have I Been Pwned delle password esposte in violazioni di dati. Da questo dispositivo escono solo i primi 5 caratteri dell\'hash SHA-1 di ogni password, su una connessione cifrata: né la password né il suo hash completo vengono mai inviati. I risultati restano in memoria e vengono dimenticati quando il vault si blocca.';

  @override
  String get breachAutoTitle => 'Controllo automatico e promemoria';

  @override
  String get breachAutoSubtitle =>
      'Controlla una password quando la apri o la modifichi e ricordami ogni mese di controllare tutto il vault';

  @override
  String get breachNeverChecked =>
      'Il vault non è mai stato controllato per intero';

  @override
  String breachLastCheck(String date) {
    return 'Ultimo controllo completo: $date';
  }

  @override
  String get breachCheckAll => 'Controlla tutte le password';

  @override
  String breachProgress(int done, int total) {
    return 'Controllate $done di $total';
  }

  @override
  String breachSomeFailed(int count, String error) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Non è stato possibile controllare $count password',
      one: 'Non è stato possibile controllare 1 password',
    );
    return '$_temp0: $error';
  }

  @override
  String get breachNoneFound =>
      'Nessuna delle tue password compare nelle violazioni note.';

  @override
  String breachCompromisedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count password compaiono in violazioni di dati: cambiale',
      one: '1 password compare in violazioni di dati: cambiala',
    );
    return '$_temp0';
  }

  @override
  String breachFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Trovata $count volte in violazioni di dati',
      one: 'Trovata una volta in violazioni di dati',
    );
    return '$_temp0';
  }

  @override
  String get breachNotFound => 'Non trovata nelle violazioni note';

  @override
  String get breachChecking => 'Controllo nelle violazioni note…';

  @override
  String breachCheckFailed(String error) {
    return 'Impossibile controllare: $error';
  }

  @override
  String get breachRetry => 'Riprova';

  @override
  String get breachCheckThis => 'Controlla se è compromessa';

  @override
  String get breachReminderFirst =>
      'Controlla se qualcuna delle tue password compare in violazioni di dati note.';

  @override
  String get breachReminder =>
      'Le tue password non vengono controllate nelle violazioni note da più di un mese.';

  @override
  String get breachLater => 'Più tardi';

  @override
  String get breachCheckNow => 'Controlla ora';

  @override
  String get breachCompromisedTooltip =>
      'Password trovata in una violazione di dati';

  @override
  String get vaultForgetSecretKey => 'Rimuovi Secret Key da questo dispositivo';

  @override
  String get vaultSignOut => 'Esci da questo dispositivo';

  @override
  String get vaultSignOutTitle => 'Uscire?';

  @override
  String get vaultSignOutBodySynced =>
      'Il vault verrà cancellato da questo dispositivo insieme alla Secret Key. I dati restano sul server di sincronizzazione: per riutilizzarli accedi con la master password e la Secret Key dell\'Emergency Kit.';

  @override
  String get vaultSignOutBodyLocal =>
      'Questo vault non è sincronizzato con un server: uscendo tutti gli elementi verranno cancellati definitivamente da questo dispositivo. L\'operazione non è reversibile.';

  @override
  String get vaultSignOutSyncFailed =>
      'L\'ultima sincronizzazione non è riuscita: le modifiche recenti potrebbero non essere sul server e andrebbero perse. Uscire comunque?';

  @override
  String get vaultSignOutConfirm => 'Esci';

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
  String get editorGroupHelper =>
      'Scegline uno esistente o scrivine uno nuovo. Usa / per i sottogruppi, es. Lavoro/Clienti';

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
  String get commonInviteCode => 'Codice invito';

  @override
  String get commonInviteCodeHelper => 'Solo se il tuo server lo richiede';

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
  String get errorInvalidLogin =>
      'Master password o Secret Key errati, oppure sul server non c\'è un account con questa Secret Key.';

  @override
  String get errorAccountExists =>
      'Questo vault ha già un account sul server: sugli altri dispositivi usa \"Ho già un account\".';

  @override
  String get errorInviteRequired =>
      'Questo server accetta nuovi account solo con un codice invito: chiedilo all\'amministratore.';

  @override
  String get errorInvalidInvite =>
      'Codice invito non valido: controlla di averlo scritto bene, potrebbe essere già usato o scaduto.';

  @override
  String get errorRegistrationClosed =>
      'Questo server non accetta nuovi account.';

  @override
  String get errorQuotaExceeded =>
      'Il tuo account ha raggiunto il limite di spazio del server.';

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

  @override
  String get vaultImport => 'Importa…';

  @override
  String get vaultExport => 'Esporta…';

  @override
  String get vaultShowSiteIcons => 'Mostra icone dei siti';

  @override
  String get vaultHideSiteIcons => 'Nascondi icone dei siti';

  @override
  String get vaultGroupPathHint =>
      'Usa / per i sottogruppi, es. Lavoro/Clienti';

  @override
  String get exportTitle => 'Esporta elementi';

  @override
  String get exportFormatBackup => 'Backup cifrato';

  @override
  String get exportFormatCsv => 'CSV in chiaro';

  @override
  String get exportBackupHint =>
      'Il file viene cifrato con questa password: servirà per importare il backup. Contiene tutti gli elementi, note comprese.';

  @override
  String get exportCsvWarning =>
      'Il file CSV non è cifrato: chiunque lo apra legge tutte le password. Eliminalo appena non ti serve più.';

  @override
  String get exportPassword => 'Password del backup';

  @override
  String get exportRepeatPassword => 'Ripeti la password';

  @override
  String get exportAction => 'Esporta';

  @override
  String get exportEmpty => 'Non c\'è nulla da esportare.';

  @override
  String exportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi esportati',
      one: '1 elemento esportato',
    );
    return '$_temp0';
  }

  @override
  String get importTitle => 'Importa elementi';

  @override
  String importFormat(String format) {
    return 'Formato riconosciuto: $format';
  }

  @override
  String get importFormatBackup => 'Backup Arcanum';

  @override
  String importNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi da importare',
      one: '1 elemento da importare',
    );
    return '$_temp0';
  }

  @override
  String importDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sono già nel vault e verranno saltati',
      one: '1 è già nel vault e verrà saltato',
    );
    return '$_temp0';
  }

  @override
  String importSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count non sono importabili (carte, identità o righe vuote)',
      one: '1 non è importabile (carta, identità o riga vuota)',
    );
    return '$_temp0';
  }

  @override
  String get importNothing => 'Non c\'è nulla di nuovo da importare.';

  @override
  String get importAction => 'Importa';

  @override
  String get importOpen => 'Apri';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi importati',
      one: '1 elemento importato',
    );
    return '$_temp0';
  }

  @override
  String get importBackupPasswordBody =>
      'Inserisci la password scelta quando hai esportato questo backup.';

  @override
  String get importWrongPassword => 'Password del backup errata';

  @override
  String get errorUnsupportedFormat =>
      'Il file non è in un formato che Arcanum sa importare.';

  @override
  String get errorBackupPasswordRequired => 'Serve la password del backup.';

  @override
  String errorFile(String details) {
    return 'Impossibile leggere o scrivere il file: $details';
  }

  @override
  String get vaultGroupColor => 'Colore';

  @override
  String vaultGroupColorTitle(String group) {
    return 'Colore di \"$group\"';
  }

  @override
  String get vaultGroupColorNone => 'Nessun colore';

  @override
  String get vaultGroupColorHint =>
      'I sottogruppi senza un colore proprio usano questo.';

  @override
  String get notesEdit => 'Modifica';

  @override
  String get notesPreview => 'Anteprima';

  @override
  String get notesBold => 'Grassetto';

  @override
  String get notesItalic => 'Corsivo';

  @override
  String get notesStrike => 'Barrato';

  @override
  String get notesHeading => 'Titolo';

  @override
  String get notesBulletList => 'Elenco puntato';

  @override
  String get notesNumberedList => 'Elenco numerato';

  @override
  String get notesChecklist => 'Lista di controllo';

  @override
  String get notesQuote => 'Citazione';

  @override
  String get notesCode => 'Codice';

  @override
  String get notesLink => 'Link';

  @override
  String get notesDivider => 'Separatore';

  @override
  String get notesEmptyPreview => 'Niente da mostrare.';

  @override
  String get notesOpenLinkTitle => 'Aprire il link?';

  @override
  String get notesOpen => 'Apri';

  @override
  String get close => 'Chiudi';

  @override
  String get editorKindWifi => 'Wi-Fi';

  @override
  String get editorKindCard => 'Carta';

  @override
  String get wifiSsid => 'Nome rete (SSID)';

  @override
  String get wifiSsidRequired => 'Inserisci il nome della rete.';

  @override
  String get wifiSecurity => 'Sicurezza';

  @override
  String get wifiSecurityWpa => 'WPA/WPA2/WPA3';

  @override
  String get wifiSecurityWep => 'WEP';

  @override
  String get wifiSecurityNone => 'Nessuna (rete aperta)';

  @override
  String get wifiHidden => 'Rete nascosta';

  @override
  String get wifiShowQr => 'Mostra codice QR';

  @override
  String get wifiQrHint =>
      'Inquadralo con la fotocamera dell\'altro telefono per connetterti alla rete.';

  @override
  String wifiQrSemantics(String ssid) {
    return 'Codice QR per connettersi a $ssid';
  }

  @override
  String get cardHolder => 'Intestatario';

  @override
  String get cardNumber => 'Numero carta';

  @override
  String cardNumberValid(String brand) {
    return '$brand · numero valido';
  }

  @override
  String get cardNumberTooShort => 'Il numero è troppo corto.';

  @override
  String cardNumberWrongLength(String brand) {
    return 'Numero di cifre errato per $brand.';
  }

  @override
  String get cardBrandUnknown => 'questa carta';

  @override
  String get cardNumberChecksum => 'Numero non valido: controlla le cifre.';

  @override
  String get cardExpiry => 'Scadenza';

  @override
  String get cardExpiryHint => 'MM/AA';

  @override
  String get cardExpiryInvalid => 'Usa il formato MM/AA.';

  @override
  String get cardExpired => 'Carta scaduta';

  @override
  String get cardCvv => 'CVV';

  @override
  String get cardPin => 'PIN';

  @override
  String get vaultCopyCardNumber => 'Copia numero carta';

  @override
  String get vaultShowWifiQr => 'Mostra QR Wi-Fi';

  @override
  String vaultExpiresOn(String expiry) {
    return 'scad. $expiry';
  }

  @override
  String get browsersTitle => 'Browser collegati';

  @override
  String get browsersIntro =>
      'Collega l\'estensione Arcanum per Chrome, Opera o Safari: compila e salva le password mentre l\'app è sbloccata.';

  @override
  String get browsersConnect => 'Collega browser';

  @override
  String get browsersWaiting =>
      'In attesa del browser… Apri l\'estensione Arcanum e premi Collega entro 2 minuti.';

  @override
  String get browsersNone => 'Nessun browser collegato';

  @override
  String get browsersRevoke => 'Revoca';

  @override
  String browsersConnectedOn(String date) {
    return 'Collegato il $date';
  }

  @override
  String browsersPairTitle(String name) {
    return 'Collegare $name?';
  }

  @override
  String get browsersPairBody =>
      'Digita il codice a 6 cifre mostrato dall\'estensione Arcanum nel browser. Se il browser non mostra un codice, rifiuta.';

  @override
  String get browsersReject => 'Rifiuta';

  @override
  String get browsersApprove => 'Collega';

  @override
  String get browsersPortsBusy =>
      'Impossibile avviare il collegamento con i browser: le porte 47613–47615 sono occupate.';

  @override
  String get browsersWrongCode => 'Codice errato';
}
