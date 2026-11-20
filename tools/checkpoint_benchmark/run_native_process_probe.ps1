param(
    [Parameter(Mandatory)][string]$Godot,
    [ValidateSet('normal','partial','backup','primary')][string]$Phase = 'normal',
    [ValidateSet('input','reward')][string]$Point = 'input',
    [Parameter(Mandatory)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$enginePath = (Resolve-Path -LiteralPath $Godot).Path
$caseId = $Point + '-' + $Phase + '-' + [guid]::NewGuid().ToString('N').Substring(0,12)
$evidenceRoot = [IO.Path]::GetFullPath($EvidenceDirectory)
[IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
$caseDirectory = Join-Path $evidenceRoot $caseId
[IO.Directory]::CreateDirectory($caseDirectory) | Out-Null
$previousAppData = $env:APPDATA
# Keep the isolated Windows user/cache path short enough for nested shader-cache hashes.
$env:APPDATA = [IO.Path]::GetFullPath((Join-Path $evidenceRoot '../../np'))
[IO.Directory]::CreateDirectory($env:APPDATA) | Out-Null

function Start-Probe([string]$Mode) {
    $arguments = @('--path', ('"' + $projectDirectory + '"'), '--resolution','1280x720',
        '--max-fps','60','--verbose','-s','tools/checkpoint_benchmark/checkpoint_native_process_probe.gd',
        '--',$caseId,$Mode, $(if ($Phase -eq 'normal') {'none'} else {$Phase}),$Point)
    return Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Normal -PassThru `
        -RedirectStandardOutput (Join-Path $caseDirectory "$Mode-stdout.log") `
        -RedirectStandardError (Join-Path $caseDirectory "$Mode-stderr.log")
}

function Wait-Probe($Process, [string]$Mode) {
    $exitDeadline = [DateTime]::UtcNow.AddSeconds(150)
    while (!$Process.WaitForExit(200) -and [DateTime]::UtcNow -lt $exitDeadline) {}
    if (!$Process.HasExited) { throw "Probe timeout: owned PID $($Process.Id), mode $Mode" }
    $Process.Refresh()
    if ($Process.ExitCode -ne 0) { throw "Probe exited $($Process.ExitCode): PID $($Process.Id), mode $Mode" }
    $reportPath = Join-Path $projectDirectory ".godot/$caseId-$Mode-report.json"
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.error -or $report.normal_exit_signal -ne 'window_close_requested') { throw "Failed report: $reportPath" }
    if ($Mode -eq 'restore' -and (!$report.snapshot_equal -or !$report.next_snapshot_equal -or !$report.pair_before_play_equal)) {
        throw 'Restored endpoint/next command/pair failed'
    }
}

function Get-OwnedDataDirectory {
    $receiptPath = Join-Path $projectDirectory ".godot/$caseId-receipt.json"
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $userDirectory = [IO.Path]::GetFullPath($receipt.user_directory)
    $appDataPrefix = [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\') + '\'
    if (!$userDirectory.StartsWith($appDataPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'User-data directory outside isolated APPDATA' }
    return Join-Path $userDirectory "process-checkpoint-probe/$caseId"
}

try {
    $mode = if ($Phase -eq 'normal') {'normal'} else {'kill'}
    $writer = Start-Probe $mode
    if ($mode -eq 'normal') {
        Wait-Probe $writer 'normal'
    } else {
        $readyPath = Join-Path $projectDirectory ".godot/$caseId-ready.json"
        $deadline = [DateTime]::UtcNow.AddSeconds(150)
        while (!(Test-Path -LiteralPath $readyPath) -and [DateTime]::UtcNow -lt $deadline -and !$writer.HasExited) {
            Start-Sleep -Milliseconds 100
            $writer.Refresh()
        }
        if (!(Test-Path -LiteralPath $readyPath)) { throw "Missing ready receipt for owned PID $($writer.Id)" }
        $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
        $owned = Get-Process -Id $writer.Id
        if ($ready.pid -ne $writer.Id -or $ready.phase -ne $Phase -or [IO.Path]::GetFullPath($owned.Path) -ne $enginePath) {
            throw 'PID, executable or phase mismatch; no process terminated'
        }
        Stop-Process -Id $writer.Id -Force
        if (!$writer.WaitForExit(5000)) { throw 'Owned process did not terminate' }
        @{pid=$writer.Id;phase=$Phase;host_forced=$true;utc=[DateTime]::UtcNow.ToString('o')} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $caseDirectory 'host-kill.json')
        Copy-Item -LiteralPath (Join-Path (Get-OwnedDataDirectory) 'slot') -Destination (Join-Path $caseDirectory 'killed-slot') -Recurse
    }
    $restored = Start-Probe 'restore'
    Wait-Probe $restored 'restore'
    Copy-Item -LiteralPath (Get-OwnedDataDirectory) -Destination (Join-Path $caseDirectory 'user-data') -Recurse
    @{case=$caseId;writer_pid=$writer.Id;restore_pid=$restored.Id;phase=$Phase;ok=$true} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $caseDirectory 'host-result.json')
} finally {
    # Preserve every receipt, including failures; never remove the isolated slot or raw log tails.
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory '.godot') -Filter "$caseId-*.json" |
        Copy-Item -Destination $caseDirectory
    $env:APPDATA = $previousAppData
}
Write-Output "NATIVE_PROCESS_EVIDENCE $caseDirectory"
