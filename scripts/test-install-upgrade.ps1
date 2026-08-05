# Regression test for the native-Windows installer managed-path transaction.
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $env:TEMP "fabi-installer-test-$([guid]::NewGuid().ToString())"
$installRoot = Join-Path $testRoot "install"
$fixtureExe = Join-Path $testRoot "fixture.exe"
$zstdHelper = Join-Path $testRoot "fabi-unzstd.exe"

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $utf8)
}

function New-Fixture {
    param([string]$Version, [bool]$ManagedManifest = $true)

    $packageName = "package-$Version"
    $packageRoot = Join-Path $testRoot $packageName
    $archive = Join-Path $testRoot "fabi-$Version.tar.zst"
    New-Item -ItemType Directory -Path (Join-Path $packageRoot "bin") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $packageRoot "runtime\parallax-venv\Scripts") -Force | Out-Null
    Copy-Item $fixtureExe (Join-Path $packageRoot "bin\fabi.exe")
    Copy-Item $fixtureExe (Join-Path $packageRoot "runtime\parallax-venv\Scripts\python.exe")
    Write-Utf8NoBom (Join-Path $packageRoot "runtime\runtime-path.txt") "__FABI_INSTALL_ROOT__\runtime`n"
    Write-Utf8NoBom (Join-Path $packageRoot "runtime\relocation-manifest.txt") "runtime/runtime-path.txt`n"
    Write-Utf8NoBom (Join-Path $packageRoot "MANIFEST") "fabi $Version`n"
    if ($ManagedManifest) {
        Write-Utf8NoBom (Join-Path $packageRoot ".fabi-managed-paths") "bin`nruntime`nMANIFEST`n.fabi-managed-paths`n"
    }
    $tarPath = Join-Path $testRoot "fabi-$Version.tar"
    & tar.exe -cf $tarPath -C $testRoot $packageName
    if ($LASTEXITCODE -ne 0) { throw "fixture tar creation failed" }
    & zstd.exe -q -1 -f $tarPath -o $archive
    if ($LASTEXITCODE -ne 0) { throw "fixture zstd creation failed" }
    return $archive
}

function Invoke-FixtureInstall {
    param([string]$Archive)
    $env:FABI_VERSION = "test"
    $env:FABI_TARBALL_PATH = $Archive
    $env:FABI_INSTALL = $installRoot
    $env:FABI_ACCEL = "cpu"
    $env:FABI_WINDOWS_MODE = "native"
    $env:FABI_ZSTD_PATH = $zstdHelper
    $env:FABI_NO_PATH = "1"
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repoRoot "install.ps1") *> $null
    if ($LASTEXITCODE -ne 0) { throw "fixture install failed with exit code $LASTEXITCODE" }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Add-Type -TypeDefinition @'
public static class FixtureProgram {
    public static int Main(string[] args) { return 0; }
}
'@ -OutputAssembly $fixtureExe -OutputType ConsoleApplication
    Copy-Item -LiteralPath (Get-Command "zstd.exe").Source -Destination $zstdHelper
    $helperHash = (Get-FileHash -LiteralPath $zstdHelper -Algorithm SHA256).Hash.ToLower()
    Write-Utf8NoBom "$zstdHelper.sha256" "$helperHash  fabi-unzstd.exe`n"

    Invoke-FixtureInstall (New-Fixture "first")
    New-Item -ItemType Directory -Path (Join-Path $installRoot "network") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $installRoot "swarm-v3") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $installRoot "trust") -Force | Out-Null
    Write-Utf8NoBom (Join-Path $installRoot "network\worker.key") "stable-identity`n"
    Write-Utf8NoBom (Join-Path $installRoot "swarm-v3\fencing.sqlite3") "fencing-state`n"
    Write-Utf8NoBom (Join-Path $installRoot "trust\root.json") "pinned-root`n"

    Invoke-FixtureInstall (New-Fixture "second")
    if ((Get-Content (Join-Path $installRoot "MANIFEST") -Raw).Trim() -ne "fabi second") {
        throw "new managed runtime was not activated"
    }
    if ((Get-Content (Join-Path $installRoot "network\worker.key") -Raw).Trim() -ne "stable-identity") {
        throw "network identity was not preserved"
    }
    if ((Get-Content (Join-Path $installRoot "swarm-v3\fencing.sqlite3") -Raw).Trim() -ne "fencing-state") {
        throw "fencing state was not preserved"
    }
    if ((Get-Content (Join-Path $installRoot "trust\root.json") -Raw).Trim() -ne "pinned-root") {
        throw "TUF root was not preserved"
    }
    if ((Get-Content (Join-Path $installRoot "runtime\runtime-path.txt") -Raw).Trim() -ne "$installRoot\runtime") {
        throw "runtime was not relocated to its final root"
    }
    if (-not (Get-ChildItem $testRoot -Directory -Filter "install.backup-*")) {
        throw "previous managed runtime backup is missing"
    }

    Invoke-FixtureInstall (New-Fixture "third")
    if ((Get-Content (Join-Path $installRoot "MANIFEST") -Raw).Trim() -ne "fabi third") {
        throw "third managed runtime was not activated"
    }
    $backups = @(Get-ChildItem $testRoot -Directory -Filter "install.backup-*")
    if ($backups.Count -ne 1) {
        throw "expected one retained rollback, got $($backups.Count)"
    }
    if ((Get-Content (Join-Path $backups[0].FullName "MANIFEST") -Raw).Trim() -ne "fabi second") {
        throw "retained rollback is not the immediately previous runtime"
    }

    # Une ancienne sauvegarde peut être verrouillée par Windows (antivirus,
    # indexeur ou processus retardataire). L'installation courante doit quand
    # même réussir, mais son avertissement doit nommer exactement la cible au
    # lieu de perdre le chemin lorsque `$_` devient l'ErrorRecord du catch.
    $lockedBackup = Join-Path $testRoot "install.backup-locked"
    $lockedFile = Join-Path $lockedBackup "locked.bin"
    New-Item -ItemType Directory -Path $lockedBackup -Force | Out-Null
    Write-Utf8NoBom $lockedFile "locked`n"
    $lockedStream = [System.IO.File]::Open(
        $lockedFile,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $env:FABI_TARBALL_PATH = New-Fixture "fourth"
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $cleanupDiagnostics = @(
            & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repoRoot "install.ps1") *>&1
        )
        $cleanupInstallExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        if ($cleanupInstallExitCode -ne 0) {
            throw "upgrade with a locked stale rollback failed with exit code $cleanupInstallExitCode"
        }
        if (($cleanupDiagnostics | Out-String) -notmatch [regex]::Escape($lockedBackup)) {
            throw "locked rollback warning did not preserve its exact path"
        }
        if ((Get-Content (Join-Path $installRoot "MANIFEST") -Raw).Trim() -ne "fabi fourth") {
            throw "upgrade with a locked stale rollback did not activate the new runtime"
        }
    } finally {
        $lockedStream.Dispose()
        Remove-Item -LiteralPath $lockedBackup -Recurse -Force -ErrorAction SilentlyContinue
    }

    $badArchive = New-Fixture "bad" $false
    $before = (Get-Content (Join-Path $installRoot "MANIFEST") -Raw)
    $env:FABI_TARBALL_PATH = $badArchive
    # Windows PowerShell 5 matérialise le stderr du processus enfant comme des
    # ErrorRecord. Cette invocation doit précisément échouer : capture son code
    # sans laisser ErrorActionPreference masquer les assertions de rollback.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repoRoot "install.ps1") *> $null
    $badInstallExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($badInstallExitCode -eq 0) {
        throw "malformed package unexpectedly installed"
    }
    if ((Get-Content (Join-Path $installRoot "MANIFEST") -Raw) -ne $before) {
        throw "malformed package changed the active runtime"
    }

    $validHelperSidecar = Get-Content -LiteralPath "$zstdHelper.sha256" -Raw
    Write-Utf8NoBom "$zstdHelper.sha256" "$('0' * 64)  fabi-unzstd.exe`n"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repoRoot "install.ps1") *> $null
    $tamperedHelperExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    Write-Utf8NoBom "$zstdHelper.sha256" $validHelperSidecar
    if ($tamperedHelperExitCode -eq 0) {
        throw "tampered decompressor unexpectedly accepted"
    }
    if ((Get-Content (Join-Path $installRoot "MANIFEST") -Raw) -ne $before) {
        throw "tampered decompressor changed the active runtime"
    }

    Write-Output "Windows installer upgrade transaction: ok"
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
exit 0
