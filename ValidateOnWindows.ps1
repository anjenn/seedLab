$ErrorActionPreference = 'Stop'
$previousUsageDir = $env:SEEDLAB_TEST_USAGE_DIR
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('SeedLab-Validation-' + [Guid]::NewGuid().ToString('N'))
$env:SEEDLAB_TEST_USAGE_DIR = Join-Path $temporary 'usage'
try {
    foreach ($name in @('app.ps1', 'functions.ps1', 'tracking.ps1', 'dashboard.ps1', 'api.ps1', 'reference.ps1', 'reference-ui.ps1', 'results-ui.ps1', 'runtime.ps1', 'tests/windows-regressions.ps1', 'ValidateOnWindows.ps1')) {
        $tokens = $null; $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count) { throw ($name + ': ' + ($parseErrors.Message -join '; ')) }
    }
    . (Join-Path $PSScriptRoot 'functions.ps1')
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    [xml]$ui = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ui.xaml'), [Text.Encoding]::UTF8)
    $view = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($ui))
    foreach ($name in @('ReferencePage','RefSubjectGroup','RefBackgroundGroup','UsageCalls','GeneratorForm','ReferenceForm','ReferenceList','ResultsBody','Progress','RunSummary')) { if (-not $view.FindName($name)) { throw ('Missing WPF control ' + $name) } }
    $view.Close()
    $seeds = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'examples') -Filter '*.xmp' | ForEach-Object { Get-Seed $_.FullName })
    if ($seeds.Count -ne 12) { throw 'Missing samples.' }
    $request = @{ seeds = $seeds; count = 24; fidelity = 85; variation = 70; keywordIds = @('dreamy', 'rose', 'cyan');
        useAi = $false; output = $temporary; randomSeed = 23; maskTemplate = ''; varyMasks = $false }
    $result = Run-Generation $request $PSScriptRoot
    if (@($result.rows).Count -ne 24) { throw 'Wrong generated count.' }
    $ids = @{}
    foreach ($row in $result.rows) {
        $x = Read-Xmp (Join-Path $result.folder $row.File)
        $id = $x.Desc.GetAttribute('UUID', $script:CrsNs)
        if ($id -notmatch '^[0-9A-F]{32}$' -or $ids.ContainsKey($id)) { throw 'UUID mismatch.' }; $ids[$id] = $true
        $seed = @($seeds | Where-Object { $_.id -eq $row.Details.seedId })[0]
        $original = Read-Xmp $seed.path
        if ($x.Desc.SelectSingleNode('crs:ToneCurvePV2012', $x.Ns).InnerXml -ne $original.Desc.SelectSingleNode('crs:ToneCurvePV2012', $original.Ns).InnerXml) { throw 'Tone curve was altered.' }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $result.folder 'manifest.json') -Raw -Encoding UTF8
    if ($manifest -match 'apiKey|Bearer|sk-proj') { throw 'Unexpected credential field.' }
    $e = New-TrackingBase 'test-call' 'api' 'test-run' 'gpt-6-luna'
    $e.status = 'pending'; $e.usageKnown = $false; $e.apiKey = 'DO_NOT_RECORD_THIS'
    Write-UsageEvent $e
    $e.status = 'completed'; $e.usageKnown = $true; $e.inputTokens = 8000; $e.outputTokens = 4000
    $e.cachedTokens = 2000; $e.reasoningTokens = 1000
    $e.estimatedUSD = Get-UsageCost 'gpt-6-luna' @{ input_tokens = 8000; output_tokens = 4000; input_tokens_details = @{ cached_tokens = 2000 } } 'default'
    Write-UsageEvent $e; Write-UsageEvent $e
    $dashboard = Get-UsageDashboard $PSScriptRoot 7 'all'
    if ($dashboard.totals.calls -ne 1 -or $dashboard.totals.totalTokens -ne 12000 -or $dashboard.totals.runs -ne 1) { throw 'Usage deduplication / aggregation failed.' }
    $ledgerPath = Join-Path (Get-UsageDirectory) 'usage-events.jsonl'
    if ([IO.File]::ReadAllText($ledgerPath).Contains('DO_NOT_RECORD_THIS')) { throw 'Credential allowlist failed.' }
    # Test-only synthetic mask data exercises preservation, not Lightroom compatibility.
    $fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tests/reference-fixtures.json') -Encoding UTF8 -Raw | ConvertFrom-Json
    $template = Read-Xmp (Join-Path $PSScriptRoot 'reference-base.xmp')
    $block = $template.Doc.CreateElement('crs', 'MaskGroupBasedCorrections', $script:CrsNs); $seq = $template.Doc.CreateElement('rdf', 'Seq', $script:RdfNs)
    foreach ($kind in @('Subject','Background')) {
        $li = $template.Doc.CreateElement('rdf', 'li', $script:RdfNs); $node = $template.Doc.CreateElement('rdf', 'Description', $script:RdfNs)
        Set-Crs $template.Doc $node 'CorrectionName' $kind; Set-Crs $template.Doc $node 'What' 'Correction'
        Set-Crs $template.Doc $node 'LocalContrast2012' '0.43'; Set-Crs $template.Doc $node 'LocalLuminanceNoise' '0.12'
        $masks = $template.Doc.CreateElement('crs', 'CorrectionMasks', $script:CrsNs); $maskSeq = $template.Doc.CreateElement('rdf', 'Seq', $script:RdfNs); $maskLi = $template.Doc.CreateElement('rdf', 'li', $script:RdfNs)
        Set-Crs $template.Doc $maskLi 'What' 'Mask/Image'; Set-Crs $template.Doc $maskLi 'MaskName' ('TEST ONLY ' + $kind)
        Set-Crs $template.Doc $maskLi 'MaskSyncID' ('TEST_ONLY_' + $kind); Set-Crs $template.Doc $maskLi 'MaskInverted' 'false'
        [void]$maskSeq.AppendChild($maskLi); [void]$masks.AppendChild($maskSeq); [void]$node.AppendChild($masks); [void]$li.AppendChild($node); [void]$seq.AppendChild($li)
    }
    [void]$block.AppendChild($seq); [void]$template.Desc.AppendChild($block)
    $maskPath = Join-Path $temporary 'TEST_ONLY_masks.xmp'; $template.Doc.Save($maskPath)
    # Mock the HTTP transport and image decoder; all orchestration, usage,
    # JSON contract validation, WSH and XMP exporters below are real code.
    $script:MockResponseIndex = 0; $script:MockResponses = @($fixture.responses)
    function Invoke-RestMethod { param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        if ($script:MockResponseIndex -ge $script:MockResponses.Count) { throw 'Unexpected API call in offline validation.' }
        $response = $script:MockResponses[$script:MockResponseIndex]; $script:MockResponseIndex++; return $response
    }
    function Get-PhotoData([string]$Path, [int]$MaxEdge = 1024) { return 'data:image/jpeg;base64,TEST_ONLY' }
    $referenceRequest = @{ generationMode = 'reference'; useAi = $true; model = 'gpt-6-luna'; apiKey = 'TEST_KEY_DO_NOT_SAVE'; count = 4;
        references = @(@{ id = 'R001'; path = 'TEST_ONLY_1.jpg' }, @{ id = 'R002'; path = 'TEST_ONLY_2.jpg' }); referenceMode = 'common'; referenceSearch = $true; referenceTarget = '';
        referenceMaskTemplate = $maskPath; referenceMaskHash = (Get-FileHash -LiteralPath $maskPath -Algorithm SHA256).Hash; maskSubject = $true; maskBackground = $true;
        subjectMaskIndex = 0; backgroundMaskIndex = 1; fidelity = 85; variation = 70; randomSeed = 12; keywordIds = @('dreamy','rose'); output = $temporary; note = '' }
    $refResult = Run-Generation $referenceRequest $PSScriptRoot
    if ($script:MockResponseIndex -ne 3 -or @($refResult.rows).Count -ne 4) { throw 'Reference pipeline call/output count mismatch.' }
    $first = Read-Xmp (Join-Path $refResult.folder $refResult.rows[0].File); $groups = @(Get-ReferenceMaskGroups $first)
    if ($groups.Count -ne 2) { throw 'Reference masks were not exported.' }
    if ([Math]::Abs([double](Get-CrsValue $first $groups[0].Node 'LocalExposure2012') - 0.075) -gt 0.0001) { throw 'Local exposure EV/4 scaling failed.' }
    if ([Math]::Abs([double](Get-CrsValue $first $groups[0].Node 'LocalTemperature') - 0.12) -gt 0.0001) { throw 'Subject XMP scaling failed.' }
    if ([Math]::Abs([double](Get-CrsValue $first $groups[1].Node 'LocalTemperature') + 0.2) -gt 0.0001) { throw 'Background XMP scaling failed.' }
    if ([double](Get-CrsValue $first $groups[0].Node 'LocalLuminanceNoise') -ne 0) { throw 'Inherited correction was not neutralized.' }
    $dashboard = Get-UsageDashboard $PSScriptRoot 7 'all'
    if ($dashboard.totals.calls -ne 4 -or $dashboard.totals.totalTokens -ne 16500 -or $dashboard.totals.webSearchCalls -ne 1 -or $dashboard.totals.referenceRuns -ne 1) { throw 'Reference token/search accounting mismatch.' }
    $manifest = Get-Content -LiteralPath (Join-Path $refResult.folder 'manifest.json') -Raw -Encoding UTF8
    if ($manifest -match 'apiKey|TEST_KEY_DO_NOT_SAVE|data:image') { throw 'Unexpected credentials/image data in manifest.' }
    if ([IO.File]::ReadAllText($ledgerPath).Contains('TEST_KEY_DO_NOT_SAVE')) { throw 'Reference key was persisted.' }
    . (Join-Path $PSScriptRoot 'tests/windows-regressions.ps1')
    Write-Host 'PASS: PS/WPF loading, WSH, seed XMPs, offline reference pipeline, subject/background mask preservation and normalization, token/search usage.' -ForegroundColor Green
    Write-Host 'No API request was made. Lightroom import remains a separate check.'
    exit 0
} catch { Write-Host ('FAIL: ' + $_.Exception.Message + "`n" + $_.ScriptStackTrace) -ForegroundColor Red; exit 1 }
finally { $env:SEEDLAB_TEST_USAGE_DIR = $previousUsageDir; if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force } }
