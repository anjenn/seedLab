# Dot-sourced by ValidateOnWindows.ps1. Every write uses its isolated temporary directory.
function Assert-Regression([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Expect-RegressionFailure([scriptblock]$Action) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert-Regression $failed 'Expected a rejected operation.'
}
function New-TestSeedRequest {
    return @{ seeds = $seeds; count = 1; fidelity = 85; variation = 70; keywordIds = @('dreamy'); useAi = $true;
        model = 'gpt-6-luna'; apiKey = 'TEST_KEY_DO_NOT_SAVE'; output = $temporary; randomSeed = 23; maskTemplate = ''; varyMasks = $false }
}
$root = Split-Path $PSScriptRoot -Parent
$transport = ${function:Invoke-RestMethod}
$exporter = ${function:Export-Candidate}
try {
    # A mutation is rejected before the first paid request.
    $copyPath = Join-Path $temporary 'changed.xmp'; Copy-Item -LiteralPath $seeds[0].path -Destination $copyPath
    $copySeed = Get-Seed $copyPath
    [IO.File]::AppendAllText($copyPath, ' ')
    $r = New-TestSeedRequest; $r.seeds = @($copySeed)
    $before = $script:MockResponseIndex
    Expect-RegressionFailure { Run-Generation $r $root }
    Assert-Regression ($script:MockResponseIndex -eq $before) 'Changed seed reached the API.'

    # Validation failures never leave an importable .xmp, and existing files are not overwritten.
    $atomic = Join-Path $temporary 'atomic.xmp'; $x = Read-Xmp $seeds[0].path
    Expect-RegressionFailure { Save-VerifiedXmp $x $atomic { throw 'Synthetic validation failure' } }
    Assert-Regression (-not [IO.File]::Exists($atomic)) 'Invalid XMP was published.'
    [IO.File]::WriteAllText($atomic, 'keep-existing')
    Expect-RegressionFailure { Save-VerifiedXmp $x $atomic {} }
    Assert-Regression ([IO.File]::ReadAllText($atomic) -eq 'keep-existing') 'An existing file was overwritten.'
    Assert-Regression (@(Get-ChildItem -LiteralPath $temporary -Filter 'atomic.xmp.*.tmp').Count -eq 0) 'Staging file leaked.'

    # Shared transport: seed and reference calls both record usage before parsing.
    $script:RegressionResponse = $fixture.responses[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $script:RegressionMode = 'success'; $script:RegressionCalls = 0; $script:RegressionCancelPath = ''
    function Invoke-RestMethod { param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        $script:RegressionCalls++
        $wire = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        Assert-Regression ($wire.store -eq $false -and $wire.input[0].role -eq 'developer') 'Request contract changed.'
        Assert-Regression (-not ([Text.Encoding]::UTF8.GetString($Body).Contains('TEST_KEY_DO_NOT_SAVE'))) 'Credential serialized in request JSON.'
        $context = $wire.input[1].content[0].text | ConvertFrom-Json
        $plans = @($context.assignments | ForEach-Object {
            $axes = @{}; foreach ($axis in @('exposure','contrast','softness','warmth','magenta','saturation','shadowLift','red','green','blue','grain')) { $axes[$axis] = 0.2 }
            @{ index = $_.index; reason = 'Test direction'; axes = $axes }
        })
        $script:RegressionResponse.output[0].content[0].text = $(if ($script:RegressionMode -eq 'malformed') { '{bad' } else { @{ plans = $plans } | ConvertTo-Json -Depth 10 -Compress })
        if ($script:RegressionCancelPath) { [IO.File]::WriteAllText($script:RegressionCancelPath, 'cancel') }
        return $script:RegressionResponse
    }
    $r = New-TestSeedRequest; $aiResult = Run-Generation $r $root
    Assert-Regression (@($aiResult.rows).Count -eq 1 -and $r.usageSummary.calls -eq 1) 'Seed shared API flow failed.'
    $script:RegressionMode = 'malformed'; $r = New-TestSeedRequest
    Expect-RegressionFailure { Run-Generation $r $root }
    $event = @((Read-UsageEvents).events | Where-Object { $_.runId -eq $r.runId -and $_.kind -eq 'api' } | Select-Object -Last 1)[0]
    Assert-Regression ($event.usageKnown -and $event.inputTokens -eq 1000 -and $event.phase -eq 'seed_variation') 'Malformed output lost paid usage.'

    # Cancellation while a response is in flight retains tokens and stops further work.
    $script:RegressionMode = 'success'; $r = New-TestSeedRequest
    $r.cancelPath = Join-Path $temporary 'cancel-during-http'; $script:RegressionCancelPath = $r.cancelPath
    Expect-RegressionFailure { Run-Generation $r $root }
    $events = @((Read-UsageEvents).events | Where-Object { $_.runId -eq $r.runId })
    Assert-Regression ($events[-1].status -eq 'cancelled' -and $r.usageSummary.inputTokens -eq 1000) 'Cancellation lost usage or status.'
    Assert-Regression (-not $r.runFolder) 'Cancelled HTTP response proceeded to export.'
    $script:RegressionCancelPath = ''

    # Stop between exports: both manifest and ledger retain the completed file and its location.
    $script:CancelExportRequest = New-TestSeedRequest; $script:CancelExportRequest.useAi = $false; $script:CancelExportRequest.count = 4
    $script:CancelExportRequest.cancelPath = Join-Path $temporary 'cancel-during-export'
    $script:RealRegressionExporter = $exporter
    function Export-Candidate($Candidate, $Seed, $Target, $MaskTemplate, $VaryMasks, $MaskHash) {
        $meta = & $script:RealRegressionExporter $Candidate $Seed $Target $MaskTemplate $VaryMasks $MaskHash
        [IO.File]::WriteAllText($script:CancelExportRequest.cancelPath, 'cancel')
        return $meta
    }
    Expect-RegressionFailure { Run-Generation $script:CancelExportRequest $root }
    $r = $script:CancelExportRequest
    $partial = Get-Content -LiteralPath (Join-Path $r.runFolder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Regression ($partial.status -eq 'cancelled' -and $partial.generatedCount -eq 1 -and @($partial.variants).Count -eq 1) 'Partial manifest was lost.'
    $last = @((Read-UsageEvents).events | Where-Object { $_.runId -eq $r.runId } | Select-Object -Last 1)[0]
    Assert-Regression ($last.folder -eq $r.runFolder -and $last.generatedCount -eq 1) 'Partial ledger location/count was lost.'

    # Warm dashboard refresh does not invoke WSH, and returned objects are isolated from UI decoration.
    $cold = Get-UsageDashboard $root 7 'all'; $savedEngine = ${function:Invoke-Engine}
    try {
        function Invoke-Engine { throw 'Cache unexpectedly invoked WSH.' }
        $cold.calls[0] | Add-Member -NotePropertyName TestDecoration -NotePropertyValue 'UI only'
        $warm = Get-UsageDashboard $root 7 'all'
        Assert-Regression ($warm.totals.totalTokens -eq $cold.totals.totalTokens -and -not $warm.calls[0].TestDecoration) 'Dashboard cache changed totals or leaked UI state.'
    } finally { Set-Item Function:Invoke-Engine $savedEngine }
    $more = New-TrackingBase 'cache-invalidation' 'api' 'cache-test' 'gpt-6-luna'; $more.status = 'pending'; $more.usageKnown = $false
    Write-UsageEvent $more
    $fresh = Get-UsageDashboard $root 7 'all'
    Assert-Regression ($fresh.totals.calls -eq $cold.totals.calls + 1) 'Dashboard did not invalidate after an append.'
    Write-Host 'PASS: mutation preflight, atomic XMP, seed shared API, malformed-output usage, cancellation during HTTP/export, partial recovery, dashboard cache.'
} finally {
    Set-Item Function:Invoke-RestMethod $transport
    Set-Item Function:Export-Candidate $exporter
}
