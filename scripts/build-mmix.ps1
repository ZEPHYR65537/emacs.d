param(
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [string]$InstallDirectory = (Join-Path $PSScriptRoot '../pkg/mmix')
)
$ErrorActionPreference = 'Stop'
$mmixSource = (Resolve-Path -LiteralPath $SourceDirectory).Path
$mmixInstall = [IO.Path]::GetFullPath($InstallDirectory)
foreach ($tool in @('gcc', 'ctangle')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' is missing from PATH."
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $mmixSource 'mmix-sim.w'))) {
    throw 'SourceDirectory must contain the MMIXware sources.'
}
Push-Location -LiteralPath $mmixSource
try {
    foreach ($unit in @('mmix-arith','mmix-io','mmix-sim','mmixal','mmotype','abstime')) {
        & ctangle "$unit.w"
        if ($LASTEXITCODE -ne 0) { throw "ctangle failed for $unit" }
    }
    & gcc -std=gnu17 -O2 -o abstime.exe abstime.c
    if ($LASTEXITCODE -ne 0) { throw 'abstime build failed' }
    & ./abstime.exe | Set-Content -Encoding ascii abstime.h
    if ($LASTEXITCODE -ne 0) { throw 'abstime execution failed' }
    & gcc -std=gnu17 -O2 -o mmix.exe mmix-sim.c mmix-arith.c mmix-io.c
    if ($LASTEXITCODE -ne 0) { throw 'mmix build failed' }
    & gcc -std=gnu17 -O2 -o mmixal.exe mmixal.c mmix-arith.c
    if ($LASTEXITCODE -ne 0) { throw 'mmixal build failed' }
    & gcc -std=gnu17 -O2 -o mmotype.exe mmotype.c
    if ($LASTEXITCODE -ne 0) { throw 'mmotype build failed' }
    New-Item -ItemType Directory -Path $mmixInstall -Force | Out-Null
    foreach ($program in @('mmix.exe','mmixal.exe','mmotype.exe')) {
        Copy-Item -LiteralPath (Join-Path $mmixSource $program) -Destination $mmixInstall -Force
    }
    Write-Output "Installed native MMIX tools in $mmixInstall"
} finally {
    Pop-Location
}
