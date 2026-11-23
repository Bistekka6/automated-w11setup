# Windows 11 Automated Setup

Script di configurazione post-installazione per PC Windows 11 e Windows 10, progettato per **Tecnodata Trentina Srl**.

## Funzionalità
- Configurazione Risparmio Energia e Timeout Schermo.
- Abilitazione ICMPv4 (Ping) nel Firewall.
- Impostazione informazioni OEM (Produttore, Sito, Telefono).
- Esecuzione di **Win11Debloat** (ottimizzazione sistema e protezione app Microsoft).
- Rimozione di McAfee e WebAdvisor tramite i comandi registrati in Windows: usa la modalità silenziosa se disponibile, altrimenti avvia la procedura interattiva e attende la conclusione. Verifica poi i componenti residui.
- Installazione app tramite **Winget** (Chrome, Microsoft 365 Apps, Teams, Acrobat) utilizzando la sorgente `winget` (community). Microsoft 365 Apps include Outlook classico; Teams viene installato separatamente tramite Winget. Se l'installazione di Office tramite Winget fallisce, lo script usa `setup.exe` e la configurazione XML inclusi in `installers/office/` e riprova tramite Office Deployment Tool. In esecuzione remota, scarica i file da questo repository.
- Rilevamento hardware Dell/Lenovo per installazione utility specifiche.
- Installazione delle dipendenze Winget richieste da Dell Command Update e riepilogo esplicito delle app non installate.
- Installazione app locali da cartella `installers/`.
- Download e installazione automatica di **WatchGuard Mobile VPN**.
- Configurazione Taskbar.
- Avvio aggiornamenti Windows e controllo BitLocker, distinguendo il disco crittografato dalla protezione attiva.
- Registrazione dettagliata in `%LOCALAPPDATA%\WindowsSetup\Logs\setup-<data>-<processo>.log`: include diagnostica dell'ambiente, operazioni e verifiche effettuate, output standard/errore e codici di uscita dei processi Winget e Office, dettagli completi degli errori, oltre alla trascrizione della sessione. Il log viene arricchito con informazioni operative non mostrate a video e il suo percorso viene indicato all'avvio.

## Esecuzione Rapida
Per avviare lo script su un nuovo PC, apri PowerShell come Amministratore e scegli una delle seguenti modalità:

### 1. Modalità Standard (Consigliata)
Esegue lo script normalmente con menu interattivo:
```powershell
irm https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main/setup.ps1 | iex
```

### 2. Modalità Debug
Esegue lo script mostrando l'output dettagliato di tutti i componenti (incluso Win11Debloat):
```powershell
$s=irm https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main/setup.ps1; & ([scriptblock]::Create($s)) -DebugMode
```

## Manutenzione
Per aggiungere nuovi file `.msi` o `.exe`, inseriscili nella cartella `installers/` e aggiorna `args.json` se necessario.
