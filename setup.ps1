<#
.SYNOPSIS
Script di configurazione post-installazione per PC Windows.

.DESCRIPTION
Questo script configura le impostazioni di risparmio energia, il firewall, ottimizza Windows 11 (debloat) 
e installa applicazioni standard tramite winget e programmi di installazione locali.

.NOTES
Assicurati che questo script venga eseguito da un'unità portatile, da una condivisione di rete o direttamente via GitHub link.
#>

# Configurazione GitHub (Modifica con i tuoi dati se carichi lo script online)
$GitHubRepoUrl = "https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main"

param(
    [bool]$ConfigureSystem = $false,
    [bool]$RunDebloat = $false,
    [bool]$InstallWingetApps = $false,
    [bool]$InstallLocalApps = $false,
    [bool]$ConfigureTaskbar = $false,
    [bool]$RunWindowsUpdate = $false,
    [bool]$CheckBitlocker = $false,
    [bool]$Unattended = $false
)

$ErrorActionPreference = "Stop"

$SummaryLog = @()

try {
    # --- 1. Verifica Amministratore ---
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Lo script non è in esecuzione come Amministratore. Tentativo di elevazione dei privilegi in corso..."
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }

    # Gestione del percorso dello script (supporta esecuzione remota via Invoke-Expression)
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
    if (-not $ScriptDir) {
        $ScriptDir = Join-Path $env:TEMP "WindowsSetup"
        if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir | Out-Null }
        Write-Host " - Esecuzione remota rilevata. Cartella di lavoro: $ScriptDir" -ForegroundColor Gray
    }

    # --- Menu Interattivo ---
    if (-not $Unattended) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "    Setup Post-Installazione Windows 11          " -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        $renamePc = Read-Host "Vuoi rinominare il PC? (Lascia vuoto per saltare, altrimenti scrivi il nuovo nome)"
        if ([string]::IsNullOrWhiteSpace($renamePc) -eq $false) {
            Rename-Computer -NewName $renamePc -PassThru
            $SummaryLog += "[-] PC rinominato in: $renamePc (Richiede riavvio)"
            Write-Host "Nome del PC aggiornato. Sarà effettivo al prossimo riavvio.`n" -ForegroundColor Yellow
        }

        do {
            Write-Host "`nSeleziona l'operazione da eseguire:"
            Write-Host " 1. Esegui TUTTO (Tutte le operazioni)"
            Write-Host " 2. Solo Configurazione Impostazioni di Sistema (Energia, Firewall)"
            Write-Host " 3. Solo Esecuzione Win11Debloat"
            Write-Host " 4. Solo Installazione App Winget"
            Write-Host " 5. Solo Installazione App Locali (cartella 'installers')"
            Write-Host " 6. Solo Pulizia Taskbar"
            Write-Host " 7. Solo Avvio Aggiornamenti (Windows e Driver)"
            Write-Host " 8. Solo Controllo Stato BitLocker"
            Write-Host " 0. Esci dallo Script"
            
            $scelta = Read-Host "`nInserisci la tua scelta (0-8)"
        } until ($scelta -match '^[0-8]$')

        if ($scelta -eq '0') {
            Write-Host "Uscita dallo script." -ForegroundColor Yellow
            exit
        }

        if ($scelta -eq '1') {
            $ConfigureSystem = $true
            $RunDebloat = $true
            $InstallWingetApps = $true
            $InstallLocalApps = $true
            $ConfigureTaskbar = $true
            $RunWindowsUpdate = $true
            $CheckBitlocker = $true
        }
        else {
            $ConfigureSystem = ($scelta -eq '2')
            $RunDebloat = ($scelta -eq '3')
            $InstallWingetApps = ($scelta -eq '4')
            $InstallLocalApps = ($scelta -eq '5')
            $ConfigureTaskbar = ($scelta -eq '6')
            $RunWindowsUpdate = ($scelta -eq '7')
            $CheckBitlocker = ($scelta -eq '8')
        }
        
        Write-Host "`nInizio operazioni tra 3 secondi..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }

    # --- 2. Impostazioni di Sistema ---
    if ($ConfigureSystem) {
        Write-Host "`n[1/4] Configurazione Impostazioni di Sistema in corso..." -ForegroundColor Cyan
        
        # Profilo di Risparmio Energia: Assicurarsi che Bilanciato sia attivo (GUID: 381b4222-f694-41f0-9685-ff5bb260df2e)
        try {
            powercfg /SETACTIVE 381b4222-f694-41f0-9685-ff5bb260df2e
            Write-Host " - Profilo di risparmio energia impostato su Bilanciato"
        }
        catch {
            Write-Warning " - Impossibile impostare il profilo di risparmio energia Bilanciato."
        }
        
        # Disattiva Sospensione/Standby (0 significa mai)
        powercfg /x -standby-timeout-ac 0
        powercfg /x -standby-timeout-dc 0
        Write-Host " - Sospensione/Standby disabilitati"
        
        # Spegni lo schermo dopo 15 minuti
        powercfg /x -monitor-timeout-ac 15
        powercfg /x -monitor-timeout-dc 15
        Write-Host " - Timeout dello schermo impostato a 15 minuti"
        
        # Richiedi l'accesso al risveglio (blocco console)
        powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
        powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
        
        # Consenti Ping (ICMPv4-In)
        Write-Host " - Abilitazione ICMPv4 (Ping) nel Firewall in corso..."
        $pingRule = Get-NetFirewallRule -DisplayName "Allow ICMPv4-In" -ErrorAction SilentlyContinue
        if (-not $pingRule) {
            New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Enabled True -Profile Any -Action Allow | Out-Null
        }
        else {
            Set-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Enabled True | Out-Null
        }
        
        # --- Informazioni OEM ---
        Write-Host " - Impostazione informazioni OEM (Tecnodata Trentina Srl)..."
        try {
            $oemKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
            if (-not (Test-Path $oemKey)) {
                New-Item -Path $oemKey -Force | Out-Null
            }
            Set-ItemProperty -Path $oemKey -Name "Manufacturer" -Value "Tecnodata Trentina Srl" -Type String -Force
            Set-ItemProperty -Path $oemKey -Name "SupportURL" -Value "https://support.tecnodata.it/" -Type String -Force
            Set-ItemProperty -Path $oemKey -Name "SupportPhone" -Value "04611780400" -Type String -Force
            $SummaryLog += "[-] Impostazioni di Sistema (Energia/Ping/OEM) configurate"
        } catch {
            Write-Warning " - Impossibile configurare le informazioni OEM: $($_.Exception.Message)"
            $SummaryLog += "[!] Errore configurazione OEM (saltata)"
        }
    }

    # --- 3. Win11Debloat ---
    if ($RunDebloat) {
        Write-Host "`n[2/4] Esecuzione di Win11Debloat in corso..." -ForegroundColor Cyan
        
        $debloatDir = Join-Path $ScriptDir "Win11Debloat"
        $debloatScriptPath = Join-Path $debloatDir "Win11Debloat.ps1"
        $zipPath = Join-Path $ScriptDir "Win11Debloat.zip"
        
        if (-not (Test-Path $debloatScriptPath)) {
            try {
                Write-Host " - Tentativo di download dell'ultima versione completa di Win11Debloat da GitHub (ZIP) in corso..."
                $zipUrl = "https://github.com/Raphire/Win11Debloat/archive/refs/heads/master.zip"
                Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
                
                Write-Host " - Estrazione dei file in corso..."
                Expand-Archive -Path $zipPath -DestinationPath $ScriptDir -Force
                
                $extractedDir = Join-Path $ScriptDir "Win11Debloat-master"
                if (Test-Path $extractedDir) {
                    Rename-Item -Path $extractedDir -NewName "Win11Debloat" -Force
                }
                
                Remove-Item -Path $zipPath -Force
                
                # Rimuove il vecchio script isolato, se presente
                $oldScript = Join-Path $ScriptDir "Win11Debloat.ps1"
                if (Test-Path $oldScript) { Remove-Item -Path $oldScript -Force }
                
                Write-Host " - Win11Debloat scaricato ed estratto con successo."
            }
            catch {
                Write-Host " - Impossibile scaricare Win11Debloat. Controllo della copia offline..." -ForegroundColor Yellow
            }
        }
        
        try {
            if (Test-Path $debloatScriptPath) {
                Write-Host " - Modifica di Apps.json per mantenere le app Microsoft..."
                $appsJsonPath = Join-Path $debloatDir "Config\Apps.json"
                if (Test-Path $appsJsonPath) {
                    $appsConfig = Get-Content $appsJsonPath -Raw | ConvertFrom-Json
                    foreach ($app in $appsConfig.Apps) {
                        if ($app.AppId -match '^Microsoft|^Windows|^Xbox|Teams|Cortana') {
                            $app.SelectedByDefault = $false
                        }
                    }
                    $appsConfig | ConvertTo-Json -Depth 10 | Set-Content $appsJsonPath
                }

                Write-Host " - Esecuzione di Win11Debloat in modalità silenziosa..."
                $currentLoc = Get-Location
                Set-Location -Path $debloatDir
                
                # -Silent prevents the "Press Enter to continue" prompt
                # -RunDefaults runs the default system optimizations
                & $debloatScriptPath -Silent -RunDefaults
                
                Set-Location -Path $currentLoc
                $SummaryLog += "[-] Win11Debloat eseguito (App non-MS rimosse, Ottimizzazioni attive)"
            }
            else {
                Write-Warning " - Lo script Win11Debloat non è stato trovato. Salto l'operazione."
            }
        } catch {
            Write-Warning " - Errore durante l'esecuzione di Win11Debloat: $($_.Exception.Message)"
            $SummaryLog += "[!] Win11Debloat fallito (saltato)"
            if ($currentLoc) { Set-Location -Path $currentLoc }
        }
    }

    # --- McAfee Removal ---
    Write-Host "`nRimozione predefinita McAfee e WebAdvisor in corso..." -ForegroundColor Cyan
    $mcafeeApps = @("McAfee*", "*WebAdvisor*")
    $foundMcAfee = $false

    foreach ($appGlob in $mcafeeApps) {
        $apps = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like $appGlob }
        if ($apps) {
            $foundMcAfee = $true
            foreach ($app in $apps) {
                Write-Host " - Disinstallazione di $($app.Name)..."
                $app.Uninstall() | Out-Null
            }
        }
    }
    
    if ($foundMcAfee) {
        Write-Host " - McAfee disinstallato con successo."
        $SummaryLog += "[-] McAfee e WebAdvisor disinstallati"
    }
    else {
        Write-Host " - Nessuna installazione di McAfee trovata."
    }

    # --- 4. App di Winget ---
    if ($InstallWingetApps) {
        Write-Host "`nInstallazione applicazioni tramite Winget in corso..." -ForegroundColor Cyan
        
        try {
            # Verifica presenza Winget (necessario su Windows 10)
            if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
                Write-Host " - Winget non trovato. Tentativo di installazione in corso..." -ForegroundColor Yellow
                
                $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                $wingetPath = Join-Path $env:TEMP "winget.msixbundle"
                
                Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath -UseBasicParsing
                Add-AppxPackage -Path $wingetPath
                
                # Attesa breve per registrazione comando
                Start-Sleep -Seconds 5
                
                if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
                    throw "Installazione Winget fallita. Procedere manualmente."
                }
                Write-Host " - Winget installato con successo."
            }

            $apps = @(
                "Google.Chrome",
                "Microsoft.Office",
                "Adobe.Acrobat.Reader.64-bit"
            )
            
            # Controllo produttore per software specifici
            $pcInfo = Get-WmiObject -Class Win32_ComputerSystem
            if ($pcInfo.Manufacturer -match "Dell") {
                Write-Host " - PC Dell rilevato. Aggiunta software specifico (Dell Command | Update)..."
                $apps += "Dell.CommandUpdate"
            }
            elseif ($pcInfo.Manufacturer -match "Lenovo") {
                Write-Host " - PC Lenovo rilevato. Aggiunta software specifico (Lenovo System Update e Vantage)..."
                $apps += "Lenovo.SystemUpdate"
                $apps += "Lenovo.Vantage"
            }

            foreach ($app in $apps) {
                Write-Host " - Installazione di $app in corso..."
                try {
                    # Esegue l'installazione invisibile accettando gli accordi
                    $installArgs = "install --id $app --accept-package-agreements --accept-source-agreements --silent --force --source winget"
                    Start-Process -FilePath "winget" -ArgumentList $installArgs -Wait -NoNewWindow
                } catch {
                    Write-Warning " - Errore durante l'installazione di ${app}: $($_.Exception.Message)"
                }
            }
            $SummaryLog += "[-] Eseguita installazione App via Winget"
        } catch {
            Write-Warning " - Errore critico in sezione Winget: $($_.Exception.Message)"
            $SummaryLog += "[!] Winget fallito o non disponibile (saltato)"
        }
    }

    # --- 5. App Locali e Speciali ---
    if ($InstallLocalApps) {
        Write-Host "`n[4/4] Installazione applicazioni locali/speciali in corso..." -ForegroundColor Cyan
        $installersDir = Join-Path $ScriptDir "installers"
        $configPath = Join-Path $installersDir "args.json"
        
        # Crea cartella installers se mancante (caso esecuzione remota)
        if (-not (Test-Path $installersDir)) { New-Item -ItemType Directory -Path $installersDir | Out-Null }

        # --- Download WatchGuard VPN (Sempre da Internet) ---
        try {
            Write-Host " - Download WatchGuard Mobile VPN with SSL in corso..."
            $wgUrl = "https://cdn.watchguard.com/SoftwareCenter/Files/MUVPN_SSL/2026_1/WG-MVPN-SSL_2026_1.exe"
            $wgPath = Join-Path $installersDir "WG-MVPN-SSL_2026_1.exe"
            if (-not (Test-Path $wgPath)) {
                Invoke-WebRequest -Uri $wgUrl -OutFile $wgPath -UseBasicParsing
            }
            Write-Host " - Installazione WatchGuard in corso..."
            Start-Process -FilePath $wgPath -ArgumentList "/S /v/qn" -Wait -NoNewWindow
            $SummaryLog += "[-] WatchGuard VPN installato"
        } catch {
            Write-Warning " - Impossibile installare WatchGuard: $($_.Exception.Message)"
        }

        # Caricamento argomenti da args.json (anche remoto)
        if (-not (Test-Path $configPath) -and $GitHubRepoUrl -ne "https://raw.githubusercontent.com/YourUsername/YourRepo/main") {
            try {
                Write-Host " - Download args.json da GitHub..."
                Invoke-WebRequest -Uri "$GitHubRepoUrl/installers/args.json" -OutFile $configPath -UseBasicParsing
            } catch { }
        }

        $customArgs = @{}
        if (Test-Path $configPath) {
            Write-Host " - Caricamento configurazioni argomenti personalizzati da args.json..."
            try {
                $jsonConfig = Get-Content $configPath -Raw | ConvertFrom-Json
                $jsonConfig.psobject.properties | ForEach-Object {
                    $customArgs[$_.Name] = $_.Value
                }
            }
            catch {
                Write-Warning " - Impossibile leggere o analizzare args.json. Verranno usati i paramteri predefiniti."
            }
        }
        
        if (Test-Path $installersDir) {
            $msis = Get-ChildItem -Path $installersDir -Filter "*.msi"
            $executables = Get-ChildItem -Path $installersDir -Filter "*.exe"
            
            foreach ($msi in $msis) {
                Write-Host " - Installazione MSI: $($msi.Name) in corso..."
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($msi.FullName)`" /qn /norestart" -Wait -NoNewWindow
            }
            
            foreach ($exe in $executables) {
                Write-Host " - Installazione EXE: $($exe.Name) in corso..."
                
                # Gestione specifica degli argomenti tramite file di configurazione
                if ($customArgs.ContainsKey($exe.Name)) {
                    $exeArgs = $customArgs[$exe.Name]
                }
                else {
                    # Argomenti invisibili comuni per EXE generici
                    $exeArgs = "/S /quiet /qn"
                }

                Start-Process -FilePath $exe.FullName -ArgumentList $exeArgs -Wait -NoNewWindow
            }
            $SummaryLog += "[-] Eseguita installazione App locali (cartella installers)"
        }
        else {
            Write-Host " - Nessuna directory 'installers' trovata. Salto le app locali."
        }
    }

    # --- 6. Taskbar ---
    if ($ConfigureTaskbar) {
        Write-Host "`nConfigurazione Taskbar in corso..." -ForegroundColor Cyan
        
        try {
            # Metodo per Windows 11: si basa su LayoutModification.json nel profilo utente
            $jsonConfig = @'
{
    "pinnedList": [
        { "desktopAppId": "Microsoft.Windows.Explorer" },
        { "desktopAppId": "Chrome" }
    ]
}
'@
            $taskbarPath = "$env:LOCALAPPDATA\Microsoft\Windows\Shell\LayoutModification.json"
            
            # Non eliminiamo la chiave registry HKCU per intero, è troppo distruttivo.
            # Rimuoviamo solo i 'Favorites' se vogliamo forzare il reset, ma è rischioso su alcune build.
            # Proviamo solo a scrivere il file JSON e riavviare Explorer.
            
            $jsonConfig | Out-File -FilePath $taskbarPath -Encoding utf8 -Force
            
            # Riavvia explorer per applicare (se possibile)
            Stop-Process -Name explorer -Force
            Write-Host " - Taskbar configurata (si applicherà completamente al prossimo login)"
            $SummaryLog += "[-] Taskbar configurata (Esplora Risorse, Chrome)"
        } catch {
            Write-Warning " - Impossibile configurare la Taskbar: $($_.Exception.Message)"
            $SummaryLog += "[!] Errore Taskbar (saltata)"
        }
    }

    # --- 7. Aggiornamenti Automatici ---
    if ($RunWindowsUpdate) {
        Write-Host "`nAvvio ricerca aggiornamenti Windows e Driver..." -ForegroundColor Cyan
        Write-Host " (Il processo avverrà in background tramite UsoClient)"
        try {
            Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartInteractiveScan" -NoNewWindow
            $SummaryLog += "[-] Ricerca Aggiornamenti Windows e Driver avviata in background"
        }
        catch {
            Write-Warning " - Impossibile avviare UsoClient."
        }
    }

    # --- 8. Controllo BitLocker ---
    if ($CheckBitlocker) {
        Write-Host "`nControllo stato BitLocker in corso..." -ForegroundColor Cyan
        try {
            $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            if ($bl.VolumeStatus -eq "FullyDecrypted") {
                Write-Host " - BitLocker è DISATTIVATO sul disco principale." -ForegroundColor Yellow
                $SummaryLog += "[-] Stato BitLocker: DISATTIVATO"
            }
            elseif ($bl.VolumeStatus -eq "FullyEncrypted") {
                Write-Host " - BitLocker è ATTIVO sul disco principale." -ForegroundColor Green
                $SummaryLog += "[-] Stato BitLocker: ATTIVO"
            }
            else {
                Write-Host " - Stato BitLocker: $($bl.VolumeStatus)"
                $SummaryLog += "[-] Stato BitLocker: $($bl.VolumeStatus)"
            }
        }
        catch {
            Write-Warning " - Impossibile controllare lo stato di BitLocker (potrebbe non essere supportato)."
            $SummaryLog += "[-] Stato BitLocker: Non verificabile / Non supportato"
        }
    }

    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "    Riepilogo Operazioni Effettuate              " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    if ($SummaryLog.Count -gt 0) {
        foreach ($log in $SummaryLog) {
            Write-Host " $log" -ForegroundColor White
        }
    }
    else {
        Write-Host " Nessuna operazione eseguita." -ForegroundColor Gray
    }
    Write-Host "=================================================`n" -ForegroundColor Cyan
    
    Write-Host "Configurazione completata!" -ForegroundColor Green

}
catch {
    Write-Error "Si è verificato un errore durante l'esecuzione dello script: $_"
}
finally {
    Read-Host "`nPremi Invio per uscire..."
}