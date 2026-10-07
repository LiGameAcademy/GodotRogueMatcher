[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [ValidateSet('Release', 'Debug')]
    [string]$BuildMode = 'Release',
    [ValidatePattern('^[a-z0-9_-]+$')]
    [string]$BuildName = ('web_baseline_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
)

$ErrorActionPreference = 'Stop'
[string]$projectRoot = Split-Path $PSScriptRoot -Parent
[string]$productionRoot = Join-Path $projectRoot 'production'
[string]$outputRoot = Join-Path $productionRoot $BuildName
[string]$archivePath = Join-Path $productionRoot ($BuildName + '.zip')
[string]$logPath = Join-Path $productionRoot ($BuildName + '.export.log')
[string]$manifestPath = Join-Path $productionRoot ($BuildName + '.build.json')
if ((Test-Path -LiteralPath $outputRoot) -or (Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $logPath) -or (Test-Path -LiteralPath $manifestPath)) {
    throw 'Build name already exists. Choose a new name to preserve previous artifacts.'
}
[string]$engineVersion = (& $GodotPath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.') {
    throw 'Use Godot 4.7.2 with matching Web export templates for this baseline.'
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if ($BuildMode -eq 'Debug') {
    & $GodotPath --headless --path $projectRoot --export-debug Web (Join-Path $outputRoot 'index.html') *> $logPath
} else {
    & $GodotPath --headless --path $projectRoot --export-release Web (Join-Path $outputRoot 'index.html') *> $logPath
}
[int]$exportCode = $LASTEXITCODE
# Godot may write export errors while returning zero; validate both channels.
if ($exportCode -ne 0 -or (Select-String -LiteralPath $logPath -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet)) {
    throw "Web export failed. See $logPath"
}
foreach ($required in @('index.html', 'index.js', 'index.pck', 'index.wasm')) {
    if (-not (Test-Path -LiteralPath (Join-Path $outputRoot $required) -PathType Leaf)) {
        throw "Missing Web artifact: $required"
    }
}
[string]$licenseRoot = Join-Path $outputRoot 'licenses'
New-Item -ItemType Directory -Path $licenseRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $licenseRoot 'game.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'addons/godot_core_system/LICENSE') -Destination (Join-Path $licenseRoot 'godot_core_system.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/fonts/OFL.txt') -Destination (Join-Path $licenseRoot 'noto_sans_sc.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/fonts/README.md') -Destination (Join-Path $outputRoot 'font_credits.md')
# ZIP contents start at index.html, without an extra enclosing directory.
Compress-Archive -Path (Join-Path $outputRoot '*') -DestinationPath $archivePath
[string]$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[ordered]@{
    engine = $engineVersion
    preset = 'Web'
    mode = "$BuildMode / Compatibility / single-threaded"
    output_directory = $outputRoot
    archive = $archivePath
    sha256 = $archiveHash
    export_log = $logPath
} | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "Web directory: $outputRoot"
Write-Output "ZIP: $archivePath"
Write-Output "SHA256: $archiveHash"
