$ErrorActionPreference = 'Stop'
$script:TrackingAppRoot = $PSScriptRoot

function Get-UsageDirectory {
    if ($env:SEEDLAB_TEST_USAGE_DIR) { return $env:SEEDLAB_TEST_USAGE_DIR }
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PresetSeedLab'
}
function Write-UsageEvent($Event) {
    $dir = Get-UsageDirectory
    [void][IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir 'usage-events.jsonl'
    # A user-wide mutex prevents interleaved append writes from the UI and jobs.
    $mutex = [Threading.Mutex]::new($false, 'Local\PresetSeedLabUsageWriter')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw '사용 기록 파일을 잠그지 못했습니다.' }
        # Explicit allowlist: never persist credentials, prompts, source photos.
        $safe = @{}
        foreach ($key in @('eventId','kind','runId','timestampUtc','updatedAtUtc','localDate','localTime','model','responseModel','responseId','status','usageKnown','inputTokens','outputTokens','cachedTokens','cacheWriteTokens','reasoningTokens','estimatedUSD','tokenUSD','searchUSD','webSearchCalls','phase','priceDate','serviceTier','durationMs','batchIndex','requestedCount','generatedCount','seedCount','referenceCount','mode','folder')) {
            if ($Event.ContainsKey($key)) { $safe[$key] = $Event[$key] }
        }
        [IO.File]::AppendAllText($path, ($safe | ConvertTo-Json -Compress -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
function Read-UsageEvents {
    $path = Join-Path (Get-UsageDirectory) 'usage-events.jsonl'
    $events = [Collections.Generic.List[object]]::new(); $unreadable = 0
    $mutex = [Threading.Mutex]::new($false, 'Local\PresetSeedLabUsageWriter'); $locked = $false
    try {
        try { $locked = $mutex.WaitOne(2000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw '사용 기록을 읽는 동안 파일이 사용 중입니다.' }
        if (Test-Path -LiteralPath $path) {
            $reader = [IO.StreamReader]::new($path, [Text.Encoding]::UTF8)
            try {
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try { $events.Add(($line | ConvertFrom-Json)) } catch { $unreadable++ }
                }
            } finally { $reader.Dispose() }
        }
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
    return @{ events = @($events.ToArray()); unreadableLines = $unreadable }
}

function New-TrackingBase([string]$EventId, [string]$Kind, [string]$RunId, [string]$Model) {
    $now = Get-Date
    return @{ eventId = $EventId; kind = $Kind; runId = $RunId; model = $Model;
        timestampUtc = $now.ToUniversalTime().ToString('o'); localDate = $now.ToString('yyyy-MM-dd'); localTime = $now.ToString('yyyy-MM-dd HH:mm:ss') }
}
function Get-UsageCost([string]$Model, $Usage, [string]$ServiceTier) {
    $result = Invoke-Engine $script:TrackingAppRoot @{ operation = 'cost'; model = $Model; usage = $Usage; serviceTier = $ServiceTier }
    return $result.estimatedUSD
}

function Record-RunStart($Request) {
    $Request.runId = [Guid]::NewGuid().ToString('N')
    $Request.startedAt = [DateTime]::UtcNow.ToString('o')
    $Request.generatedCount = 0
    $model = $(if ($Request.useAi) { $Request.model } else { 'local' })
    $event = New-TrackingBase ($Request.runId + ':start') 'run_start' $Request.runId $model
    $event.requestedCount = $Request.count; $event.seedCount = $(if ($Request.generationMode -eq 'reference') { 0 } else { @($Request.seeds).Count })
    $event.mode = $(if ($Request.generationMode -eq 'reference') { 'reference' } elseif ($Request.useAi) { 'ai' } else { 'local' })
    if ($Request.generationMode -eq 'reference') { $event.referenceCount = @($Request.references).Count }
    Write-UsageEvent $event
}
function Record-RunFinish($Request, [string]$Status, [string]$Folder = '') {
    if (-not $Request.runId) { return }
    $event = New-TrackingBase ($Request.runId + ':finish') 'run_result' $Request.runId $(if ($Request.useAi) { $Request.model } else { 'local' })
    $event.status = $Status; $event.generatedCount = [int]$Request.generatedCount
    $event.requestedCount = $Request.count; $event.folder = $(if ($Folder) { $Folder } else { $Request.runFolder })
    $event.mode = $(if ($Request.generationMode -eq 'reference') { 'reference' } elseif ($Request.useAi) { 'ai' } else { 'local' })
    $event.durationMs = [Math]::Max(0, ([DateTime]::UtcNow - [DateTime]::Parse($Request.startedAt).ToUniversalTime()).TotalMilliseconds)
    Write-UsageEvent $event
}
function Get-UsageDashboard([string]$AppRoot, $Days, [string]$Model = 'all') {
    $path = Join-Path (Get-UsageDirectory) 'usage-events.jsonl'
    $stamp = $(if (Test-Path -LiteralPath $path) { $file = Get-Item -LiteralPath $path; $file.Length.ToString() + ':' + $file.LastWriteTimeUtc.Ticks } else { 'empty' })
    $today = Get-Date -Format 'yyyy-MM-dd'
    $cacheKey = @($path, $stamp, $today, [string]$Days, $Model) | ConvertTo-Json -Compress
    if ($script:UsageDashboardCache -and $script:UsageDashboardCache.key -eq $cacheKey) { return ($script:UsageDashboardCache.json | ConvertFrom-Json) }
    $ledger = Read-UsageEvents
    $result = Invoke-Engine $AppRoot @{ operation = 'usage'; events = $ledger.events; today = (Get-Date -Format 'yyyy-MM-dd'); days = $Days; model = $Model }
    $result | Add-Member -NotePropertyName unreadableLines -NotePropertyValue $ledger.unreadableLines
    $script:UsageDashboardCache = @{ key = $cacheKey; json = ($result | ConvertTo-Json -Depth 40 -Compress) }
    return $result
}
