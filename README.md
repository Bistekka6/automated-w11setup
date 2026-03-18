# Windows 11 Automated Setup

Script di configurazione post-installazione per PC Windows 11 e Windows 10, progettato per **Tecnodata Trentina Srl**.

## Funzionalità
- Configurazione Risparmio Energia e Timeout Schermo.
- Abilitazione ICMPv4 (Ping) nel Firewall.
- Impostazione informazioni OEM (Produttore, Sito, Telefono).
- Esecuzione di **Win11Debloat** (ottimizzazione sistema e protezione app Microsoft).
- Rimozione automatica di McAfee e WebAdvisor.
- Installazione app tramite **Winget** (Chrome, Office, Acrobat).
- Rilevamento hardware Dell/Lenovo per installazione utility specifiche.
- Installazione app locali da cartella `installers/`.
- Download e installazione automatica di **WatchGuard Mobile VPN**.
- Configurazione Taskbar.
- Avvio aggiornamenti Windows e controllo BitLocker.

## Esecuzione Rapida
Per avviare lo script su un nuovo PC, apri PowerShell come Amministratore e incolla il seguente comando:

```powershell
iwr https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main/setup.ps1 -useb | iex
```

Questo comando scarica ed esegue l'ultima versione dello script direttamente dal repository.

## Manutenzione
Per aggiungere nuovi file `.msi` o `.exe`, inseriscili nella cartella `installers/` e aggiorna `args.json` se necessario.
