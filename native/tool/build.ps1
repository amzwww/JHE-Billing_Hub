param([string]$ReleaseRootOverride = '')

$ErrorActionPreference = 'Stop'
$nativeRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $nativeRoot
$settings = @{}
$flutter = Join-Path $env:USERPROFILE 'tools\flutter\bin\flutter.bat'

if (-not (Test-Path -LiteralPath $flutter)) { throw 'No se encuentra Flutter.' }
if (Get-Process -Name 'bills_maker' -ErrorAction SilentlyContinue) { throw 'Cierra JHE Billing Hub antes de compilar.' }

Get-Content -LiteralPath (Join-Path $repoRoot '.env') | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { $settings[$matches[1]] = $matches[2].Trim('"') }
}
$supabaseUrl = $settings['VITE_SUPABASE_URL']
$publishableKey = $settings['VITE_SUPABASE_PUBLISHABLE_KEY']
if (-not $supabaseUrl -or -not $publishableKey) { throw 'Falta la configuración pública de Supabase en .env.' }

$defines = @("--dart-define=SUPABASE_URL=$supabaseUrl", "--dart-define=SUPABASE_ANON_KEY=$publishableKey")

Push-Location $nativeRoot
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron resolver las dependencias.' }
    & $flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'El análisis de Flutter ha fallado.' }
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Las pruebas de Flutter han fallado.' }
    & $flutter build windows --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'La compilación de Windows ha fallado.' }
    # Publicamos el APK ARM64, que cubre los móviles Android actuales y evita
    # incluir las tres arquitecturas en una sola descarga.
    & $flutter build apk --release --split-per-abi @defines
    if ($LASTEXITCODE -ne 0) { throw 'La compilación de Android ha fallado.' }

    $releaseRoot = if ($ReleaseRootOverride) { $ReleaseRootOverride } else { Join-Path $repoRoot 'releases' }
    if (-not ($releaseRoot -like "$(Join-Path $repoRoot 'releases')*")) { throw 'La carpeta de salida no es segura.' }
    if (Test-Path -LiteralPath $releaseRoot) {
        Get-ChildItem -LiteralPath $releaseRoot -Force | Remove-Item -Recurse -Force
    }
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
    $windowsRelease = Join-Path $releaseRoot 'JHE-Billing-Hub-Windows-native-1.1.24'
    New-Item -ItemType Directory -Path $windowsRelease -Force | Out-Null
    Copy-Item -Path (Join-Path $nativeRoot 'build\windows\x64\runner\Release\*') -Destination $windowsRelease -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $nativeRoot 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk') -Destination (Join-Path $releaseRoot 'JHE-Billing-Hub-Android-native-1.1.24.apk') -Force
}
finally { Pop-Location }
