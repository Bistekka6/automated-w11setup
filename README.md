# Windows 11 Automated Setup

Script di configurazione post-installazione per PC Windows 11 e Windows 10, progettato per **Tecnodata Trentina Srl**.

## Funzionalità
- Configurazione Risparmio Energia e Timeout Schermo.
- Abilitazione ICMPv4 (Ping) nel Firewall.
- Impostazione informazioni OEM (Produttore, Sito, Telefono).
- Esecuzione di **Win11Debloat** (ottimizzazione sistema e protezione app Microsoft).
- Rimozione automatica di McAfee e WebAdvisor.
- Installazione app tramite **Winget** (Chrome, Office, Acrobat) utilizzando la sorgente `winget` (community) e il parametro `--nowarn` per evitare falsi positivi dovuti ad errori di altre sorgenti (es. `msstore`).
- Rilevamento hardware Dell/Lenovo per installazione utility specifiche.
- Installazione app locali da cartella `installers/`.
- Download e installazione automatica di **WatchGuard Mobile VPN**.
- Configurazione Taskbar.
- Avvio aggiornamenti Windows e controllo BitLocker.

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
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main/setup.ps1))) -DebugMode
```

## Manutenzione
Per aggiungere nuovi file `.msi` o `.exe`, inseriscili nella cartella `installers/` e aggiorna `args.json` se necessario.
