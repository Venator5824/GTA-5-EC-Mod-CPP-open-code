# Enhanced Conversations Mod - Downloader (v3.6 - Final Logic Fix)
# THIS SCRIPT MUST BE LOCATED IN THE GTA V ROOT DIRECTORY!

$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "Gray"
Clear-Host

# --- FIX: Lade notwendige .NET Assemblies für Web-Requests ---
try {
    Add-Type -AssemblyName System.Net.Http
} catch {
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Net.Http")
}

# --- 0. CONFIGURATION (URLs) ---
$CONFIG_REPO_URL = "https://raw.githubusercontent.com/Venator5824/GTA-5-Enhanced-Conversation-Mod-Configs/main"
$Phi3Url = "https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf"
$Phi3TargetName = "Phi3.gguf"
$WhisperUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
$WhisperTargetName = "ggml-base.en.bin"
$IniSettingsPath = "GTA_LLM_Settings.ini"
$ModAsiName = "GTA_LLM_01.asi" 
$TargetDir = $PSScriptRoot

# --- 1. INI MANIPULATION HELPER FUNCTION ---
function Set-IniValue {
    param([string]$FilePath, [string]$Section, [string]$Key, [string]$Value)
    (Get-Content -Path $FilePath) | ForEach-Object {
        if ($_ -match "^\s*$Key\s*=\s*.*") { "$_" -replace "^\s*$Key\s*=\s*.*", "$Key = $Value" } else { $_ }
    } | Set-Content $FilePath
}

# --- 2. TRUE STREAMING DOWNLOAD FUNCTION ---
function Try-Download {
    param([string]$Url, [string]$FileName, [string]$Description)

    $FilePath = Join-Path $TargetDir $FileName
    if (Test-Path $FilePath) {
        Write-Host "[EXISTS] $Description ($FileName) is already present. Skipping." -ForegroundColor Green
        return $true
    }

    Write-Host "[DOWNLOAD] Starting $Description..." -ForegroundColor Yellow
    Write-Host "           Source: $Url" -ForegroundColor DarkGray

    try {
        $HttpClient = New-Object System.Net.Http.HttpClient
        $HttpClient.Timeout = [TimeSpan]::FromMinutes(60) 
        
        $Response = $HttpClient.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        # FIX: [void] unterdrückt die Ausgabe der HTTP-Header in der Konsole
        [void]$Response.EnsureSuccessStatusCode()

        $TotalBytes = $Response.Content.Headers.ContentLength
        if ($null -eq $TotalBytes) { $TotalBytes = -1 }

        $RemoteStream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $LocalStream = [System.IO.File]::Create($FilePath)
        
        $Buffer = New-Object byte[] 81920 
        $TotalRead = 0
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $LastUpdate = $Stopwatch.ElapsedMilliseconds

        while (($BytesRead = $RemoteStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            $LocalStream.Write($Buffer, 0, $BytesRead)
            $TotalRead += $BytesRead
            
            if (($Stopwatch.ElapsedMilliseconds - $LastUpdate) -gt 500) {
                $Speed = ($TotalRead / 1MB) / ($Stopwatch.Elapsed.TotalSeconds)
                if ($TotalBytes -gt 0) {
                    $Percent = ($TotalRead / $TotalBytes) * 100
                    $RemainingBytes = $TotalBytes - $TotalRead
                    $SecondsLeft = if ($Speed -gt 0) { $RemainingBytes / ($Speed * 1MB) } else { 0 }
                    $ETA = [TimeSpan]::FromSeconds($SecondsLeft)
                    $Status = "{0:N2} MB / {1:N2} MB @ {2:N2} MB/s [ETA: {3:mm}m {3:ss}s]" -f ($TotalRead/1MB), ($TotalBytes/1MB), $Speed, $ETA
                    Write-Progress -Activity "Downloading $FileName" -Status $Status -PercentComplete $Percent
                } else {
                    $Status = "{0:N2} MB downloaded @ {1:N2} MB/s" -f ($TotalRead/1MB), $Speed
                    Write-Progress -Activity "Downloading $FileName (Size Unknown)" -Status $Status
                }
                $LastUpdate = $Stopwatch.ElapsedMilliseconds
            }
        }
        
        $LocalStream.Close()
        $RemoteStream.Close()
        $HttpClient.Dispose()
        Write-Progress -Activity "Downloading $FileName" -Completed

        if (Test-Path $FilePath) {
            Write-Host "[SUCCESS] Download finished: $FileName" -ForegroundColor Green
            return $true
        } else { throw "File missing after download loop." }
    }
    catch {
        if ($LocalStream) { $LocalStream.Close() }
        if ($HttpClient) { $HttpClient.Dispose() }
        Write-Host "`n[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $FilePath) { Remove-Item $FilePath } 
        Write-Host "PRESS ENTER TO EXIT..." -ForegroundColor Red
        Read-Host
        exit 1
    }
}

# --- 3. INI REPAIR (FIXED LOGIC) ---
function Repair-IniFile {
    param([string]$IniFile, [string]$RepoUrl)
    $IniPath = Join-Path $TargetDir $IniFile
    
    # Check ob Datei existiert
    if (Test-Path $IniPath) {
        $Content = Get-Content -Path $IniPath -ErrorAction SilentlyContinue -Raw
        # FIX: Wir prüfen nur, ob irgendeine Sektion [...] existiert, nicht zwingend [SETTINGS]
        # Das verhindert, dass Personas/Relationships gelöscht werden.
        if ($Content -match '\[.*\]') {
            return # Datei ist okay, nichts tun
        }
        Write-Host "ERROR: File '$IniFile' appears empty or corrupt. Repairing..." -ForegroundColor Red
    } else {
        Write-Host "NOTICE: File '$IniFile' not found. Downloading..." -ForegroundColor Yellow
    }

    Remove-Item $IniPath -Force -ErrorAction SilentlyContinue
    # FIX: [void] unterdrückt "True" Ausgabe
    [void](Try-Download -Url "$RepoUrl/$IniFile" -FileName $IniFile -Description "$IniFile (Repair)")
}

# --- 4. HARDWARE CHECK ---
function Check-SystemRequirements {
    Write-Host "Running Hardware Stability Check..." -ForegroundColor Yellow
    
    $RAM_GB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    
    $MaxVRAM_Bytes = 0
    $GpuList = @()
    $GPUs = Get-CimInstance Win32_VideoController
    foreach ($GPU in $GPUs) {
        $VRAM_GB = [math]::Round($GPU.AdapterRam / 1GB, 1)
        if ($GPU.Caption) { $GpuList += "$($GPU.Caption) ($($VRAM_GB) GB)" }
        if ($GPU.AdapterRam -gt $MaxVRAM_Bytes) { $MaxVRAM_Bytes = $GPU.AdapterRam }
    }
    $TotalVRAM_GB = [math]::Round($MaxVRAM_Bytes / 1GB, 1)
    
    # Logic
    $VRAM_RESERVE_GB = 4
    $AvailableVRAM = $TotalVRAM_GB - $VRAM_RESERVE_GB
    $SuggestedLayers = 0
    $UseVRAMPreferred = 0 

    if ($TotalVRAM_GB -ge 8) { $SuggestedLayers = 33; $UseVRAMPreferred = 1 } 
    elseif ($AvailableVRAM -gt 0) { $SuggestedLayers = [int][math]::Round($AvailableVRAM * 1024 / 512) }
    if ($SuggestedLayers -gt 33) { $SuggestedLayers = 33 }
    
    $CombinedMemory_GB = $RAM_GB + $TotalVRAM_GB
    $OverallStabilityOK = $CombinedMemory_GB -ge 16
    
    $Recommendation = "GPU"
    if (-not $OverallStabilityOK) { $SuggestedLayers = 0; $Recommendation = "CPU" }
    elseif ($TotalVRAM_GB -lt 8 -and $OverallStabilityOK) { $Recommendation = "MIXED (GPU/CPU)" } 

    Write-Host "   System RAM: $RAM_GB GB | VRAM: $TotalVRAM_GB GB" -ForegroundColor DarkGray
    Write-Host "   Detected GPUs: $($GpuList -join ', ')" -ForegroundColor DarkGray
    
    # VRAM Override
    $VRAMCorrected = $TotalVRAM_GB
    if ($TotalVRAM_GB -lt 8 -and $RAM_GB -ge 16) {
        Write-Host "`nVRAM CHECK (UNCERTAIN RESULT)" -ForegroundColor Yellow
        Write-Host "Detected only $TotalVRAM_GB GB VRAM. If you have dedicated GPU (>= 8GB), verify manually." -ForegroundColor Yellow
        $Override = Read-Host "Override to Max GPU Layers (33) for max performance? (Y/N) - [Default: N]:"
        if ($Override -match "^[Yy]") {
            $VRAMCorrected = 16; $SuggestedLayers = 33; $UseVRAMPreferred = 1; $Recommendation = "GPU (Override)"
            Write-Host "[OVERRIDE] Max performance enabled." -ForegroundColor Green
        }
    } else { Write-Host "[OK] Hardware check passed." -ForegroundColor Green }
    
    return @{ TotalVRAM_GB=$VRAMCorrected; RAM_GB=$RAM_GB; SuggestedLayers=$SuggestedLayers; UseVRAMPreferred=$UseVRAMPreferred; Recommendation=$Recommendation; }
}

# --- 5. INSTALL FLOW ---
function Execute-InstallFlow {
    Write-Host "`nRunning CORE FILE VALIDATION..." -ForegroundColor Yellow
    
    if ((Test-Path (Join-Path $TargetDir "GTA5.exe")) -or (Test-Path (Join-Path $TargetDir "GTA5_Enhanced.exe"))) {
        Write-Host "[SUCCESS] Game executable found." -ForegroundColor Green
    } else {
        Write-Host "ERROR: GTA5.exe not found. Exiting." -ForegroundColor Red; Read-Host; exit 1
    }

    $DependencyFailed = $false
    foreach ($File in @("ScriptHookV.dll", "dinput8.dll")) {
        if (-not (Test-Path (Join-Path $TargetDir $File))) {
            Write-Host "WARNING: Critical dependency '$File' missing." -ForegroundColor Red
            $DependencyFailed = $true
        }
    }
    if (-not $DependencyFailed) { Write-Host "[SUCCESS] ScriptHookV dependencies found." -ForegroundColor Green }
    
    if (-not (Test-Path (Join-Path $TargetDir $ModAsiName))) {
        Write-Host "WARNING: Core mod file '$ModAsiName' missing. Ensure you extracted the ZIP." -ForegroundColor Yellow
    }
    
    $HardwareResult = Check-SystemRequirements
    
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "   MODEL & CORE DOWNLOADS                                 " -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Cyan
    
    Repair-IniFile -IniFile "GTA_LLM_Settings.ini" -RepoUrl $CONFIG_REPO_URL
    Repair-IniFile -IniFile "GTA_LLM_Relationships.ini" -RepoUrl $CONFIG_REPO_URL
    Repair-IniFile -IniFile "GTA_LLM_Personas.ini" -RepoUrl $CONFIG_REPO_URL

    Write-Host ""
    Write-Host "--- AUDIO MODEL SELECTION ---" -ForegroundColor Yellow
    $AudioChoice = Read-Host "Download Multilingual (M) or English-only (E) Whisper Model? (M/E) - [Default: E]:"
    $WhisperModelUrl = $WhisperUrl
    $WhisperModelName = $WhisperTargetName
    if ($AudioChoice -match "^[Mm]") {
        $WhisperModelName = "ggml-base.bin"
        $WhisperModelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
        Write-Host "[NOTE] Downloading Multilingual model." -ForegroundColor Yellow
    }
    
    # FIX: Unterdrücke "True" Ausgaben mit [void]
    [void](Try-Download -Url $Phi3Url -FileName $Phi3TargetName -Description "Phi-3 Model (AI Brain) - 2.3 GB")
    [void](Try-Download -Url $WhisperModelUrl -FileName $WhisperModelName -Description "Whisper Audio Model")

    # Auto-Config INI
    $IniPath = Join-Path $TargetDir $IniSettingsPath
    $AvailableMemoryForHistory_GB = $HardwareResult.RAM_GB + $HardwareResult.TotalVRAM_GB - 8
    $MAX_HISTORY = [int][math]::Round([math]::Max(4, $AvailableMemoryForHistory_GB) / 4 * 1024 * 2)
    if ($MAX_HISTORY -gt 4096) { $MAX_HISTORY = 4096 }
    
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "MAX_REMEMBER_HISTORY" -Value $MAX_HISTORY
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "MAX_OUTPUT_CHARS" -Value 786
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "USE_GPU_LAYERS" -Value $HardwareResult.SuggestedLayers
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "USE_VRAM_PREFERED" -Value $HardwareResult.UseVRAMPreferred
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "STT_MODEL_ALT_NAME" -Value $WhisperModelName
    
    Write-Host "`n[CONFIG] Auto-optimized settings applied." -ForegroundColor DarkCyan
}

# --- 6. CONFIG FLOW ---
function Start-ConfigurationFlow {
    Repair-IniFile -IniFile "GTA_LLM_Settings.ini" -RepoUrl $CONFIG_REPO_URL
    $HardwareResult = Check-SystemRequirements
    $IniPath = Join-Path $TargetDir $IniSettingsPath

    # Read Current
    $Content = Get-Content $IniPath
    $CurrentSTT = ($Content | Select-String "SPEECH_TO_TEXT" | ForEach-Object { $_.ToString().Split('=')[-1].Trim() })
    if ($CurrentSTT -eq $null) { $CurrentSTT = "1" }

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "   INI SETTINGS CONFIGURATION                             " -ForegroundColor White
    Write-Host " -run in your GTA 5 root folder -                         "
    Write-Host "==========================================================" -ForegroundColor Cyan
    
    # GPU
    $DefaultLayer = $HardwareResult.SuggestedLayers
    if ($HardwareResult.Recommendation -eq "CPU") { $DefaultLayer = 0 }
    $GpuUsage = Read-Host "Set GPU Layers (0=CPU, 33=Max) - [Default: $DefaultLayer]:"
    if (-not $GpuUsage) { $GpuUsage = $DefaultLayer }
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "USE_GPU_LAYERS" -Value $GpuUsage
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "USE_VRAM_PREFERED" -Value $HardwareResult.UseVRAMPreferred

    # STT
    Write-Host "`n--- VOICE INPUT (STT) ---" -ForegroundColor Yellow
    $DefSTTStr = if ($CurrentSTT -eq "1") {"Y"} else {"N"}
    $STTEnabled = Read-Host "Enable Speech-to-Text? (Y/N) - [Current: $DefSTTStr]:"
    
    $NewSTTVal = $CurrentSTT
    if ($STTEnabled -match "^[Yy]") { $NewSTTVal = 1 } elseif ($STTEnabled -match "^[Nn]") { $NewSTTVal = 0 }
    Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "SPEECH_TO_TEXT" -Value $NewSTTVal
    
    # Keys
    Write-Host "`n--- 3. KEY BINDINGS ---" -ForegroundColor Yellow
    if ($NewSTTVal -eq 1) {
        $PushToTalk = Read-Host "Choose PTT Key (e.g. L, 0x05) - [Default: L]:"
        if (-not $PushToTalk) { $PushToTalk = "L" }
        Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "SPEECH_TO_TEXT_RECORDING_BUTTON" -Value $PushToTalk
    }

    $ActivationKey = Read-Host "Set Activation Key - [Default: T]:"
    if ($ActivationKey) { Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "ACTIVATION_KEY" -Value $ActivationKey }
    $StopKey = Read-Host "Set Stop Key - [Default: U]:"
    if ($StopKey) { Set-IniValue -FilePath $IniPath -Section "SETTINGS" -Key "STOP_KEY" -Value $StopKey }

    Write-Host "`n[SUCCESS] Configuration saved." -ForegroundColor Green
    Show-PostInstallMenu
    Read-Host
}

# --- 7. MENUS ---
function Show-MainMenu {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   EC MOD INSTALLER (v1.0)                                " -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "Select option:" -ForegroundColor Yellow
    Write-Host "1) FULL INSTALLATION" -ForegroundColor White
    Write-Host "2) CONFIGURE SETTINGS" -ForegroundColor White
    Write-Host "3) UNINSTALL MOD" -ForegroundColor Red
    Write-Host "4) EXIT" -ForegroundColor Red
    
    switch (Read-Host "Option") {
        "1" { Execute-InstallFlow; Show-PostInstallMenu }
        "2" { Start-ConfigurationFlow }
        "3" { Remove-ModFiles }
        "4" { exit 0 }
        default { Show-MainMenu }
    }
}

function Show-PostInstallMenu {
    Write-Host "`n----------------------------------------------------------"
    Write-Host "Select Next Action:" -ForegroundColor Yellow
    Write-Host "1) CONFIGURE SETTINGS (Keys/GPU/STT)" -ForegroundColor White
    Write-Host "2) START GAME" -ForegroundColor Green
    Write-Host "3) EXIT" -ForegroundColor Red
    
    $StartFile = "GTA5.exe"
    if (Test-Path (Join-Path $TargetDir "PlayGTAV.exe")) { $StartFile = "PlayGTAV.exe" }

    switch (Read-Host "Option") {
        "1" { Start-ConfigurationFlow }
        "2" { Start-Process -FilePath (Join-Path $TargetDir $StartFile); exit 0 }
        "3" { exit 0 }
        default { Show-PostInstallMenu }
    }
}

function Remove-ModFiles {
    $Confirm = Read-Host "DELETE ALL MOD FILES? (Y/N)"
    if ($Confirm -match "^[Yy]") {
        $Files = @($Phi3TargetName, $WhisperTargetName, "ggml-base.bin", "GTA_LLM_Settings.ini", "GTA_LLM_Relationships.ini", "GTA_LLM_Personas.ini", "download_models.ps1")
        foreach ($F in $Files) { if(Test-Path $F){Remove-Item $F -Force; Write-Host "Deleted $F" -ForegroundColor Red} }
        Write-Host "Done. Remove '$ModAsiName' manually."
        Read-Host
    }
}

Show-MainMenu