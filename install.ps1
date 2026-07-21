# Fabi installer for Windows (PowerShell).
#
# Usage:
#   irm https://github.com/Noagiannone03/fabi/releases/latest/download/install.ps1 | iex
#   irm https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.ps1 | iex
#
# Supported environment variables:
#   $env:FABI_VERSION       version to install (default: latest)
#   $env:FABI_INSTALL       Windows shim directory (default: $env:LOCALAPPDATA\fabi)
#   $env:FABI_REPO          source repo override (default: Noagiannone03/fabi)
#   $env:FABI_ACCEL         force accelerator (cuda / cpu)
#   $env:FABI_WINDOWS_MODE  native (default, no WSL) or wsl (legacy)
#   $env:FABI_WSL_DISTRO    optional WSL distro name (only when FABI_WINDOWS_MODE=wsl)
#
# Windows runs Fabi NATIVELY (no WSL): the GPU engine uses the native-Windows vLLM
# wheel (SystemPanic, cu124) + mlx-free Parallax, bundled in the windows-x64-cuda
# release asset. Set FABI_WINDOWS_MODE=wsl only for the legacy path (running the
# Linux runtime inside WSL).

$ErrorActionPreference = "Stop"

function Write-Log($msg)  { Write-Host "[fabi-install] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[fabi-install] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Warning "[fabi-install] $msg" }
function Write-Err($msg)  { Write-Host "[fabi-install] $msg" -ForegroundColor Red }

function Save-UrlFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curl) {
        $attempts = 6
        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            $args = @(
                "--fail",
                "--location",
                "--show-error",
                "--connect-timeout", "30",
                "--speed-limit", "1024",
                "--speed-time", "60",
                "--output", $OutFile
            )
            if ((Test-Path -LiteralPath $OutFile -PathType Leaf) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                $args += @("--continue-at", "-")
            }
            $args += $Uri

            & $curl.Source @args
            if ($LASTEXITCODE -eq 0) {
                return
            }

            if ($attempt -eq $attempts) {
                throw "curl.exe failed with exit code $LASTEXITCODE while downloading $Uri"
            }

            Write-Warn "Telechargement interrompu, nouvelle tentative $($attempt + 1)/$attempts : $Uri"
            Start-Sleep -Seconds ([Math]::Min(30, 2 * $attempt))
        }
    }

    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Read-UrlText {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $tmp = New-TemporaryFile
    try {
        Save-UrlFile -Uri $Uri -OutFile $tmp.FullName
        return (Get-Content -LiteralPath $tmp.FullName -Raw)
    } finally {
        Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Get-FabiRepo {
    if ($env:FABI_REPO) { return $env:FABI_REPO }
    return "Noagiannone03/fabi"
}

function Get-FabiVersion {
    param([string]$Repo)
    if ($env:FABI_VERSION) { return $env:FABI_VERSION }
    return "latest"
}

function Get-InstallRoot {
    if ($env:FABI_INSTALL) { return $env:FABI_INSTALL }
    return (Join-Path $env:LOCALAPPDATA "fabi")
}

function Test-NvidiaGpu {
    return [bool](Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue)
}

function Get-Accel {
    if ($env:FABI_ACCEL) { return $env:FABI_ACCEL }
    if (Test-NvidiaGpu) { return "cuda" }
    return "cpu"
}

function Quote-Bash {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-Wsl {
    param([string[]]$Arguments)
    $baseArgs = @()
    if ($env:FABI_WSL_DISTRO) {
        $baseArgs += @("-d", $env:FABI_WSL_DISTRO)
    }
    $baseArgs += $Arguments
    & wsl.exe @baseArgs
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe failed with exit code $LASTEXITCODE"
    }
}

function Assert-WslReady {
    if (-not (Get-Command "wsl.exe" -ErrorAction SilentlyContinue)) {
        Write-Err "WSL n'est pas disponible. Installe WSL puis relance:"
        Write-Host "  wsl --install -d Ubuntu"
        exit 1
    }

    try {
        Invoke-Wsl @("--status") | Out-Null
    } catch {
        Write-Warn "Impossible de lire le statut WSL. On tente quand meme l'installation."
    }

    $distroList = (& wsl.exe -l -q 2>$null) | Where-Object { $_.Trim().Length -gt 0 }
    if (-not $distroList -and -not $env:FABI_WSL_DISTRO) {
        Write-Err "Aucune distribution WSL detectee. Installe Ubuntu puis relance:"
        Write-Host "  wsl --install -d Ubuntu"
        exit 1
    }
}

function Install-WslFabi {
    param(
        [string]$Repo,
        [string]$Version,
        [string]$Accel,
        [string]$InstallRoot
    )

    Assert-WslReady

    if ($Accel -eq "cuda" -and -not (Test-NvidiaGpu)) {
        Write-Warn "FABI_ACCEL=cuda mais nvidia-smi.exe est introuvable cote Windows."
        Write-Warn "Assure-toi d'avoir un driver NVIDIA recent avec support WSL CUDA."
    }

    $installUrl = "https://raw.githubusercontent.com/${Repo}/main/install.sh"
    $bash = @(
        "set -e"
        "export FABI_REPO=$(Quote-Bash $Repo)"
        "export FABI_ACCEL=$(Quote-Bash $Accel)"
        "export FABI_PARALLAX_EXTRA=$(Quote-Bash $(if ($Accel -eq 'cuda') { 'gpu' } else { '' }))"
    )
    if ($env:FABI_PARALLAX_REF) {
        $bash += "export FABI_PARALLAX_REF=$(Quote-Bash $env:FABI_PARALLAX_REF)"
    }
    if ($Version -ne "latest") {
        $bash += "export FABI_VERSION=$(Quote-Bash $Version)"
    }
    $bash += "command -v curl >/dev/null 2>&1 || { echo 'curl manquant dans WSL. Installe-le: sudo apt install curl' >&2; exit 1; }"
    $bash += "curl -fsSL $(Quote-Bash $installUrl) | bash"
    $bash += "fabi --help >/dev/null || true"

    Write-Log "Installation Linux Fabi dans WSL ($Accel)..."
    Invoke-Wsl @("bash", "-lc", ($bash -join "; "))

    $binDir = Join-Path $InstallRoot "bin"
    New-Item -Type Directory -Path $binDir -Force | Out-Null

    $psShim = Join-Path $binDir "fabi.ps1"
    $cmdShim = Join-Path $binDir "fabi.cmd"

    @'
$ErrorActionPreference = "Stop"
$wslBase = @()
if ($env:FABI_WSL_DISTRO) {
    $wslBase += @("-d", $env:FABI_WSL_DISTRO)
}
$wslBase += @("bash", "-lc", 'fabi "$@"', "fabi")
$allArgs = @()
$allArgs += $wslBase
$allArgs += $args
& wsl.exe @allArgs
exit $LASTEXITCODE
'@ | Set-Content -Path $psShim -Encoding UTF8

    @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fabi.ps1" %*
'@ | Set-Content -Path $cmdShim -Encoding ASCII

    Add-ToUserPath $binDir
    Write-Ok "Fabi installe via WSL"
    Write-Host ""
    Write-Host "  Lance avec : fabi"
    Write-Host "  Runtime    : WSL Linux ($Accel)"
    Write-Host ""
}

function Add-ToUserPath {
    param([string]$BinDir)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$BinDir*") {
        Write-Log "Ajout de $BinDir au PATH utilisateur..."
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            [Environment]::SetEnvironmentVariable("Path", $BinDir, "User")
        } else {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$BinDir", "User")
        }
        Write-Warn "Redemarre ton terminal pour que fabi soit reconnu."
    }
}

function Relocate-BundledRuntime {
    param([string]$InstallRoot)

    $placeholder = "__FABI_INSTALL_ROOT__"
    $manifest = Join-Path $InstallRoot "runtime\relocation-manifest.txt"
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "Manifeste de relocalisation runtime absent : $manifest"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $count = 0
    foreach ($line in [System.IO.File]::ReadAllLines($manifest, $utf8)) {
        $relative = $line.Trim()
        if (-not $relative) { continue }
        $segments = $relative -split "[\\/]"
        if ([System.IO.Path]::IsPathRooted($relative) -or $segments -contains ".." -or $segments[0] -ne "runtime") {
            throw "Chemin de relocalisation invalide : $relative"
        }

        $normalized = $relative.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
        $path = Join-Path $InstallRoot $normalized
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Fichier de relocalisation absent : $relative"
        }
        $content = [System.IO.File]::ReadAllText($path, $utf8)
        if (-not $content.Contains($placeholder)) {
            throw "Placeholder de relocalisation absent : $relative"
        }
        [System.IO.File]::WriteAllText($path, $content.Replace($placeholder, $InstallRoot), $utf8)
        $count += 1
    }

    if ($count -eq 0) {
        throw "Manifeste de relocalisation runtime vide"
    }
    Write-Ok "Runtime Python relocalise dans $count fichiers"
}

function Install-NativeFabi {
    param(
        [string]$Repo,
        [string]$Version,
        [string]$Accel,
        [string]$InstallRoot
    )

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default {
            Write-Err "Architecture non supportee : $($env:PROCESSOR_ARCHITECTURE)"
            exit 1
        }
    }
    $platform = "windows-${arch}-${Accel}"
    Write-Log "Plateforme native detectee : $platform"

    if ($Version -eq "latest") {
        Write-Log "Resolution de la derniere version..."
        $api = Invoke-RestMethod "https://api.github.com/repos/${Repo}/releases/latest"
        $Version = $api.tag_name
    }
    Write-Ok "Version cible : $Version"

    $tarballName = "fabi-${platform}.tar.zst"
    $tarballUrl = "https://github.com/${Repo}/releases/download/${Version}/${tarballName}"
    $shaUrl = "${tarballUrl}.sha256"

    $tmpDir = New-Item -Type Directory -Path (Join-Path $env:TEMP "fabi-install-$([guid]::NewGuid().ToString())")
    try {
        $tarballPath = Join-Path $tmpDir "fabi.tar.zst"
        $dlBase = "https://github.com/${Repo}/releases/download/${Version}"
        # Asset splitte ? release-build.sh publie un manifeste .parts quand le
        # tarball depasse 2 Go (limite GitHub) -> on telecharge les parties et on
        # reassemble (concatenation binaire). Sinon, telechargement direct.
        $partsTxt = Join-Path $tmpDir "parts.txt"
        $isSplit = $true
        try { Save-UrlFile -Uri "$tarballUrl.parts" -OutFile $partsTxt } catch { $isSplit = $false }
        if ($isSplit) {
            Write-Log "Asset volumineux -> telechargement en parties + reassemblage..."
            $out = [System.IO.File]::Open($tarballPath, [System.IO.FileMode]::Create)
            try {
                foreach ($line in (Get-Content $partsTxt)) {
                    $part = $line.Trim()
                    if (-not $part) { continue }
                    $partPath = Join-Path $tmpDir $part
                    Write-Log "  partie : $part"
                    Save-UrlFile -Uri "$dlBase/$part" -OutFile $partPath
                    $in = [System.IO.File]::OpenRead($partPath)
                    try { $in.CopyTo($out) } finally { $in.Close() }
                    Remove-Item $partPath -Force
                }
            } finally { $out.Close() }
        } else {
            Write-Log "Telechargement : $tarballUrl"
            Save-UrlFile -Uri $tarballUrl -OutFile $tarballPath
        }

        try {
            $expected = (Read-UrlText -Uri $shaUrl).Trim().Split()[0]
            $actual = (Get-FileHash -Path $tarballPath -Algorithm SHA256).Hash.ToLower()
            if ($expected -ne $actual) {
                Write-Err "SHA256 mismatch. Attendu: $expected, Recu: $actual"
                exit 1
            }
            Write-Ok "Integrite verifiee"
        } catch {
            Write-Warn "Pas de fichier .sha256 disponible; verification skippee"
        }

        if (Test-Path $InstallRoot) {
            $backup = "${InstallRoot}.backup-$(Get-Date -UFormat %s)"
            Write-Warn "Install existante detectee, backup -> $backup"
            Move-Item $InstallRoot $backup
        }

        if (-not (Get-Command "zstd.exe" -ErrorAction SilentlyContinue)) {
            Write-Err "zstd.exe n'est pas disponible. Installe: winget install Facebook.Zstandard"
            exit 1
        }

        New-Item -Type Directory -Path $InstallRoot -Force | Out-Null
        & zstd.exe -d "$tarballPath" -o (Join-Path $tmpDir "fabi.tar")
        & tar.exe -xf (Join-Path $tmpDir "fabi.tar") -C $InstallRoot --strip-components=1

        Relocate-BundledRuntime -InstallRoot $InstallRoot

        $fabiBin = Join-Path $InstallRoot "bin\fabi.exe"
        if (-not (Test-Path $fabiBin)) {
            Write-Err "fabi.exe absent apres extraction : $fabiBin"
            exit 1
        }

        $runtimePython = Join-Path $InstallRoot "runtime\parallax-venv\Scripts\python.exe"
        if (-not (Test-Path -LiteralPath $runtimePython -PathType Leaf)) {
            throw "Python runtime absent apres extraction : $runtimePython"
        }
        & $runtimePython -c "import parallax"
        if ($LASTEXITCODE -ne 0) {
            throw "Le runtime Parallax relocalise ne peut pas etre importe"
        }

        Add-ToUserPath (Join-Path $InstallRoot "bin")
        Write-Ok "Fabi $Version installe en mode Windows natif"
    } finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }
}

Write-Host @"

  FABI

  CLI agentique open source connecte au swarm Fabi

"@ -ForegroundColor DarkYellow

$repo = Get-FabiRepo
$version = Get-FabiVersion -Repo $repo
$accel = Get-Accel
$installRoot = Get-InstallRoot
$mode = if ($env:FABI_WINDOWS_MODE) { $env:FABI_WINDOWS_MODE.ToLowerInvariant() } else { "native" }

Write-Log "Repo: $repo"
Write-Log "Version: $version"
Write-Log "Accel: $accel"
Write-Log "Mode Windows: $mode"

switch ($mode) {
    "wsl" {
        Install-WslFabi -Repo $repo -Version $version -Accel $accel -InstallRoot $installRoot
    }
    "native" {
        Install-NativeFabi -Repo $repo -Version $version -Accel $accel -InstallRoot $installRoot
    }
    default {
        Write-Err "FABI_WINDOWS_MODE invalide: $mode (attendu: wsl ou native)"
        exit 1
    }
}
