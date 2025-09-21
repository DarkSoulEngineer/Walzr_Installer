# ===============================================
# install_glazewm_zebar.ps1
# Installs Chocolatey + Git + Rust (MSVC only),
# installs Visual Studio Build Tools via Choco,
# installs GlazeWM + Zebar MSI, or builds GlazeWM from source
# ===============================================

# ------------------------------
# 0️⃣ Ensure running as Admin
# ------------------------------
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Warning "Please run this script as Administrator."
    exit
}

# ------------------------------
# 1️⃣ Set execution policy and TLS
# ------------------------------
Set-ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ------------------------------
# 2️⃣ Install Chocolatey if missing
# ------------------------------
$chocoExe = "$env:ProgramData\Chocolatey\bin\choco.exe"
if (-not (Test-Path $chocoExe)) {
    Write-Host "Installing Chocolatey..."
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    if (-not (Test-Path $chocoExe)) {
        Write-Error "Chocolatey installation failed. Install manually."
        exit
    }
}
if (-not ($env:Path -split ";" | Where-Object { $_ -eq "$env:ProgramData\Chocolatey\bin" })) {
    $env:Path = "$env:ProgramData\Chocolatey\bin;$env:Path"
}

# ------------------------------
# 3️⃣ Install Git if missing
# ------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Git..."
    Start-Process -FilePath $chocoExe -ArgumentList "install git -y --no-progress" -Wait -NoNewWindow
    $gitCmdPath = "$env:ProgramFiles\Git\cmd"
    if (-not ($env:Path -split ";" | Where-Object { $_ -eq $gitCmdPath })) {
        $env:Path += ";$gitCmdPath"
    }
}

# ------------------------------
# 4️⃣ Install Rust via rustup
# ------------------------------
$cargoBin = "$env:USERPROFILE\.cargo\bin"
if (-not ($env:Path -split ";" | Where-Object { $_ -eq $cargoBin })) {
    $env:Path = "$cargoBin;$env:Path"
    [Environment]::SetEnvironmentVariable("PATH", "$cargoBin;" + [Environment]::GetEnvironmentVariable("PATH", "User"), "User")
}
if (-not (Test-Path "$cargoBin\rustc.exe")) {
    Write-Host "Installing Rust via rustup..."
    $rustupExe = "$env:TEMP\rustup-init.exe"
    Invoke-WebRequest -Uri https://win.rustup.rs/x86_64 -OutFile $rustupExe
    Start-Process -FilePath $rustupExe -ArgumentList "-y" -Wait
}
$rustupPath = Join-Path $cargoBin "rustup.exe"

# ------------------------------
# 5️⃣ Configure Rust for MSVC only
# ------------------------------
Write-Host "Installing MSVC toolchain..."
& $rustupPath install stable-x86_64-pc-windows-msvc
& $rustupPath default stable-x86_64-pc-windows-msvc

# ------------------------------
# 6️⃣ Install Visual Studio Build Tools and Brave Browser via Choco
# ------------------------------
$vsWhere = "$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstalled = $false
if (Test-Path $vsWhere) {
    $vsInstalled = (& $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -ne ""
}
if (-not $vsInstalled) {
    Write-Host "Installing Visual Studio Build Tools..."
    Start-Process -FilePath $chocoExe -ArgumentList 'install visualstudio2022buildtools -y --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --locale en-US"' -Wait -NoNewWindow
} else {
    Write-Host "Visual Studio Build Tools already installed. Skipping..."
}

if (-not (Get-Command brave -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Brave Browser..."
    Start-Process -FilePath $chocoExe -ArgumentList "install brave -y --no-progress" -Wait -NoNewWindow
} else {
    Write-Host "Brave Browser already installed. Skipping..."
}

# ------------------------------
# 7️⃣ Define installation directories
# ------------------------------
$glzrBase = Join-Path $env:ProgramFiles "glzr.io"
$glazeInstallDir = Join-Path $glzrBase "GlazeWM"
$zebarInstallDir = Join-Path $glzrBase "Zebar"

# Create directories if they don't exist
New-Item -ItemType Directory -Force -Path $glzrBase | Out-Null

# ------------------------------
# 8️⃣ Install GlazeWM via MSI
# ------------------------------
$glazeMsiUrl = "https://github.com/glzr-io/glazewm/releases/download/v3.9.1/standalone-glazewm-v3.9.1-x64.msi"
$glazeMsi = "$env:TEMP\glazewm-v3.9.1-x64.msi"
$glazeExe = Join-Path $glazeInstallDir "GlazeWM.exe"

if (-not (Test-Path $glazeExe)) {
    Write-Host "Downloading GlazeWM MSI..."
    Invoke-WebRequest -Uri $glazeMsiUrl -OutFile $glazeMsi

    Write-Host "Installing GlazeWM silently to $glazeInstallDir..."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$glazeMsi`" TARGETDIR=`"$glazeInstallDir`" /quiet /norestart /log `"$env:TEMP\glazewm_install.log`"" -Wait

    if (Test-Path $glazeExe) {
        Write-Host "GlazeWM installed successfully via MSI."
    } else {
        Write-Warning "MSI install failed. Attempting source build..."
        Remove-Item $glazeMsi -Force
        # Fallback: clone + build from source
        $glazeSrcDir = Join-Path $env:USERPROFILE ".glzr\glazewm"
        if (-not (Test-Path (Join-Path $glazeSrcDir ".git"))) {
            git clone https://github.com/glzr-io/glazewm.git $glazeSrcDir
        }
        Write-Host "Building GlazeWM from source..."
        Push-Location $glazeSrcDir
        cargo build --release --locked
        if ($LASTEXITCODE -ne 0) {
            Write-Error "GlazeWM build failed."
            Pop-Location
            exit
        }
        Pop-Location
        Copy-Item "$glazeSrcDir\target\release\GlazeWM.exe" $glazeInstallDir -Force
    }
    Remove-Item $glazeMsi -Force
} else {
    Write-Host "GlazeWM already installed. Skipping MSI install."
}

# ------------------------------
# 9️⃣ Install Zebar MSI
# ------------------------------
$zebarMsiUrl = "https://github.com/glzr-io/zebar/releases/download/v3.1.1/zebar-v3.1.1-opt1-x64.msi"
$zebarMsi = "$env:TEMP\zebar-v3.1.1-opt1-x64.msi"
$zebarExe = Join-Path $zebarInstallDir "Zebar.exe"

if (-not (Test-Path $zebarExe)) {
    Write-Host "Downloading Zebar MSI..."
    Invoke-WebRequest -Uri $zebarMsiUrl -OutFile $zebarMsi

    Write-Host "Installing Zebar silently to $zebarInstallDir..."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$zebarMsi`" TARGETDIR=`"$zebarInstallDir`" /quiet /norestart /log `"$env:TEMP\zebar_install.log`"" -Wait

    if (Test-Path $zebarExe) {
        Write-Host "Zebar installed successfully."
    } else {
        Write-Warning "Zebar installation may have failed. Check logs at $env:TEMP\zebar_install.log"
    }
    Remove-Item $zebarMsi -Force
} else {
    Write-Host "Zebar already installed. Skipping MSI install."
}

# Add Zebar to PATH
if (-not ($env:Path -split ";" | Where-Object { $_ -eq $zebarInstallDir })) {
    $env:Path = "$zebarInstallDir;$env:Path"
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not ($userPath -split ";" | Where-Object { $_ -eq $zebarInstallDir })) {
        [Environment]::SetEnvironmentVariable("PATH", "$zebarInstallDir;$userPath", "User")
    }
}

# ================================
# zebar_neon_theme install script
# ================================

# Dynamically get current user's home directory
$userProfile = $env:USERPROFILE
$zebarDir = Join-Path $userProfile ".glzr\zebar"

# Ensure the Zebar directory exists
New-Item -ItemType Directory -Force -Path $zebarDir | Out-Null

# Clone zebar_neon_theme directly inside .glzr\zebar
$themeRepoDir = Join-Path $zebarDir "zebar_neon_theme"
if (-not (Test-Path $themeRepoDir)) {
    git clone https://github.com/DarkSoulEngineer/zebar_neon_theme $themeRepoDir
} else {
    Write-Host "Repository already cloned. Skipping clone."
}

# Move settings.json one folder down into .glzr\zebar
$sourceSettings = Join-Path $themeRepoDir "settings.json"
$destSettings = Join-Path $zebarDir "settings.json"

if (Test-Path $sourceSettings) {
    Move-Item $sourceSettings $destSettings -Force
    Write-Host "✅ settings.json moved to $zebarDir"
} else {
    Write-Warning "settings.json not found in $themeRepoDir"
}

Write-Host "✅ zebar_neon_theme setup complete inside $zebarDir"


# ------------------------------
# 🔟 Run GlazeWM
# ------------------------------
if (Test-Path $glazeExe) {
    Write-Host "`nLaunching GlazeWM (it will auto-launch Zebar)..."
    Start-Process -FilePath $glazeExe -WorkingDirectory $glazeInstallDir
} else {
    Write-Warning "GlazeWM.exe not found."
}

Write-Host "`n✅ Installation process complete! GlazeWM and Zebar are ready."
