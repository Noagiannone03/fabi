# Fabi installer for Windows (PowerShell).
#
# Usage :
#   irm https://fabi.aircarto.fr/install.ps1 | iex
# ou (sans le sous-domaine) :
#   irm https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.ps1 | iex
#
# Variables d'environnement supportées :
#   $env:FABI_VERSION   version à installer (défaut : latest)
#   $env:FABI_INSTALL   dossier d'install (défaut : $env:LOCALAPPDATA\fabi)
#   $env:FABI_REPO      override repo source (défaut : Noagiannone03/fabi)
#
# NOTE : install.ps1 est encore expérimental — la cible windows-x64 doit être
# activée dans .github/workflows/release.yml avant de pouvoir l'utiliser.

$ErrorActionPreference = "Stop"

function Write-Log($msg)  { Write-Host "[fabi-install] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[fabi-install] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Warning "[fabi-install] $msg" }
function Write-Err($msg)  { Write-Host "[fabi-install] $msg" -ForegroundColor Red }

# Banner
Write-Host @"

  ███████╗ █████╗ ██████╗ ██╗
  ██╔════╝██╔══██╗██╔══██╗██║
  █████╗  ███████║██████╔╝██║
  ██╔══╝  ██╔══██║██╔══██╗██║
  ██║     ██║  ██║██████╔╝██║
  ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝

  CLI agentique open source qui rejoint le swarm Aircarto

"@ -ForegroundColor DarkYellow

# Detection arch
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "x64" }
    "ARM64" { "arm64" }
    default { Write-Err "Architecture non supportée : $($env:PROCESSOR_ARCHITECTURE)"; exit 1 }
}

# Detection accel
$accel = if ($env:FABI_ACCEL) {
    $env:FABI_ACCEL
} elseif (Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue) {
    "cuda"
} else {
    "cpu"
}

$platform = "windows-${arch}-${accel}"
Write-Log "Plateforme détectée : $platform"

# Resolution version
$repo = if ($env:FABI_REPO) { $env:FABI_REPO } else { "Noagiannone03/fabi" }
$version = if ($env:FABI_VERSION) {
    $env:FABI_VERSION
} else {
    Write-Log "Résolution de la dernière version…"
    $api = Invoke-RestMethod "https://api.github.com/repos/${repo}/releases/latest"
    $api.tag_name
}
Write-Ok "Version cible : $version"

$tarballName = "fabi-${platform}.tar.zst"
$tarballUrl = "https://github.com/${repo}/releases/download/${version}/${tarballName}"
$shaUrl = "${tarballUrl}.sha256"

# Download
$installRoot = if ($env:FABI_INSTALL) { $env:FABI_INSTALL } else { Join-Path $env:LOCALAPPDATA "fabi" }
$tmpDir = New-Item -Type Directory -Path (Join-Path $env:TEMP "fabi-install-$([guid]::NewGuid().ToString())")
try {
    $tarballPath = Join-Path $tmpDir "fabi.tar.zst"

    Write-Log "Téléchargement : $tarballUrl"
    Invoke-WebRequest -Uri $tarballUrl -OutFile $tarballPath -UseBasicParsing

    # SHA256 check (best effort)
    try {
        $expected = (Invoke-WebRequest -Uri $shaUrl -UseBasicParsing).Content.Trim().Split()[0]
        $actual = (Get-FileHash -Path $tarballPath -Algorithm SHA256).Hash.ToLower()
        if ($expected -ne $actual) {
            Write-Err "SHA256 mismatch ! Attendu: $expected, Reçu: $actual"
            exit 1
        }
        Write-Ok "Intégrité vérifiée"
    } catch {
        Write-Warn "Pas de fichier .sha256 dispo — vérification skipée"
    }

    # Backup existing install
    if (Test-Path $installRoot) {
        $backup = "${installRoot}.backup-$(Get-Date -UFormat %s)"
        Write-Warn "Install existante détectée, backup → $backup"
        Move-Item $installRoot $backup
    }

    # Extract via tar (Windows 10+ a tar bundlé, mais pas zstd natif)
    Write-Log "Installation dans $installRoot…"
    if (-not (Get-Command "zstd.exe" -ErrorAction SilentlyContinue)) {
        Write-Err "zstd.exe n'est pas disponible. Install : winget install Facebook.Zstandard"
        exit 1
    }

    New-Item -Type Directory -Path $installRoot -Force | Out-Null
    & zstd.exe -d "$tarballPath" -o (Join-Path $tmpDir "fabi.tar")
    & tar.exe -xf (Join-Path $tmpDir "fabi.tar") -C $installRoot --strip-components=1

    $fabiBin = Join-Path $installRoot "bin\fabi.exe"
    if (-not (Test-Path $fabiBin)) {
        Write-Err "fabi.exe absent après extraction : $fabiBin"
        exit 1
    }

    # PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $binDir = Join-Path $installRoot "bin"
    if ($userPath -notlike "*$binDir*") {
        Write-Log "Ajout de $binDir au PATH utilisateur…"
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User")
        Write-Warn "Redémarre ton terminal pour que `fabi` soit reconnu."
    }

    Write-Host ""
    Write-Ok "Fabi $version installé avec succès"
    Write-Host ""
    Write-Host "  Lance avec : fabi"
    Write-Host "  Aide       : fabi --help"
    Write-Host ""
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
