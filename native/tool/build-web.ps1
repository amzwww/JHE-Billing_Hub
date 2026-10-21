$ErrorActionPreference = 'Stop'

$nativeRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $nativeRoot
$flutter = Join-Path $env:USERPROFILE 'tools\flutter\bin\flutter.bat'
$settings = @{}

if (-not (Test-Path -LiteralPath $flutter)) { throw 'No se encuentra Flutter.' }

Get-Content -LiteralPath (Join-Path $repoRoot '.env') | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { $settings[$matches[1]] = $matches[2].Trim('"') }
}

$supabaseUrl = $settings['VITE_SUPABASE_URL']
$publishableKey = $settings['VITE_SUPABASE_PUBLISHABLE_KEY']
if (-not $supabaseUrl -or -not $publishableKey) {
    throw 'Falta la configuración pública de Supabase en .env.'
}

$defines = @(
    "--dart-define=SUPABASE_URL=$supabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$publishableKey"
)

Push-Location $nativeRoot
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron resolver las dependencias.' }

    & $flutter build web --release --base-href '/JHE-Billing_Hub/' @defines
    if ($LASTEXITCODE -ne 0) { throw 'La compilación web ha fallado.' }

    $webRoot = Join-Path $nativeRoot 'build\web'
    $bootstrapPath = Join-Path $webRoot 'flutter_bootstrap.js'
    $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    $serviceWorkerLoader = '_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{.*?\}\s*\}\);'
    $cleanBootstrap = [regex]::Replace(
        $bootstrap,
        $serviceWorkerLoader,
        '_flutter.loader.load();',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($cleanBootstrap -eq $bootstrap) {
        throw 'No se pudo retirar el registro automático del service worker.'
    }
    [System.IO.File]::WriteAllText(
        $bootstrapPath,
        $cleanBootstrap,
        [System.Text.UTF8Encoding]::new($false)
    )

    $pubspec = Get-Content -LiteralPath (Join-Path $nativeRoot 'pubspec.yaml') -Raw
    if ($pubspec -notmatch '(?m)^version:\s*([^\r\n]+)') {
        throw 'No se pudo leer la versión de pubspec.yaml.'
    }
    $cacheVersion = $matches[1].Trim().Replace('+', '-')
    $indexPath = Join-Path $webRoot 'index.html'
    $index = Get-Content -LiteralPath $indexPath -Raw
    $index = $index.Replace(
        'flutter_bootstrap.js"',
        "flutter_bootstrap.js?v=$cacheVersion`""
    )
    [System.IO.File]::WriteAllText(
        $indexPath,
        $index,
        [System.Text.UTF8Encoding]::new($false)
    )

    New-Item -ItemType File -Path (Join-Path $webRoot '.nojekyll') -Force | Out-Null
    Write-Host "Web preparada en $webRoot sin bucle de service worker."
}
finally {
    Pop-Location
}
