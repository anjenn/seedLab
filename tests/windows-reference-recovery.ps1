# Dot-sourced by ValidateOnWindows.ps1, with isolated files/usage and mocked HTTP only.
$recoveryRoot = Split-Path $PSScriptRoot -Parent
$savedRecoveryTransport = ${function:Invoke-RestMethod}
$savedRecoveryDecoder = ${function:Get-PhotoData}
$savedRecoveryExporter = ${function:Export-ReferenceCandidate}
function New-RecoveryRequest {
    return @{ generationMode = 'reference'; useAi = $true; model = 'gpt-6-luna'; apiKey = 'TEST_KEY_DO_NOT_SAVE'; count = 4;
        references = @(@{ id = 'R001'; path = 'TEST_ONLY_1.jpg' }, @{ id = 'R002'; path = 'TEST_ONLY_2.jpg' });
        referenceMode = 'common'; referenceSearch = $false; referenceTarget = 'TEST_ONLY_TARGET.jpg'; maskSubject = $false; maskBackground = $false;
        fidelity = 85; variation = 70; randomSeed = 12; keywordIds = @('dreamy','rose'); output = $temporary; note = '' }
}
try {
    $script:RecoveryCalls = 0; $script:RecoveryDecodeCalls = 0; $script:RecoveryMode = 'repair'; $script:RecoveryImages = @()
    function Get-PhotoData([string]$Path, [int]$MaxEdge = 1024, [string]$ExpectedHash = '') {
        $script:RecoveryDecodeCalls++
        return 'data:image/jpeg;base64,TEST_ONLY_' + $script:RecoveryDecodeCalls
    }
    function Invoke-RestMethod { param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        $script:RecoveryCalls++
        if ($script:RecoveryCalls -gt 2) { throw 'Unexpected retry or extra API call.' }
        if ($script:RecoveryMode -eq 'network') { throw [Net.WebException]::new('Synthetic network timeout') }
        $wire = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        $images = @($wire.input[1].content | Where-Object { $_.type -eq 'input_image' } | ForEach-Object { $_.image_url })
        if ($script:RecoveryCalls -eq 1) { $script:RecoveryImages = $images }
        else {
            Assert-Regression ($images[0] -eq $script:RecoveryImages[0] -and $images[1] -eq $script:RecoveryImages[1]) 'Recipe did not reuse the analyzed photo snapshot.'
        }
        $index = $(if ($script:RecoveryCalls -eq 1) { 0 } else { 2 })
        $response = $fixture.responses[$index] | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        if ($script:RecoveryMode -eq 'incomplete') {
            $response.status = 'incomplete'; $response | Add-Member -NotePropertyName incomplete_details -NotePropertyValue @{ reason = 'max_output_tokens' }
        } elseif ($script:RecoveryMode -eq 'refused') {
            $response.output = @(@{ type = 'message'; content = @(@{ type = 'refusal'; refusal = 'Test only' }) })
        } elseif ($script:RecoveryCalls -eq 2) {
            $payload = $response.output[0].content[0].text | ConvertFrom-Json
            $recipe = $payload.recipes[0]
            $recipe.curves.ToneCurvePV2012 = @(0,40,20,192,255)
            $recipe.curves.ToneCurvePV2012Red = @(-5,64.5,128,192,280)
            $recipe.curves.ToneCurvePV2012Blue = @(255,192,128,64,0)
            $recipe.values.Contrast2012 = 300; $recipe.subject.exposure = 3
            if ($script:RecoveryMode -eq 'malformed') { $recipe.curves.ToneCurvePV2012 = @(0,64,128,255) }
            $response.output[0].content[0].text = $payload | ConvertTo-Json -Depth 20 -Compress
        }
        return $response
    }
    $r = New-RecoveryRequest; $recovered = Run-Generation $r $recoveryRoot
    Assert-Regression ($script:RecoveryCalls -eq 2 -and $script:RecoveryDecodeCalls -eq 3) 'Recovery called the API again or decoded a photo twice.'
    Assert-Regression (@($recovered.rows).Count -eq 4 -and $r.usageSummary.calls -eq 2 -and $r.usageSummary.inputTokens -eq 2000) 'Recovered export count/usage mismatch.'
    $manifest = Get-Content -LiteralPath (Join-Path $recovered.folder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Regression (@($manifest.repairs).Count -eq 5 -and ($manifest.warnings -join ' ').Contains('자동 보정')) 'Repair audit disappeared between validation and export.'
    Assert-Regression ((Get-Content -LiteralPath (Join-Path $recovered.folder 'analysis.txt') -Raw -Encoding UTF8).Contains('ToneCurvePV2012')) 'Analysis omitted repair details.'
    foreach ($row in $recovered.rows) {
        $x = Read-Xmp (Join-Path $recovered.folder $row.File)
        $ys = @($x.Desc.SelectNodes('crs:ToneCurvePV2012/rdf:Seq/rdf:li', $x.Ns) | ForEach-Object { [int]($_.InnerText.Split(',')[1]) })
        Assert-Regression (($ys -join ',') -eq '0,30,30,192,255') 'Repaired curve was not saved correctly in XMP.'
        Assert-Regression (([double](Get-CrsValue $x $x.Desc 'Contrast2012')) -le 70) 'Global slider bounds were not applied.'
    }
    # Unrecoverable data, refusal, and truncation stop with context and keep usage.
    foreach ($mode in @('malformed','incomplete','refused','network')) {
        $script:RecoveryCalls = 0; $script:RecoveryMode = $mode; $r = New-RecoveryRequest; $message = ''
        try { $null = Run-Generation $r $recoveryRoot } catch { $message = $_.Exception.Message }
        Assert-Regression ($message -and -not $r.runFolder) 'Unusable response reached the exporter.'
        $expectedCalls = $(if ($mode -eq 'malformed') { 2 } else { 1 })
        Assert-Regression ($script:RecoveryCalls -eq $expectedCalls) 'Failed response was automatically retried.'
        if ($mode -ne 'network') { Assert-Regression ($r.usageSummary.calls -eq $expectedCalls -and $r.usageSummary.inputTokens -eq 1000 * $expectedCalls) 'Failure discarded usage.' }
        if ($mode -eq 'malformed') { Assert-Regression ($message.Contains('R001') -and $message.Contains('ToneCurvePV2012')) 'Validation failure lost reference/field context.' }
        if ($mode -eq 'incomplete') { Assert-Regression ($message.Contains('출력 토큰 한도')) 'Truncation did not explain the cause.' }
    }
    # Checkpointed partial exports retain the same repair audit.
    $script:RecoveryMode = 'repair'; $script:RecoveryCalls = 0; $r = New-RecoveryRequest
    $r.cancelPath = Join-Path $temporary 'reference-cancel'; $script:RecoveryCancelPath = $r.cancelPath
    function Export-ReferenceCandidate($Candidate, $Request, $AppRoot, $Target) {
        $meta = & $savedRecoveryExporter $Candidate $Request $AppRoot $Target
        [IO.File]::WriteAllText($script:RecoveryCancelPath, 'cancel'); return $meta
    }
    Expect-RegressionFailure { Run-Generation $r $recoveryRoot }
    $partial = Get-Content -LiteralPath (Join-Path $r.runFolder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Regression ($partial.status -eq 'cancelled' -and $partial.generatedCount -eq 1 -and @($partial.repairs).Count -eq 5) 'Partial reference export lost its repairs.'
    Set-Item Function:Export-ReferenceCandidate $savedRecoveryExporter

    # Real Windows decoder: every reference and target is checked before HTTP.
    Set-Item Function:Get-PhotoData $realPhotoDecoder
    Add-Type -AssemblyName System.Drawing
    $good = Join-Path $temporary 'valid-photo.png'; $bad = Join-Path $temporary 'broken-photo.png'
    $bitmap = [Drawing.Bitmap]::new(32,24)
    try { $bitmap.Save($good, [Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    [IO.File]::WriteAllText($bad, 'Not an image')
    $hash = (Get-FileHash -LiteralPath $good -Algorithm SHA256).Hash
    Assert-Regression ((Get-PhotoData $good 1024 $hash).StartsWith('data:image/jpeg;base64,')) 'Real photo decoding failed.'
    Expect-RegressionFailure { Get-PhotoData $good 1024 'CHANGED_HASH' }
    foreach ($badInput in @('fifth-reference','target','count')) {
        $script:RecoveryCalls = 0; $r = New-RecoveryRequest
        $r.references = @(1..5 | ForEach-Object { @{ id = 'R00' + $_; path = $good; hash = $hash } }); $r.referenceTarget = $good
        if ($badInput -eq 'fifth-reference') { $r.references[4].path = $bad; $r.references[4].hash = '' }
        if ($badInput -eq 'target') { $r.referenceTarget = $bad }
        if ($badInput -eq 'count') { $r.count = [double]::NaN }
        Expect-RegressionFailure { Run-Generation $r $recoveryRoot }
        Assert-Regression ($script:RecoveryCalls -eq 0) 'Bad image/count consumed an API call before preflight.'
    }
    # Failed decodes release file handles; files remain editable/removable.
    [IO.File]::Delete($good); [IO.File]::Delete($bad)
    Write-Host 'PASS: reference curve/slider recovery, audit/partial manifest, no extra calls, image snapshots/preflight, real decoder, structural failures, refusal/truncation/network errors preserve usage.'
} finally {
    Set-Item Function:Invoke-RestMethod $savedRecoveryTransport
    Set-Item Function:Get-PhotoData $savedRecoveryDecoder
    Set-Item Function:Export-ReferenceCandidate $savedRecoveryExporter
}
