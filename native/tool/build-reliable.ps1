$ErrorActionPreference = 'Stop'
$nativeRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $nativeRoot
$stageRoot = Join-Path $env:LOCALAPPDATA 'BMB'
$stageNative = Join-Path $stageRoot 'native'
$releaseRoot = Join-Path $repoRoot 'releases'
$expectedPrefix = Join-Path $env:LOCALAPPDATA 'BMB'

if (-not $stageRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'La ruta temporal no es segura.' }
New-Item -ItemType Directory -Path $stageNative -Force | Out-Null
& robocopy $nativeRoot $stageNative /MIR /XD build .dart_tool ephemeral /XF local.properties /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -gt 7) { throw "No se pudo preparar la compilación: $LASTEXITCODE" }
Copy-Item -LiteralPath (Join-Path $repoRoot '.env') -Destination (Join-Path $stageRoot '.env') -Force
& (Join-Path $stageNative 'tool\build.ps1') -ReleaseRootOverride $releaseRoot
if ($LASTEXITCODE -ne 0) { throw 'La compilación aislada ha fallado.' }

$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'
if (Test-Path -LiteralPath $iscc) {
    & $iscc (Join-Path $nativeRoot 'installer\JHE-Billing_Hub.iss')
    if ($LASTEXITCODE -ne 0) { throw 'La creación del instalador ha fallado.' }
}
