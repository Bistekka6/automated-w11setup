param(
    [bool]$ConfigureSystem = $false,
    [bool]$RunDebloat = $false,
    [bool]$InstallWingetApps = $false,
    [bool]$InstallLocalApps = $false,
    [bool]$ConfigureTaskbar = $false,
    [bool]$RunWindowsUpdate = $false,
    [bool]$CheckBitlocker = $false,
    [bool]$Unattended = $false,
    [bool]$DebugMode = $false
)

<#
.SYNOPSIS
Script di configurazione post-installazione per PC Windows.
#>

# Configurazione GitHub
$GitHubRepoUrl = "https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main"
$RemoteBackgroundUrl = "$GitHubRepoUrl/background/background.png"

# Configurazione Protocolli di Sicurezza (TLS 1.2)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Forza la Execution Policy per la sessione corrente (Processo)
# Questo risolve l'errore "script non abilitati" senza cambiare le impostazioni di sistema permanenti.
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$ErrorActionPreference = "Stop"
$SummaryLog = @()

try {
    # --- 1. Verifica Amministratore ---
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Lo script non è in esecuzione come Amministratore. Tentativo di elevazione dei privilegi in corso..."
        
        # Definiamo la sorgente remota per l'elevazione
        $remoteUrl = "https://raw.githubusercontent.com/Bistekka6/automated-w11setup/main/setup.ps1"

        if ($PSCommandPath) {
            # Esecuzione locale
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        }
        else {
            # Esecuzione remota (via iex): scarichiamo un file temporaneo per elevare reliably
            $tempScript = Join-Path $env:TEMP "setup_elevated.ps1"
            try {
                Invoke-WebRequest -Uri $remoteUrl -OutFile $tempScript -UseBasicParsing -ErrorAction Stop
                Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs
            }
            catch {
                Write-Error "Impossibile scaricare lo script per l'elevazione: $($_.Exception.Message)"
                Read-Host "Premi Invio per uscire..."
            }
        }
        exit
    }

    # Gestione del percorso dello script (supporta esecuzione remota via Invoke-Expression)
    if ($PSCommandPath) {
        $ScriptDir = Split-Path -Parent $PSCommandPath
    }
    else {
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

    # --- 2. Configurazione Impostazioni di Sistema ---
    if ($ConfigureSystem) {
        try {
            Write-Host "`n[1/4] Configurazione Impostazioni di Sistema..." -ForegroundColor Cyan
            
            # Profilo di Risparmio Energia: Bilanciato
            powercfg /SETACTIVE 381b4222-f694-41f0-9685-ff5bb260df2e
            powercfg /x -standby-timeout-ac 0
            powercfg /x -standby-timeout-dc 0
            powercfg /x -monitor-timeout-ac 15
            powercfg /x -monitor-timeout-dc 15
            Write-Host " - Risparmio energia e timeout configurati." -ForegroundColor Gray
            
            # Consenti Ping (ICMPv4-In)
            if (-not (Get-NetFirewallRule -DisplayName "Allow ICMPv4-In" -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Enabled True -Profile Any -Action Allow | Out-Null
            }
            Write-Host " - Firewall (Ping) configurato." -ForegroundColor Gray

            # Informazioni OEM (Tecnodata Trentina Srl)
            $oemKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
            if (-not (Test-Path $oemKey)) { New-Item -Path $oemKey -Force | Out-Null }
            Set-ItemProperty -Path $oemKey -Name "Manufacturer" -Value "Tecnodata Trentina Srl" -Type String -Force
            Set-ItemProperty -Path $oemKey -Name "SupportURL" -Value "https://support.tecnodata.it/" -Type String -Force
            Set-ItemProperty -Path $oemKey -Name "SupportPhone" -Value "04611780400" -Type String -Force
            Write-Host " - Informazioni OEM impostate." -ForegroundColor Gray

            # --- Sfondo Aziendale ---
            $LocalBackgroundDir = Join-Path $ScriptDir "background"
            if (-not (Test-Path $LocalBackgroundDir)) { New-Item -ItemType Directory -Path $LocalBackgroundDir | Out-Null }
            $LocalBackgroundPath = Join-Path $LocalBackgroundDir "background.png"
            
            if (-not (Test-Path $LocalBackgroundPath)) {
                if (-not $PSCommandPath) {
                    Write-Host " - Download dello sfondo aziendale..." -ForegroundColor Gray
                    Invoke-WebRequest -Uri $RemoteBackgroundUrl -OutFile $LocalBackgroundPath -UseBasicParsing -ErrorAction SilentlyContinue
                }
            }
            
            if (Test-Path $LocalBackgroundPath) {
                Write-Host " - Applicazione dello sfondo desktop..." -ForegroundColor Gray
                $code = @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    public const int SPI_SETDESKWALLPAPER = 20;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDWININICHANGE = 0x02;
    public static void Set(string path) {
        SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE);
    }
}
"@
                Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
                Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $LocalBackgroundPath
                [Wallpaper]::Set($LocalBackgroundPath)
            }
            $SummaryLog += "[-] Impostazioni di Sistema e Sfondo configurati"
        }
        catch {
            Write-Warning " - Errore durante la configurazione di sistema: $($_.Exception.Message)"
            $SummaryLog += "[!] Errore configurazione sistema (parziale)"
        }
    }

    # --- 3. Win11Debloat ---
    if ($RunDebloat) {
        Write-Host "`n[2/4] Esecuzione di Win11Debloat..." -ForegroundColor Cyan
        try {
            $debloatDir = Join-Path $ScriptDir "Win11Debloat"
            $debloatScriptPath = Join-Path $debloatDir "Win11Debloat.ps1"
            
            if ($DebugMode) {
                Write-Host " [DEBUG] Directory debloat: $debloatDir" -ForegroundColor Gray
                Write-Host " [DEBUG] Script path: $debloatScriptPath" -ForegroundColor Gray
            }

            if (-not (Test-Path $debloatScriptPath)) {
                Write-Host " - Download di Win11Debloat in corso..." -ForegroundColor Gray
                $zipUrl = "https://github.com/Raphire/Win11Debloat/archive/refs/heads/master.zip"
                $zipPath = Join-Path $ScriptDir "Win11Debloat.zip"
                Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
                
                Write-Host " - Estrazione file..." -ForegroundColor Gray
                Expand-Archive -Path $zipPath -DestinationPath $ScriptDir -Force
                Rename-Item -Path (Join-Path $ScriptDir "Win11Debloat-master") -NewName "Win11Debloat" -Force
                Remove-Item -Path $zipPath -Force
                
                if (-not (Test-Path $debloatScriptPath)) {
                    throw "Errore: Lo script $debloatScriptPath non è stato trovato dopo l'estrazione."
                }
            }

            $currentLoc = Get-Location
            Set-Location -Path $debloatDir
            
            # Sblocca i file scaricati di Win11Debloat per evitare errori di sicurezza
            Write-Host " - Sbloccaggio file di Win11Debloat..." -ForegroundColor Gray
            Get-ChildItem -Path $debloatDir -Recurse | Unblock-File -ErrorAction SilentlyContinue
            
            $debloatArgs = @("-RunDefaults")
            if ($DebugMode) {
                Write-Host " [DEBUG] Esecuzione di Win11Debloat in modalità DEBUG (senza -Silent)..." -ForegroundColor Yellow
            }
            else {
                $debloatArgs += "-Silent"
            }

            & $debloatScriptPath @debloatArgs
            
            Set-Location -Path $currentLoc
            $SummaryLog += "[-] Win11Debloat eseguito con successo"
        }
        catch {
            Write-Warning " - Errore Win11Debloat: $($_.Exception.Message)"
            if ($currentLoc) { Set-Location -Path $currentLoc }
        }
    }

    # --- Rimozione McAfee ---
    Write-Host "`nRimozione McAfee..." -ForegroundColor Cyan
    try {
        $mc = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "McAfee*" -or $_.Name -like "*WebAdvisor*" }
        if ($mc) {
            foreach ($app in $mc) { $app.Uninstall() | Out-Null }
            $SummaryLog += "[-] McAfee rimosso"
        }
    }
    catch { Write-Warning " - Errore rimozione McAfee" }

    # --- 4. App di Winget ---
    if ($InstallWingetApps) {
        Write-Host "`n[3/4] Installazione Applicazioni Winget..." -ForegroundColor Cyan
        try {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                Invoke-WebRequest -Uri $wingetUrl -OutFile "$env:TEMP\winget.msixbundle" -UseBasicParsing
                Add-AppxPackage -Path "$env:TEMP\winget.msixbundle"
                Start-Sleep -Seconds 5
            }

            # --- Self-healing per le sorgenti Winget ---
            Write-Host " - Verifica e aggiornamento sorgenti Winget..." -ForegroundColor Gray
            $sourceUpdateOutput = winget source update 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $sourceUpdateOutput -match "0x8a15005e") {
                Write-Warning " - Rilevato errore sorgenti Winget (es. certificato scaduto o metadati corrotti). Tentativo di ripristino automatico..."
                winget source reset --force | Out-Null
                winget source update | Out-Null
            }

            $apps = @(
                @{ id = "Google.Chrome"; name = "Chrome" },
                @{ id = "Microsoft.Office"; name = "Office" },
                @{ id = "Adobe.Acrobat.Reader.64-bit"; name = "Acrobat Reader" },
                @{ id = "WatchGuard.MobileVPNWithSSLClient"; name = "WatchGuard Mobile VPN" }
            )

            $manufacturer = (Get-WmiObject Win32_ComputerSystem).Manufacturer
            if ($manufacturer -match "Dell") { $apps += @{ id = "Dell.CommandUpdate"; name = "Dell Command Update" } }
            elseif ($manufacturer -match "Lenovo") { 
                $apps += @{ id = "Lenovo.SystemUpdate"; name = "Lenovo System Update" }
                $apps += @{ id = "Lenovo.Vantage"; name = "Lenovo Vantage" }
            }

            foreach ($app in $apps) {
                # Usa il codice di uscita per verificare l'installazione (0 = installato, altro = non trovato)
                $null = winget list --id $($app.id) --exact --source winget 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host " - $($app.name) già installato. Verifica aggiornamenti..." -ForegroundColor Gray
                }
                else {
                    Write-Host " - Installazione di $($app.name)..." -ForegroundColor Gray
                    Start-Process winget -ArgumentList "install --id $($app.id) --silent --accept-package-agreements --accept-source-agreements --source winget" -Wait -NoNewWindow
                }
            }
            $SummaryLog += "[-] Applicazioni Winget verificate"
        }
        catch { Write-Warning " - Errore Winget" }
    }

    # --- 5. App Locali e Speciali ---
    if ($InstallLocalApps) {
        Write-Host "`n[4/4] Installazione applicazioni locali/speciali (TEMPORANEAMENTE DISABILITATA)" -ForegroundColor Yellow
        <#
        $installersDir = Join-Path $ScriptDir "installers"
        $configPath = Join-Path $installersDir "args.json"
        
        # Crea cartella installers se mancante (caso esecuzione remota)
        if (-not (Test-Path $installersDir)) { New-Item -ItemType Directory -Path $installersDir | Out-Null }


        # Caricamento argomenti da args.json (anche remoto)
        if (-not (Test-Path $configPath) -and $GitHubRepoUrl -ne "https://raw.githubusercontent.com/YourUsername/YourRepo/main") {
            try {
                Write-Host " - Download args.json da GitHub..."
                Invoke-WebRequest -Uri "$GitHubRepoUrl/installers/args.json" -OutFile $configPath -UseBasicParsing
            }
            catch { }
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
                
                # Cerca argomenti corrispondenti (supporta wildcard nei nomi file in args.json)
                $exeArgs = "/S /quiet /qn" # Default
                foreach ($pattern in $customArgs.Keys) {
                    if ($exe.Name -like $pattern) {
                        $exeArgs = $customArgs[$pattern]
                        break
                    }
                }

                Start-Process -FilePath $exe.FullName -ArgumentList $exeArgs -Wait -NoNewWindow
            }
            $SummaryLog += "[-] Eseguita installazione App locali (cartella installers)"
        }
        else {
            Write-Host " - Nessuna directory 'installers' trovata. Salto le app locali."
        }
        #>
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
        }
        catch {
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