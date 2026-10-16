function Write-AtomicJson([string]$Path, $Value) {
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 60), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, ($temporary + '.bak')) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($temporary + '.bak')) { [IO.File]::Delete($temporary + '.bak') }
    }
}

function Test-GenerationCancelled($Request) {
    if ($Request.cancelPath -and [IO.File]::Exists($Request.cancelPath)) {
        throw [OperationCanceledException]::new('사용자가 생성을 중지했습니다. 확인된 사용량과 저장된 결과는 보존됩니다.')
    }
}

function Set-GenerationProgress($Request, [string]$Phase, [int]$Done = 0, [int]$Total = 0) {
    Test-GenerationCancelled $Request
    $percent = $(if ($Total -gt 0) { [Math]::Min(100, [int](100 * $Done / $Total)) } else { -1 })
    Write-Progress -Activity 'Preset Seed Lab' -Status $Phase -PercentComplete $percent
}

function Save-PartialManifest($Request, [string]$Status) {
    if (-not $Request.runFolder) { return }
    $manifest = @{ version = '1.4.0'; runId = $Request.runId; status = $Status; createdAt = $Request.startedAt;
        mode = $(if ($Request.generationMode -eq 'mix') { 'mix' } elseif ($Request.generationMode -eq 'reference') { 'reference' } elseif ($Request.useAi) { 'ai' } else { 'local' });
        requestedCount = $Request.count; generatedCount = $Request.generatedCount; randomSeed = $Request.randomSeed;
        fidelity = $Request.fidelity; variation = $Request.variation; keywordIds = $Request.keywordIds;
        variants = @($Request.exportedRows.ToArray()); usage = $Request.usageSummary;
        mix = $Request.mix; masks = $Request.masks; repairs = @($Request.repairs); warnings = @($Request.generationWarnings) }
    Write-AtomicJson (Join-Path $Request.runFolder 'manifest.json') $manifest
}

function Initialize-Export($Request, [string]$Folder, $Rows) {
    $Request.runFolder = $Folder; $Request.exportedRows = $Rows
    Save-PartialManifest $Request 'exporting'
    Record-RunFinish $Request 'exporting' $Folder
}

function Complete-ExportedCandidate($Request) {
    $Request.generatedCount = $Request.exportedRows.Count
    Save-PartialManifest $Request 'exporting'
    Record-RunFinish $Request 'exporting' $Request.runFolder
}

function Save-VerifiedXmp($X, [string]$Target, [scriptblock]$Validate) {
    $temporary = $Target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $settings = [Xml.XmlWriterSettings]::new(); $settings.Encoding = [Text.UTF8Encoding]::new($false); $settings.Indent = $true
        $writer = [Xml.XmlWriter]::Create($temporary, $settings)
        try { $X.Doc.Save($writer) } finally { $writer.Dispose() }
        $check = Read-Xmp $temporary
        & $Validate $check
        # Never replace an existing preset. Only fully validated files receive .xmp.
        [IO.File]::Move($temporary, $Target)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
