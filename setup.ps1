param(
    [bool]$ConfigureSystem = $false,
    [bool]$RunDebloat = $false,
    [bool]$InstallWingetApps = $false,
    [bool]$InstallLocalApps = $false,
    [bool]$ConfigureTaskbar = $false,
    [bool]$RunWindowsUpdate = $false,
    [bool]$CheckBitlocker = $false,
    [bool]$Unattended = $false,
    [switch]$DebugMode
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
$TranscriptStarted = $false

function Write-SetupLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fffK"
    foreach ($line in ($Message -split "\r?\n")) {
        Add-Content -LiteralPath $script:LogPath -Value "$timestamp [$Level] $line" -Encoding UTF8
    }
}

function Start-SetupProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList,
        [Parameter(Mandatory)][string]$Label
    )

    $processId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP "setup-$processId-stdout.tmp"
    $stderrPath = Join-Path $env:TEMP "setup-$processId-stderr.tmp"
    try {
        Write-SetupLog "Avvio processo ${Label}: $FilePath $ArgumentList"
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { "" }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { "" }
        Write-SetupLog "Processo $Label ($FilePath): PID $($process.Id), codice uscita $($process.ExitCode)"
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-SetupLog "stdout $Label`:`n$stdout" }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-SetupLog "stderr $Label`:`n$stderr" "WARN" }
        foreach ($line in ($stdout -split "\r?\n")) {
            if ($line -match '(?im)(?:disponibile in|available in|available at):\s*[''"](?<path>[^''"]+)[''"]') {
                $installerLogPath = $Matches.path
                if (Test-Path -LiteralPath $installerLogPath) {
                    $installerLog = Get-Content -LiteralPath $installerLogPath -Raw
                    Write-SetupLog "Log dettagliato del programma di installazione ($installerLogPath):`n$installerLog" "WARN"
                }
                else {
                    Write-SetupLog "Log dettagliato del programma di installazione non trovato: $installerLogPath" "WARN"
                }
            }
        }
        return [PSCustomObject]@{
            Id       = $process.Id
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction Stop
            }
        }
    }
}

function Write-SetupErrorDetails {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ([string]::IsNullOrWhiteSpace($script:LogPath)) {
        Write-Host "Dettagli errore: $($ErrorRecord.Exception.ToString())"
        return
    }
    if (-not (Test-Path -LiteralPath $script:LogPath)) {
        Write-Host "Dettagli errore: $($ErrorRecord.Exception.ToString())"
        return
    }

    Write-SetupLog "Eccezione: $($ErrorRecord.Exception.ToString())" "ERROR"
    if ($ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.Line)) {
        Write-SetupLog "Istruzione: $($ErrorRecord.InvocationInfo.Line.Trim())" "ERROR"
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
        Write-SetupLog "Stack: $($ErrorRecord.ScriptStackTrace)" "ERROR"
    }
}

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
                Write-SetupErrorDetails $_
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

    # Salva i dettagli operativi e aggiunge la trascrizione della sessione al termine.
    $LogDir = Join-Path $env:LOCALAPPDATA "WindowsSetup\Logs"
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $LogTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogPath = Join-Path $LogDir "setup-$LogTimestamp-$PID.log"
    $TranscriptPath = Join-Path $LogDir "setup-$LogTimestamp-$PID-transcript.log"
    $RunStartedAt = Get-Date
    Set-Content -LiteralPath $LogPath -Value "Log dettagliato dell'esecuzione Setup" -Encoding UTF8 -ErrorAction Stop
    Write-SetupLog "Avvio: $($RunStartedAt.ToString('o'))"
    Write-SetupLog "Computer: $env:COMPUTERNAME"
    Write-SetupLog "Utente: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-SetupLog "PowerShell: $($PSVersionTable.PSVersion)"
    Write-SetupLog "Sistema operativo: $([Environment]::OSVersion.VersionString)"
    if ($PSCommandPath) {
        Write-SetupLog "Script: $PSCommandPath"
    }
    else {
        Write-SetupLog "Script: esecuzione remota via Invoke-Expression"
    }
    Write-SetupLog "Cartella dello script: $ScriptDir"
    Write-SetupLog "Directory di lavoro: $(Get-Location)"
    Start-Transcript -Path $TranscriptPath -ErrorAction Stop | Out-Null
    $TranscriptStarted = $true
    Write-Host "File di log dell'esecuzione: $LogPath" -ForegroundColor Gray
    Write-SetupLog "Parametri iniziali: ConfigureSystem=$ConfigureSystem; RunDebloat=$RunDebloat; InstallWingetApps=$InstallWingetApps; InstallLocalApps=$InstallLocalApps; ConfigureTaskbar=$ConfigureTaskbar; RunWindowsUpdate=$RunWindowsUpdate; CheckBitlocker=$CheckBitlocker; Unattended=$Unattended; DebugMode=$DebugMode"

    # --- Menu Interattivo ---
    if (-not $Unattended) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "    Setup Post-Installazione Windows 11          " -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        $renamePc = Read-Host "Vuoi rinominare il PC? (Lascia vuoto per saltare, altrimenti scrivi il nuovo nome)"
        if ([string]::IsNullOrWhiteSpace($renamePc) -eq $false) {
            Write-SetupLog "Richiesta rinomina PC: $renamePc"
            Rename-Computer -NewName $renamePc -PassThru
            $SummaryLog += "[-] PC rinominato in: $renamePc (Richiede riavvio)"
            Write-Host "Nome del PC aggiornato. Sarà effettivo al prossimo riavvio.`n" -ForegroundColor Yellow
        }
        else {
            Write-SetupLog "Rinomina PC saltata"
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
            Write-SetupLog "Scelta menu: $scelta"
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

    $SelectedOperations = "ConfigureSystem=$ConfigureSystem; RunDebloat=$RunDebloat; InstallWingetApps=$InstallWingetApps; InstallLocalApps=$InstallLocalApps; ConfigureTaskbar=$ConfigureTaskbar; RunWindowsUpdate=$RunWindowsUpdate; CheckBitlocker=$CheckBitlocker"
    Write-SetupLog "Operazioni selezionate: $SelectedOperations"

    # --- 2. Configurazione Impostazioni di Sistema ---
    if ($ConfigureSystem) {
        try {
            Write-Host "`n[1/4] Configurazione Impostazioni di Sistema..." -ForegroundColor Cyan
            Write-SetupLog "Fase: configurazione impostazioni di sistema"
            
            # Profilo di Risparmio Energia: Bilanciato
            powercfg /SETACTIVE 381b4222-f694-41f0-9685-ff5bb260df2e
            Write-SetupLog "Comando powercfg /SETACTIVE terminato con codice $LASTEXITCODE"
            powercfg /x -standby-timeout-ac 0
            Write-SetupLog "Comando powercfg standby-timeout-ac terminato con codice $LASTEXITCODE"
            powercfg /x -standby-timeout-dc 0
            Write-SetupLog "Comando powercfg standby-timeout-dc terminato con codice $LASTEXITCODE"
            powercfg /x -monitor-timeout-ac 15
            Write-SetupLog "Comando powercfg monitor-timeout-ac terminato con codice $LASTEXITCODE"
            powercfg /x -monitor-timeout-dc 15
            Write-SetupLog "Comando powercfg monitor-timeout-dc terminato con codice $LASTEXITCODE"
            Write-Host " - Risparmio energia e timeout configurati." -ForegroundColor Gray
            
            # Consenti Ping (ICMPv4-In)
            if (-not (Get-NetFirewallRule -DisplayName "Allow ICMPv4-In" -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Enabled True -Profile Any -Action Allow | Out-Null
                Write-SetupLog "Regola firewall Allow ICMPv4-In creata"
            }
            else {
                Write-SetupLog "Regola firewall Allow ICMPv4-In già presente"
            }
            Write-Host " - Firewall (Ping) configurato." -ForegroundColor Gray

            # Informazioni OEM (Tecnodata Trentina Srl)
            $oemKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
            if (-not (Test-Path $oemKey)) { New-Item -Path $oemKey -Force | Out-Null }
            Set-ItemProperty -Path $oemKey -Name "Manufacturer" -Value "Tecnodata Trentina Srl" -Type String -Force
            Set-ItemProperty -Path $oemKey -Name "SupportURL" -Value "https://support.tecnodata.it/" -Type String -Force
            Set-ItemProperty -Path $oemKey -Name "SupportPhone" -Value "04611780400" -Type String -Force
            Write-SetupLog "Informazioni OEM aggiornate nella chiave $oemKey"
            Write-Host " - Informazioni OEM impostate." -ForegroundColor Gray

            # --- Sfondo Aziendale ---
            $LocalBackgroundDir = Join-Path $ScriptDir "background"
            if (-not (Test-Path $LocalBackgroundDir)) { New-Item -ItemType Directory -Path $LocalBackgroundDir | Out-Null }
            $LocalBackgroundPath = Join-Path $LocalBackgroundDir "background.png"
            
            if (-not (Test-Path $LocalBackgroundPath)) {
                if (-not $PSCommandPath) {
                    Write-Host " - Download dello sfondo aziendale..." -ForegroundColor Gray
                    try {
                        Invoke-WebRequest -Uri $RemoteBackgroundUrl -OutFile $LocalBackgroundPath -UseBasicParsing -ErrorAction Stop
                        Write-SetupLog "Sfondo scaricato da $RemoteBackgroundUrl"
                    }
                    catch {
                        Write-Warning " - Download dello sfondo non riuscito: $($_.Exception.Message)"
                        Write-SetupErrorDetails $_
                    }
                }
            }
            
            if (Test-Path $LocalBackgroundPath) {
                Write-SetupLog "Applicazione sfondo da $LocalBackgroundPath"
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
            Write-SetupErrorDetails $_
            $SummaryLog += "[!] Errore configurazione sistema (parziale)"
        }
    }

    # --- 3. Win11Debloat ---
    if ($RunDebloat) {
        Write-Host "`n[2/4] Esecuzione di Win11Debloat..." -ForegroundColor Cyan
        Write-SetupLog "Fase: Win11Debloat"
        try {
            $debloatDir = Join-Path $ScriptDir "Win11Debloat"
            $debloatScriptPath = Join-Path $debloatDir "Win11Debloat.ps1"
            
            if ($DebugMode) {
                Write-Host " [DEBUG] Directory debloat: $debloatDir" -ForegroundColor Gray
                Write-Host " [DEBUG] Script path: $debloatScriptPath" -ForegroundColor Gray
            }

            if (-not (Test-Path $debloatScriptPath)) {
                Write-SetupLog "Win11Debloat non presente; download archivio da $zipUrl"
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
            
            if ($DebugMode) {
                Write-Host " [DEBUG] Esecuzione di Win11Debloat con parametri: -RunDefaults -Silent" -ForegroundColor Yellow
            }

            # Ripristina ErrorActionPreference: Win11Debloat usa reg.exe che scrive sullo stderr 
            # se non trova alcune chiavi, causando il blocco a causa del nostro "Stop" globale.
            $oldErrPref = $global:ErrorActionPreference
            $global:ErrorActionPreference = "Continue"

            & $debloatScriptPath -RunDefaults -Silent
            Write-SetupLog "Win11Debloat terminato"
            
            $global:ErrorActionPreference = $oldErrPref

            Set-Location -Path $currentLoc
            $SummaryLog += "[-] Win11Debloat eseguito con successo"
        }
        catch {
            Write-Warning " - Errore Win11Debloat: $($_.Exception.Message)"
            Write-SetupErrorDetails $_
            if ($currentLoc) { Set-Location -Path $currentLoc }
        }
    }

    # --- Rimozione McAfee ---
    Write-Host "`nRimozione McAfee..." -ForegroundColor Cyan
    $GetMcAfeeUninstallEntries = {
        $uninstallPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        $entries = @()

        foreach ($uninstallPath in $uninstallPaths) {
            if (Test-Path -LiteralPath $uninstallPath) {
                try {
                    foreach ($entryKey in (Get-ChildItem -LiteralPath $uninstallPath -ErrorAction Stop)) {
                        try {
                            $entry = Get-ItemProperty -LiteralPath $entryKey.PSPath -ErrorAction Stop
                            if ($entry.DisplayName -match "(?i)McAfee|WebAdvisor") {
                                $entries += [PSCustomObject]@{
                                    Name                 = $entry.DisplayName
                                    UninstallString      = $entry.UninstallString
                                    QuietUninstallString = $entry.QuietUninstallString
                                    RegistryPath         = $entryKey.PSPath
                                }
                            }
                        }
                        catch {
                            Write-Warning " - Impossibile leggere una voce di disinstallazione in $uninstallPath`: $($_.Exception.Message)"
                            Write-SetupErrorDetails $_
                        }
                    }
                }
                catch {
                    Write-Warning " - Impossibile esaminare $uninstallPath`: $($_.Exception.Message)"
                    Write-SetupErrorDetails $_
                }
            }
        }

        return $entries
    }

    try {
        $mcAfeeEntries = @(& $GetMcAfeeUninstallEntries)
        Write-SetupLog "Prodotti McAfee/WebAdvisor rilevati: $($mcAfeeEntries.Count)"
        if ($mcAfeeEntries.Count -eq 0) {
            Write-Host " - Nessun prodotto McAfee o WebAdvisor rilevato." -ForegroundColor Gray
        }
        else {
            foreach ($app in $mcAfeeEntries) {
                if (-not (Test-Path -LiteralPath $app.RegistryPath)) {
                    continue
                }

                $hasQuietUninstallCommand = -not [string]::IsNullOrWhiteSpace($app.QuietUninstallString)
                $uninstallCommand = $app.QuietUninstallString
                if (-not $hasQuietUninstallCommand) {
                    $uninstallCommand = $app.UninstallString
                }
                if ([string]::IsNullOrWhiteSpace($uninstallCommand)) {
                    Write-Warning " - Nessun comando di disinstallazione registrato per $($app.Name)."
                    Write-SetupLog "Disinstallazione di $($app.Name) saltata: comando di disinstallazione assente" "WARN"
                    continue
                }

                Write-Host " - Disinstallazione di $($app.Name)..." -ForegroundColor Gray
                try {
                    Write-SetupLog "Avvio disinstallazione di $($app.Name)"
                    if ($uninstallCommand -match "(?i)\bmsiexec(?:\.exe)?\b") {
                        if ($uninstallCommand -notmatch "(?i)\{[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\}") {
                            throw "Codice prodotto MSI non trovato nel comando di disinstallazione."
                        }

                        $productCode = $Matches[0]
                        $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                    }
                    else {
                        if ($uninstallCommand -match '^\s*"([^"]+)"\s*(.*)$') {
                            $uninstallerPath = $Matches[1]
                            $uninstallerArguments = if ($Matches[2]) { $Matches[2] } else { "" }
                        }
                        elseif ($uninstallCommand -match '^\s*(.+?\.exe)(?:\s+(.*))?$') {
                            $uninstallerPath = $Matches[1].Trim()
                            $uninstallerArguments = if ($Matches[2]) { $Matches[2] } else { "" }
                        }
                        else {
                            throw "Formato del comando di disinstallazione non riconosciuto: $uninstallCommand"
                        }

                        if (-not (Test-Path -LiteralPath $uninstallerPath)) {
                            throw "Uninstaller non trovato: $uninstallerPath"
                        }

                        $uninstallerArguments = $uninstallerArguments.Trim()
                        $hasSilentSwitch = $uninstallerArguments -match '(?i)(?:^|\s)(?:/|-)(?:s|silent|quiet|qn|verysilent)(?:\s|$)'
                        if (-not $hasQuietUninstallCommand) {
                            if ($app.Name -match "(?i)WebAdvisor" -and -not $hasSilentSwitch) {
                                $uninstallerArguments = "$uninstallerArguments /s".Trim()
                                $hasSilentSwitch = $true
                            }

                            if (-not $hasSilentSwitch) {
                                Write-Warning " - Disinstallazione di $($app.Name) saltata: nessun comando silenzioso riconosciuto; evito di aprire una procedura interattiva."
                                Write-SetupLog "Disinstallazione di $($app.Name) saltata: nessun comando silenzioso riconosciuto" "WARN"
                                continue
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($uninstallerArguments)) {
                            $uninstallProcess = Start-Process -FilePath $uninstallerPath -Wait -PassThru -NoNewWindow -ErrorAction Stop
                        }
                        else {
                            $uninstallProcess = Start-Process -FilePath $uninstallerPath -ArgumentList $uninstallerArguments -Wait -PassThru -NoNewWindow -ErrorAction Stop
                        }
                    }

                    Write-SetupLog "Processo disinstallazione $($app.Name): PID $($uninstallProcess.Id), codice uscita $($uninstallProcess.ExitCode)"
                    if ($uninstallProcess.ExitCode -notin @(0, 1605, 1614, 1641, 3010)) {
                        Write-Warning " - Disinstallazione di $($app.Name) terminata con codice $($uninstallProcess.ExitCode)."
                    }
                }
                catch {
                    Write-Warning " - Errore disinstallazione di $($app.Name): $($_.Exception.Message)"
                    Write-SetupErrorDetails $_
                }
            }

            $remainingMcAfeeEntries = @(& $GetMcAfeeUninstallEntries)
            Write-SetupLog "Componenti McAfee/WebAdvisor residui: $($remainingMcAfeeEntries.Count)"
            if ($remainingMcAfeeEntries.Count -eq 0) {
                Write-Host " - McAfee e WebAdvisor rimossi." -ForegroundColor Green
                $SummaryLog += "[-] McAfee e WebAdvisor rimossi"
            }
            else {
                $remainingNames = ($remainingMcAfeeEntries | ForEach-Object { $_.Name } | Select-Object -Unique) -join ", "
                Write-Warning " - Alcuni componenti McAfee risultano ancora installati: $remainingNames"
                $SummaryLog += "[!] Disinstallazione McAfee incompleta: $remainingNames"
            }
        }
    }
    catch {
        Write-Warning " - Errore durante il rilevamento o la rimozione di McAfee: $($_.Exception.Message)"
        Write-SetupErrorDetails $_
        $SummaryLog += "[!] Errore rimozione McAfee"
    }

    # --- 4. App di Winget ---
    if ($InstallWingetApps) {
        Write-Host "`n[3/4] Installazione Applicazioni Winget..." -ForegroundColor Cyan
        Write-SetupLog "Fase: installazione/verifica applicazioni Winget"
        try {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Write-SetupLog "Winget non trovato; tentativo di installazione del pacchetto App Installer"
                $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                try {
                    Invoke-WebRequest -Uri $wingetUrl -OutFile "$env:TEMP\winget.msixbundle" -UseBasicParsing -ErrorAction Stop
                    Add-AppxPackage -Path "$env:TEMP\winget.msixbundle" -ErrorAction Stop
                    Start-Sleep -Seconds 5
                }
                catch {
                    Write-Warning " - Impossibile installare Winget: $($_.Exception.Message)"
                    Write-SetupErrorDetails $_
                }
            }

            # --- Self-healing per le sorgenti Winget ---
            try {
                Write-Host " - Verifica e aggiornamento sorgenti Winget..." -ForegroundColor Gray
                $sourceUpdateResult = Start-SetupProcess -FilePath "winget" -ArgumentList "source update" -Label "winget source update"
                $sourceUpdateOutput = "$($sourceUpdateResult.StdOut)`r`n$($sourceUpdateResult.StdErr)"
                $sourceUpdateExitCode = $sourceUpdateResult.ExitCode
                Write-SetupLog "winget source update: codice $sourceUpdateExitCode; output: $sourceUpdateOutput"
                if ($sourceUpdateExitCode -ne 0 -or $sourceUpdateOutput -match "0x8a15005e") {
                    Write-Warning " - Rilevato errore sorgenti Winget (es. certificato scaduto o metadati corrotti). Tentativo di ripristino automatico..."
                    $sourceResetResult = Start-SetupProcess -FilePath "winget" -ArgumentList "source reset --force" -Label "winget source reset"
                    $sourceResetOutput = "$($sourceResetResult.StdOut)`r`n$($sourceResetResult.StdErr)"
                    $sourceResetExitCode = $sourceResetResult.ExitCode
                    Write-SetupLog "winget source reset --force: codice $sourceResetExitCode; output: $sourceResetOutput"
                    $sourceRetryResult = Start-SetupProcess -FilePath "winget" -ArgumentList "source update" -Label "winget source update dopo reset"
                    $sourceRetryOutput = "$($sourceRetryResult.StdOut)`r`n$($sourceRetryResult.StdErr)"
                    $sourceRetryExitCode = $sourceRetryResult.ExitCode
                    Write-SetupLog "winget source update dopo reset: codice $sourceRetryExitCode; output: $sourceRetryOutput"
                }
            }
            catch {
                Write-Warning " - Errore aggiornamento sorgenti Winget: $($_.Exception.Message)"
                Write-SetupErrorDetails $_
            }

            $apps = @(
                @{ id = "Google.Chrome"; name = "Chrome" },
                @{ id = "Microsoft.Office"; name = "Office" },
                @{ id = "Microsoft.Teams"; name = "Teams" },
                @{ id = "Adobe.Acrobat.Reader.64-bit"; name = "Acrobat Reader" },
                @{ id = "WatchGuard.MobileVPNWithSSLClient"; name = "WatchGuard Mobile VPN" }
            )

            $manufacturer = (Get-WmiObject Win32_ComputerSystem).Manufacturer
            Write-SetupLog "Produttore rilevato: $manufacturer"
            if ($manufacturer -match "Dell") { $apps += @{ id = "Dell.CommandUpdate"; name = "Dell Command Update" } }
            elseif ($manufacturer -match "Lenovo") { 
                $apps += @{ id = "Lenovo.SystemUpdate"; name = "Lenovo System Update" }
                $apps += @{ id = "Lenovo.Vantage"; name = "Lenovo Vantage" }
            }

            $wingetFailures = @()
            foreach ($app in $apps) {
                $isInstalled = $false
                try {
                    $wingetListResult = Start-SetupProcess -FilePath "winget" -ArgumentList "list --id $($app.id) --exact --source winget" -Label "winget list $($app.id)"
                    $wingetListOutput = "$($wingetListResult.StdOut)`r`n$($wingetListResult.StdErr)"
                    $wingetListExitCode = $wingetListResult.ExitCode
                    Write-SetupLog "winget list --id $($app.id): codice $wingetListExitCode; output: $wingetListOutput"
                    $isInstalled = $wingetListExitCode -eq 0
                }
                catch {
                    Write-Warning " - Impossibile verificare $($app.name) con Winget: $($_.Exception.Message)"
                    Write-SetupErrorDetails $_
                }

                $installSucceeded = $isInstalled
                $appFailureMessages = @()
                if ($isInstalled) {
                    Write-SetupLog "$($app.id) già presente secondo winget list"
                    Write-Host " - $($app.name) già installato. Verifica aggiornamenti..." -ForegroundColor Gray
                }
                else {
                    Write-Host " - Installazione di $($app.name)..." -ForegroundColor Gray
                    try {
                        if ($app.id -eq "Dell.CommandUpdate") {
                            $runtimeId = "Microsoft.DotNet.DesktopRuntime.8"
                            $runtimeListResult = Start-SetupProcess -FilePath "winget" -ArgumentList "list --id $runtimeId --exact --source winget" -Label "winget list $runtimeId"
                            $runtimeListOutput = "$($runtimeListResult.StdOut)`r`n$($runtimeListResult.StdErr)"
                            $runtimeListExitCode = $runtimeListResult.ExitCode
                            Write-SetupLog "Prerequisito ${runtimeId}: winget list codice $runtimeListExitCode; output: $runtimeListOutput"
                            if ($runtimeListExitCode -ne 0) {
                                Write-SetupLog "Installazione preventiva del prerequisito $runtimeId dichiarato da Dell.CommandUpdate"
                                try {
                                    $runtimeProcess = Start-SetupProcess -FilePath "winget" -ArgumentList "install --id $runtimeId --exact --silent --accept-package-agreements --accept-source-agreements --source winget" -Label "winget install $runtimeId"
                                    if ($runtimeProcess.ExitCode -ne 0) {
                                        $appFailureMessages += "$runtimeId non installato (codice $($runtimeProcess.ExitCode))"
                                        Write-Warning " - Installazione del prerequisito $runtimeId non riuscita (codice $($runtimeProcess.ExitCode))."
                                    }
                                }
                                catch {
                                    $appFailureMessages += "${runtimeId}: $($_.Exception.Message)"
                                    Write-Warning " - Errore installazione del prerequisito $runtimeId`: $($_.Exception.Message)"
                                    Write-SetupErrorDetails $_
                                }
                            }
                        }

                        Write-SetupLog "Avvio installazione Winget $($app.id)"
                        $installProcess = Start-SetupProcess -FilePath "winget" -ArgumentList "install --id $($app.id) --silent --accept-package-agreements --accept-source-agreements --source winget" -Label "winget install $($app.id)"
                        $installSucceeded = $installProcess.ExitCode -eq 0
                        if (-not $installSucceeded) {
                            $appFailureMessages += "codice uscita $($installProcess.ExitCode)"
                            Write-Warning " - Installazione Winget di $($app.name) non riuscita (codice $($installProcess.ExitCode))."
                        }
                    }
                    catch {
                        $appFailureMessages += $_.Exception.Message
                        Write-Warning " - Errore installazione Winget di $($app.name): $($_.Exception.Message)"
                        Write-SetupErrorDetails $_
                    }
                }

                if ($app.id -eq "Microsoft.Office" -and -not $isInstalled -and -not $installSucceeded) {
                    Write-Warning " - Avvio installazione di Office tramite setup.exe e file XML..."
                    $officeFallbackDir = Join-Path $env:TEMP "TecnodataOfficeFallback"
                    $officeSetupPath = Join-Path $officeFallbackDir "setup.exe"
                    $officeConfigPath = Join-Path $officeFallbackDir "configuration-Office365-x64.xml"
                    $bundledOfficeDir = Join-Path $ScriptDir "installers\office"
                    $bundledOfficeSetupPath = Join-Path $bundledOfficeDir "setup.exe"
                    $bundledOfficeConfigPath = Join-Path $bundledOfficeDir "configuration-Office365-x64.xml"
                    $officeFallbackSucceeded = $false

                    try {
                        if ((Test-Path $bundledOfficeSetupPath) -and (Test-Path $bundledOfficeConfigPath)) {
                            $officeSetupPath = $bundledOfficeSetupPath
                            $officeConfigPath = $bundledOfficeConfigPath
                            Write-SetupLog "Uso setup Office e configurazione XML locali"
                        }
                        else {
                            Write-SetupLog "File Office locali non disponibili; download da $GitHubRepoUrl"
                            if (-not (Test-Path $officeFallbackDir)) {
                                New-Item -ItemType Directory -Path $officeFallbackDir -Force | Out-Null
                            }

                            Invoke-WebRequest -Uri "$GitHubRepoUrl/installers/office/setup.exe" -OutFile $officeSetupPath -UseBasicParsing -ErrorAction Stop
                            Invoke-WebRequest -Uri "$GitHubRepoUrl/installers/office/configuration-Office365-x64.xml" -OutFile $officeConfigPath -UseBasicParsing -ErrorAction Stop
                        }

                        Write-SetupLog "Avvio fallback Office con setup: $officeSetupPath; configurazione: $officeConfigPath"
                        if ((Get-Item $officeSetupPath).Length -eq 0 -or (Get-Item $officeConfigPath).Length -eq 0) {
                            throw "Il setup.exe o il file XML scaricato è vuoto."
                        }

                        $officeSetupProcess = Start-SetupProcess -FilePath $officeSetupPath -ArgumentList "/configure `"$officeConfigPath`"" -Label "Office setup.exe"
                        if ($officeSetupProcess.ExitCode -ne 0) {
                            throw "setup.exe ha restituito il codice $($officeSetupProcess.ExitCode)."
                        }

                        $officeFallbackSucceeded = $true
                        $installSucceeded = $true
                        Write-Host " - Office installato tramite setup.exe." -ForegroundColor Green
                    }
                    catch {
                        $appFailureMessages += "fallback Office: $($_.Exception.Message)"
                        Write-Warning " - Installazione di Office tramite setup.exe non riuscita: $($_.Exception.Message)"
                        Write-SetupErrorDetails $_
                    }

                    if ($officeFallbackSucceeded) {
                        $SummaryLog += "[-] Office installato tramite setup.exe (fallback dopo errore Winget)"
                    }
                    else {
                        $SummaryLog += "[!] Installazione Office non riuscita né con Winget né con setup.exe"
                    }
                }

                if (-not ($isInstalled -or $installSucceeded)) {
                    if ($appFailureMessages.Count -eq 0) {
                        $appFailureMessages += "installazione non riuscita"
                    }
                    $failureSummary = "$($app.name): $($appFailureMessages -join '; ')"
                    $wingetFailures += $failureSummary
                    Write-SetupLog $failureSummary "WARN"
                }
            }
            if ($wingetFailures.Count -eq 0) {
                $SummaryLog += "[-] Applicazioni Winget verificate"
            }
            else {
                $SummaryLog += "[!] Installazione Winget incompleta: $($wingetFailures -join ', ')"
            }
        }
        catch {
            Write-Warning " - Errore Winget: $($_.Exception.Message)"
            Write-SetupErrorDetails $_
            $SummaryLog += "[!] Errore durante la fase Winget: $($_.Exception.Message)"
        }
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
        Write-SetupLog "Fase: configurazione taskbar"
        
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
            Write-SetupLog "Layout taskbar scritto in $taskbarPath"
            
            # Riavvia explorer per applicare (se possibile)
            Stop-Process -Name explorer -Force
            Write-Host " - Taskbar configurata (si applicherà completamente al prossimo login)"
            $SummaryLog += "[-] Taskbar configurata (Esplora Risorse, Chrome)"
        }
        catch {
            Write-Warning " - Impossibile configurare la Taskbar: $($_.Exception.Message)"
            Write-SetupErrorDetails $_
            $SummaryLog += "[!] Errore Taskbar (saltata)"
        }
    }

    # --- 7. Aggiornamenti Automatici ---
    if ($RunWindowsUpdate) {
        Write-Host "`nAvvio ricerca aggiornamenti Windows e Driver..." -ForegroundColor Cyan
        Write-SetupLog "Fase: avvio scansione Windows Update"
        Write-Host " (Il processo avverrà in background tramite UsoClient)"
        try {
            $updateProcess = Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartInteractiveScan" -NoNewWindow -PassThru
            Write-SetupLog "UsoClient avviato: PID $($updateProcess.Id)"
            Write-Host " - UsoClient avviato: PID $($updateProcess.Id)"
            $SummaryLog += "[-] Ricerca Aggiornamenti Windows e Driver avviata in background"
        }
        catch {
            Write-Warning " - Impossibile avviare UsoClient: $($_.Exception.Message)"
            Write-SetupErrorDetails $_
        }
    }

    # --- 8. Controllo BitLocker ---
    if ($CheckBitlocker) {
        Write-Host "`nControllo stato BitLocker in corso..." -ForegroundColor Cyan
        Write-SetupLog "Fase: controllo BitLocker su $env:SystemDrive"
        try {
            $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            Write-SetupLog "BitLocker VolumeStatus=$($bl.VolumeStatus); ProtectionStatus=$($bl.ProtectionStatus); EncryptionPercentage=$($bl.EncryptionPercentage)"
            if ($bl.VolumeStatus -eq "FullyDecrypted") {
                Write-Host " - BitLocker è DISATTIVATO sul disco principale." -ForegroundColor Yellow
                $SummaryLog += "[-] Stato BitLocker: DISATTIVATO"
            }
            elseif ($bl.VolumeStatus -eq "FullyEncrypted" -and $bl.ProtectionStatus -eq "On") {
                Write-Host " - BitLocker è ATTIVO sul disco principale." -ForegroundColor Green
                $SummaryLog += "[-] Stato BitLocker: ATTIVO"
            }
            elseif ($bl.VolumeStatus -eq "FullyEncrypted" -and $bl.ProtectionStatus -eq "Off") {
                Write-Host " - Il disco è crittografato, ma la protezione BitLocker è disattivata o sospesa." -ForegroundColor Yellow
                $SummaryLog += "[!] Disco crittografato, ma protezione BitLocker disattivata/sospesa"
            }
            elseif ($bl.VolumeStatus -eq "FullyEncrypted") {
                Write-Host " - Il disco è crittografato; stato protezione BitLocker: $($bl.ProtectionStatus)." -ForegroundColor Yellow
                $SummaryLog += "[!] Disco crittografato; stato protezione BitLocker: $($bl.ProtectionStatus)"
            }
            else {
                Write-Host " - Stato BitLocker: $($bl.VolumeStatus)"
                $SummaryLog += "[-] Stato BitLocker: $($bl.VolumeStatus)"
            }
        }
        catch {
            Write-Warning " - Impossibile controllare lo stato di BitLocker (potrebbe non essere supportato): $($_.Exception.Message)"
            Write-SetupErrorDetails $_
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
    
    Write-SetupLog "Riepilogo: $($SummaryLog -join '; ')"
    Write-Host "Configurazione completata!" -ForegroundColor Green

}
catch {
    Write-SetupErrorDetails $_
    Write-Error "Si è verificato un errore durante l'esecuzione dello script: $_"
}
finally {
    try {
        Read-Host "`nPremi Invio per uscire..."
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($LogPath) -and (Test-Path -LiteralPath $LogPath)) {
            $runDuration = (Get-Date) - $RunStartedAt
            Write-SetupLog "Fine esecuzione: $(Get-Date -Format o); durata: $runDuration"
        }
        if ($TranscriptStarted) {
            try {
                Stop-Transcript | Out-Null
            }
            catch {
                Write-Warning "Impossibile chiudere correttamente il file di log: $($_.Exception.Message)"
            }
            try {
                Add-Content -LiteralPath $LogPath -Value "`r`n=== Trascrizione output console ===" -Encoding UTF8 -ErrorAction Stop
                Get-Content -LiteralPath $TranscriptPath -Raw -ErrorAction Stop | Add-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop
                Remove-Item -LiteralPath $TranscriptPath -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Impossibile unire la trascrizione al log dettagliato; la trascrizione è disponibile in $TranscriptPath. Errore: $($_.Exception.Message)"
            }
        }
    }
}