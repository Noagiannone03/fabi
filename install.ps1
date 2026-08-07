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
#   $env:FABI_ACCEL         force accelerator (cuda / directml; cpu in WSL)
#   $env:FABI_WINDOWS_MODE  native (default, no WSL) or wsl (legacy)
#   $env:FABI_WSL_DISTRO    optional WSL distro name (only when FABI_WINDOWS_MODE=wsl)
#   $env:FABI_TARBALL_PATH  optional local release tarball to install instead of downloading
#   $env:FABI_ZSTD_PATH     optional local decompressor plus .sha256 sidecar
#   $env:FABI_NO_PATH       "1" to leave the user PATH unchanged
#
# Windows runs Fabi NATIVELY (no WSL). NVIDIA uses the qualified vLLM-Windows
# runtime; Intel/AMD/Qualcomm GPUs use the official ONNX Runtime DirectML wheel.
# Set FABI_WINDOWS_MODE=wsl only for the legacy Linux path.

$ErrorActionPreference = "Stop"

function Write-Log($msg)  { Write-Host "[fabi-install] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[fabi-install] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Warning "[fabi-install] $msg" }
function Write-Err($msg)  { Write-Host "[fabi-install] $msg" -ForegroundColor Red }

function Remove-ManagedDirectoryTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return
    } catch {
        $providerError = $_
    }

    # Windows PowerShell 5's FileSystem provider can still fail below MAX_PATH
    # in CUDA/Python trees even on a long-path-enabled host. Robocopy is part of
    # supported Windows releases and uses native extended-path traversal. An
    # empty mirror removes the descendants; Directory.Delete then removes only
    # the already-validated managed backup root.
    $robocopy = Get-Command "robocopy.exe" -ErrorAction SilentlyContinue
    if (-not $robocopy) {
        throw $providerError
    }
    $empty = Join-Path ([System.IO.Path]::GetTempPath()) (
        "fabi-empty-{0}-{1}" -f $PID, [guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path $empty -Force -ErrorAction Stop | Out-Null
    try {
        & $robocopy.Source $empty $Path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null
        $robocopyExitCode = $LASTEXITCODE
        # Robocopy documents 0..7 as success states; 8+ means at least one
        # copy/delete failure (for example an actually locked runtime file).
        if ($robocopyExitCode -gt 7) {
            throw (
                "robocopy failed with exit code {0}; PowerShell provider: {1}" -f
                $robocopyExitCode,
                $providerError.Exception.Message
            )
        }
        try {
            [System.IO.Directory]::Delete($Path, $false)
        } catch {
            throw (
                "native root removal failed: {0}; PowerShell provider: {1}" -f
                $_.Exception.Message,
                $providerError.Exception.Message
            )
        }
        if (Test-Path -LiteralPath $Path) {
            throw "managed backup root is still present after cleanup"
        }
    } finally {
        Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-StaleRuntimeBackups {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$Keep
    )
    $parent = Split-Path -Parent $InstallRoot
    $prefix = "$(Split-Path -Leaf $InstallRoot).backup-"
    $keepFull = [System.IO.Path]::GetFullPath($Keep)
    Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name.StartsWith($prefix, [System.StringComparison]::Ordinal) -and
            -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        } |
        ForEach-Object {
            # Dans un bloc catch, la variable automatique `$_` devient
            # l'ErrorRecord. Capturer le chemin avant la suppression évite un
            # diagnostic vide et conserve la vraie cible en cas de verrou ou
            # de limite Windows sur un ancien environnement Python profond.
            $backupPath = [System.IO.Path]::GetFullPath($_.FullName)
            if ($backupPath -ne $keepFull) {
                try {
                    Remove-ManagedDirectoryTree -Path $backupPath
                } catch {
                    Write-Warn (
                        "Impossible de supprimer l'ancien rollback {0} : {1}" -f
                        $backupPath,
                        $_.Exception.Message
                    )
                }
            }
        }
}

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

    $attempts = 6
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            # Boucle explicite pour rester compatible avec Windows PowerShell
            # 5.1, qui ne possède pas encore MaximumRetryCount.
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return
        } catch {
            if ($attempt -eq $attempts) {
                throw
            }
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            Write-Warn "Telechargement interrompu, nouvelle tentative $($attempt + 1)/$attempts : $Uri"
            Start-Sleep -Seconds ([Math]::Min(30, 2 * $attempt))
        }
    }
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

function Get-VerifiedZstd {
    param(
        [string]$Repo,
        [string]$Version,
        [string]$Platform,
        [string]$TmpDir
    )

    if ($env:FABI_ZSTD_PATH) {
        if (-not (Test-Path -LiteralPath $env:FABI_ZSTD_PATH -PathType Leaf) -or
            -not (Test-Path -LiteralPath "$($env:FABI_ZSTD_PATH).sha256" -PathType Leaf)) {
            throw "FABI_ZSTD_PATH doit pointer vers un fichier et son sidecar .sha256"
        }
        $sourcePath = $env:FABI_ZSTD_PATH
        $expected = (Get-Content -LiteralPath "$sourcePath.sha256" -Raw).Trim().Split()[0]
        $zstdPath = Join-Path $TmpDir "fabi-unzstd.exe"
        Copy-Item -LiteralPath $sourcePath -Destination $zstdPath -Force
    } else {
        $systemZstd = Get-Command "zstd.exe" -ErrorAction SilentlyContinue
        if ($systemZstd) {
            return $systemZstd.Source
        }

        $helperName = "fabi-unzstd-${Platform}.exe"
        $helperUrl = "https://github.com/${Repo}/releases/download/${Version}/${helperName}"
        $zstdPath = Join-Path $TmpDir $helperName
        Write-Log "zstd absent -> telechargement du decompresseur autonome..."
        Save-UrlFile -Uri $helperUrl -OutFile $zstdPath
        try {
            $expected = (Read-UrlText -Uri "${helperUrl}.sha256").Trim().Split()[0]
        } catch {
            throw "Checksum du decompresseur autonome absent : ${helperUrl}.sha256"
        }
    }

    if ($expected -notmatch "^[0-9a-fA-F]{64}$") {
        throw "SHA256 invalide pour le decompresseur autonome"
    }
    $actual = (Get-FileHash -LiteralPath $zstdPath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected.ToLower()) {
        throw "SHA256 mismatch pour le decompresseur autonome. Attendu: $expected, Recu: $actual"
    }
    Write-Ok "Decompresseur autonome verifie"
    return $zstdPath
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

function New-InstallTransactionDirectory {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $absoluteRoot = [System.IO.Path]::GetFullPath($InstallRoot)
    $parent = [System.IO.Path]::GetDirectoryName($absoluteRoot)
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "FABI_INSTALL doit designer un repertoire, pas la racine d'un volume"
    }
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $transactionRoot = Join-Path $parent (".fabi-install-{0}" -f [guid]::NewGuid())
    return New-Item -ItemType Directory -Path $transactionRoot
}

function Test-NvidiaGpu {
    return [bool](Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue)
}

function Get-Accel {
    if ($env:FABI_ACCEL) {
        $forced = $env:FABI_ACCEL.Trim().ToLowerInvariant()
        if ($forced -notin @("cuda", "directml", "cpu")) {
            throw "FABI_ACCEL invalide pour Windows : $forced (attendu: cuda, directml ou cpu en WSL)"
        }
        return $forced
    }
    if (Test-NvidiaGpu) { return "cuda" }
    return "directml"
}

function Assert-InstallRootIdle {
    param([string]$InstallRoot)

    if (-not (Test-Path -LiteralPath $InstallRoot)) {
        return
    }

    $resolved = (Resolve-Path -LiteralPath $InstallRoot).Path.TrimEnd('\')
    $escaped = [regex]::Escape($resolved)
    $busy = Get-CimInstance Win32_Process | Where-Object {
        ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolved, [System.StringComparison]::OrdinalIgnoreCase)) -or
        ($_.CommandLine -and $_.CommandLine -match $escaped)
    } | Select-Object ProcessId, Name, ExecutablePath, CommandLine

    if ($busy) {
        Write-Err "Installation Fabi active sous $InstallRoot. Arrete les workers/processus Fabi puis relance."
        $busy | ForEach-Object {
            Write-Host "  pid=$($_.ProcessId) name=$($_.Name) exe=$($_.ExecutablePath)" -ForegroundColor Yellow
        }
        exit 1
    }
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
    if ($env:FABI_NO_PATH -eq "1") {
        return
    }
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
    param(
        [string]$PackageRoot,
        [string]$InstallRoot
    )

    $placeholder = "__FABI_INSTALL_ROOT__"
    $manifest = Join-Path $PackageRoot "runtime\relocation-manifest.txt"
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
        $path = Join-Path $PackageRoot $normalized
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

    if ($Accel -eq "cpu") {
        Write-Err "Le runtime CPU Windows natif n'est pas publie; utilise DirectML ou FABI_WINDOWS_MODE=wsl"
        exit 1
    }

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" {
            Write-Err "Windows ARM64 n'est pas encore qualifie pour le runtime Python DirectML Fabi"
            exit 1
        }
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

    Assert-InstallRootIdle -InstallRoot $InstallRoot

    # Keep extraction and activation on the target volume. PowerShell's
    # FileSystem provider moves directories only within one drive; staging in
    # %TEMP% would turn a custom D:\ install into a failing cross-volume move
    # instead of the intended atomic rename transaction.
    $tmpDir = New-InstallTransactionDirectory -InstallRoot $InstallRoot
    try {
        $tarballPath = Join-Path $tmpDir "fabi.tar.zst"
        $dlBase = "https://github.com/${Repo}/releases/download/${Version}"
        # Asset splitte ? release-build.sh publie un manifeste .parts quand le
        # tarball depasse 2 Go (limite GitHub) -> on telecharge les parties et on
        # reassemble (concatenation binaire). Sinon, telechargement direct.
        if ($env:FABI_TARBALL_PATH) {
            if (-not (Test-Path -LiteralPath $env:FABI_TARBALL_PATH -PathType Leaf)) {
                Write-Err "FABI_TARBALL_PATH introuvable : $env:FABI_TARBALL_PATH"
                exit 1
            }
            Write-Log "Archive locale : $env:FABI_TARBALL_PATH"
            Copy-Item -LiteralPath $env:FABI_TARBALL_PATH -Destination $tarballPath -Force
        } else {
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
        }

        $expected = $null
        if ($env:FABI_TARBALL_PATH) {
            $localSha = "$($env:FABI_TARBALL_PATH).sha256"
            if (Test-Path -LiteralPath $localSha -PathType Leaf) {
                $expected = (Get-Content -LiteralPath $localSha -Raw).Trim().Split()[0]
            }
        } else {
            try {
                $expected = (Read-UrlText -Uri $shaUrl).Trim().Split()[0]
            } catch {
                Write-Warn "Pas de fichier .sha256 disponible; verification skippee"
            }
        }
        if ($expected) {
            $actual = (Get-FileHash -Path $tarballPath -Algorithm SHA256).Hash.ToLower()
            if ($expected -ne $actual) {
                Write-Err "SHA256 mismatch. Attendu: $expected, Recu: $actual"
                exit 1
            }
            Write-Ok "Integrite verifiee"
        } else {
            Write-Warn $(if ($env:FABI_TARBALL_PATH) {
                "Archive locale sans sidecar .sha256; verification skippee"
            } else {
                "Somme .sha256 distante indisponible; verification skippee"
            })
        }

        $zstdPath = Get-VerifiedZstd -Repo $Repo -Version $Version -Platform $platform -TmpDir $tmpDir
        $stagingRoot = Join-Path $tmpDir "install"
        New-Item -Type Directory -Path $stagingRoot -Force | Out-Null
        & $zstdPath -q -f -d "$tarballPath" -o (Join-Path $tmpDir "fabi.tar")
        if ($LASTEXITCODE -ne 0) { throw "Echec de decompression du paquet Fabi" }
        & tar.exe -xf (Join-Path $tmpDir "fabi.tar") -C $stagingRoot --strip-components=1
        if ($LASTEXITCODE -ne 0) { throw "Echec d'extraction du paquet Fabi" }

        Relocate-BundledRuntime -PackageRoot $stagingRoot -InstallRoot $InstallRoot

        $fabiBin = Join-Path $stagingRoot "bin\fabi.exe"
        if (-not (Test-Path $fabiBin)) {
            Write-Err "fabi.exe absent apres extraction : $fabiBin"
            exit 1
        }

        $runtimePython = Join-Path $stagingRoot "runtime\parallax-venv\Scripts\python.exe"
        if (-not (Test-Path -LiteralPath $runtimePython -PathType Leaf)) {
            throw "Python runtime absent apres extraction : $runtimePython"
        }

        $managedManifest = Join-Path $stagingRoot ".fabi-managed-paths"
        if (-not (Test-Path -LiteralPath $managedManifest -PathType Leaf)) {
            throw "Manifeste des chemins geres absent : .fabi-managed-paths"
        }
        $managedPaths = @()
        foreach ($line in [System.IO.File]::ReadAllLines($managedManifest)) {
            $managed = $line.Trim()
            if (-not $managed) { continue }
            if ([System.IO.Path]::IsPathRooted($managed) -or $managed -in @(".", "..") -or
                $managed.Contains("/") -or $managed.Contains("\")) {
                throw "Chemin gere invalide : $managed"
            }
            $packagePath = Join-Path $stagingRoot $managed
            if (-not (Test-Path -LiteralPath $packagePath)) {
                throw "Chemin gere absent du paquet : $managed"
            }
            $managedPaths += $managed
        }
        if ($managedPaths.Count -eq 0) {
            throw "Manifeste des chemins geres vide"
        }

        New-Item -Type Directory -Path $InstallRoot -Force | Out-Null
        $backup = "${InstallRoot}.backup-$(Get-Date -Format 'yyyyMMddHHmmssfff')"
        New-Item -Type Directory -Path $backup -Force | Out-Null
        $backupUsed = $false
        try {
            foreach ($managed in $managedPaths) {
                $currentPath = Join-Path $InstallRoot $managed
                if (Test-Path -LiteralPath $currentPath) {
                    Move-Item -LiteralPath $currentPath -Destination (Join-Path $backup $managed)
                    $backupUsed = $true
                }
            }
            foreach ($managed in $managedPaths) {
                Move-Item -LiteralPath (Join-Path $stagingRoot $managed) -Destination (Join-Path $InstallRoot $managed)
            }

            $runtimePython = Join-Path $InstallRoot "runtime\parallax-venv\Scripts\python.exe"
            & $runtimePython -c "from parallax.cli import main as parallax_main; from backend.server.request_agent_frontend import main as request_agent_main"
            if ($LASTEXITCODE -ne 0) {
                throw "Les entrypoints Parallax et Request Agent relocalises ne peuvent pas etre importes"
            }
        } catch {
            Write-Warn "Activation du nouveau runtime echouee; restauration de la version precedente"
            foreach ($managed in $managedPaths) {
                $currentPath = Join-Path $InstallRoot $managed
                Remove-Item -LiteralPath $currentPath -Recurse -Force -ErrorAction SilentlyContinue
                $backupPath = Join-Path $backup $managed
                if (Test-Path -LiteralPath $backupPath) {
                    Move-Item -LiteralPath $backupPath -Destination $currentPath
                }
            }
            throw
        }
        if ($backupUsed) {
            Write-Warn "Ancien runtime sauvegarde dans $backup"
            # Les imports du nouveau runtime ont réussi. Conserver uniquement
            # cette version précédente ; les identités et états V3 ne sont
            # jamais déplacés dans les backups de chemins gérés.
            Remove-StaleRuntimeBackups -InstallRoot $InstallRoot -Keep $backup
        } else {
            Remove-Item -LiteralPath $backup -Force
        }

        Add-ToUserPath (Join-Path $InstallRoot "bin")
        Write-Ok "Fabi $Version installe en mode Windows natif"
    } finally {
        if (Test-Path -LiteralPath $tmpDir) {
            try {
                Remove-ManagedDirectoryTree -Path $tmpDir
            } catch {
                Write-Warn "Impossible de nettoyer le staging $tmpDir : $($_.Exception.Message)"
            }
        }
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
        $wslAccel = if ($accel -eq "directml") { "cpu" } else { $accel }
        Install-WslFabi -Repo $repo -Version $version -Accel $wslAccel -InstallRoot $installRoot
    }
    "native" {
        Install-NativeFabi -Repo $repo -Version $version -Accel $accel -InstallRoot $installRoot
    }
    default {
        Write-Err "FABI_WINDOWS_MODE invalide: $mode (attendu: wsl ou native)"
        exit 1
    }
}
