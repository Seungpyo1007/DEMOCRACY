[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)+$')]
    [string]$Organization
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$appRoot = Join-Path $repoRoot 'app'

if (-not (Test-Path -LiteralPath $appRoot)) {
    throw "App scaffold not found: $appRoot"
}

$fvmCommand = Get-Command fvm -CommandType Application -ErrorAction SilentlyContinue
$flutterCommand = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue
$useFvm = $null -ne $fvmCommand

if (-not $useFvm -and $null -eq $flutterCommand) {
    throw 'Neither FVM nor Flutter is available. Install FVM or Flutter 3.44.8 first.'
}

function Invoke-FlutterTool {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandArguments
    )

    if ($useFvm) {
        & $fvmCommand.Source flutter @CommandArguments
    }
    else {
        & $flutterCommand.Source @CommandArguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed: $($CommandArguments -join ' ')"
    }
}

function Invoke-DartTool {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandArguments
    )

    if ($useFvm) {
        & $fvmCommand.Source dart @CommandArguments
    }
    else {
        $dartCommand = Get-Command dart -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $dartCommand) {
            throw 'Dart is not available beside the active Flutter SDK.'
        }
        & $dartCommand.Source @CommandArguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Dart command failed: $($CommandArguments -join ' ')"
    }
}

$expectedFlutterVersion = '3.44.8'
$expectedDartVersion = '3.12.2'

Push-Location $appRoot
try {
    $versionJson = Invoke-FlutterTool -CommandArguments @('--version', '--machine')
    $versionPayload = $versionJson | ConvertFrom-Json
    if ($versionPayload.frameworkVersion -ne $expectedFlutterVersion) {
        throw "Expected Flutter $expectedFlutterVersion, found $($versionPayload.frameworkVersion)."
    }
    if ($versionPayload.dartSdkVersion -notlike "$expectedDartVersion*") {
        throw "Expected Dart $expectedDartVersion, found $($versionPayload.dartSdkVersion)."
    }

    $androidMissing = -not (Test-Path -LiteralPath 'android')
    $iosMissing = -not (Test-Path -LiteralPath 'ios')

    if ($androidMissing -or $iosMissing) {
        Invoke-FlutterTool -CommandArguments @(
            'create'
            '--empty'
            '--platforms=android,ios'
            '--org'
            $Organization
            '--project-name'
            'democracy'
            '.'
        )
    }

    Invoke-FlutterTool -CommandArguments @('pub', 'get')
    Invoke-DartTool -CommandArguments @('format', 'lib', 'test')
    Invoke-FlutterTool -CommandArguments @('analyze')
    Invoke-FlutterTool -CommandArguments @('test')
}
finally {
    Pop-Location
}

Write-Output 'Flutter scaffold and baseline verification completed.'
