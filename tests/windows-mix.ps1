# Offline integration of the real WSH mixer, XMP exporter and API accounting.
$mixRoot = Split-Path $PSScriptRoot -Parent
$mixTransport = ${function:Invoke-RestMethod}; $mixExporter = ${function:Export-MixCandidate}
function New-TestMixRequest {
    return @{ generationMode = 'mix'; sources = @(@{ id = $mixA.id; path = $mixA.path; weight = 25.0 }, @{ id = $mixB.id; path = $mixB.path; weight = 75.0 });
        baseId = $mixA.id; mixGroups = @{ tone = 'blend'; color = 'blend'; texture = 'base'; curves = 'blend' }; count = 3; variation = 40; fidelity = 0;
        randomSeed = 19; useAi = $false; output = $temporary; apiKey = 'TEST_MIX_KEY_DO_NOT_SAVE'; model = 'gpt-6-luna'; note = '' }
}
try {
    $x = Read-Xmp $maskPath
    Set-Crs $x.Doc $x.Desc 'Exposure2012' '0'; Set-Crs $x.Doc $x.Desc 'Saturation' '20'
    Set-Crs $x.Doc $x.Desc 'CameraProfile' 'TEST_Profile_A'; Set-Crs $x.Doc $x.Desc 'Temperature' '6200'
    $curve = $x.Doc.CreateElement('crs', 'ToneCurvePV2012', $script:CrsNs); $seq = $x.Doc.CreateElement('rdf', 'Seq', $script:RdfNs)
    foreach ($point in @('0, 12','128, 140','255, 250')) { $li = $x.Doc.CreateElement('rdf', 'li', $script:RdfNs); $li.InnerText = $point; [void]$seq.AppendChild($li) }
    [void]$curve.AppendChild($seq); [void]$x.Desc.AppendChild($curve)
    $aPath = Join-Path $temporary 'Mix A.xmp'; $x.Doc.Save($aPath); $mixA = Get-MixSource $aPath
    $x.Desc.RemoveAttribute('Exposure2012', $script:CrsNs)
    $child = $x.Doc.CreateElement('crs', 'Exposure2012', $script:CrsNs); $child.InnerText = '2'; [void]$x.Desc.AppendChild($child)
    Set-Crs $x.Doc $x.Desc 'Saturation' '-20'; Set-Crs $x.Doc $x.Desc 'CameraProfile' 'TEST_Profile_B'; Set-Crs $x.Doc $x.Desc 'Temperature' '-12'
    $bPath = Join-Path $temporary 'Mix B.xmp'; $x.Doc.Save($bPath); $mixB = Get-MixSource $bPath
    Assert-Regression ($mixB.values.Exposure2012 -eq 2) 'Child-element XMP slider was not read.'
    $script:MixApiCalls = 0
    function Invoke-RestMethod { throw 'Local mix must never call the API.' }
    $r = New-TestMixRequest; $local = Run-Generation $r $mixRoot
    Assert-Regression (@($local.rows).Count -eq 3 -and $local.cost -eq 0 -and $local.inputTokens -eq 0) 'Local mix output/cost mismatch.'
    $original = Read-Xmp $aPath
    foreach ($row in $local.rows) {
        $saved = Read-Xmp (Join-Path $local.folder $row.File)
        Assert-Regression ((Get-CrsValue $saved $saved.Desc 'CameraProfile') -eq 'TEST_Profile_A' -and (Get-CrsValue $saved $saved.Desc 'Temperature') -eq '6200') 'Opaque profile/white balance was mixed.'
        Assert-Regression ($saved.Desc.SelectSingleNode('crs:MaskGroupBasedCorrections', $saved.Ns).OuterXml -eq $original.Desc.SelectSingleNode('crs:MaskGroupBasedCorrections', $original.Ns).OuterXml) 'Base masks changed.'
        Assert-Regression (@($saved.Desc.SelectNodes('crs:ToneCurvePV2012/rdf:Seq/rdf:li', $saved.Ns)).Count -eq 5) 'Mixed curve was not exported.'
    }
    $first = Read-Xmp (Join-Path $local.folder $local.rows[0].File)
    Assert-Regression ([double](Get-CrsValue $first $first.Desc 'Exposure2012') -eq 1.5) 'Weighted blend is wrong.'
    Assert-Regression ((Get-FileHash -LiteralPath $aPath -Algorithm SHA256).Hash -eq $mixA.id -and (Get-FileHash -LiteralPath $bPath -Algorithm SHA256).Hash -eq $mixB.id) 'Original source changed.'
    $manifest = Get-Content -LiteralPath (Join-Path $local.folder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Regression ($manifest.mode -eq 'mix' -and @($manifest.mix.sources).Count -eq 2 -and $manifest.usage.calls -eq 0) 'Mix recipe was not recorded.'
    Assert-Regression (-not ((Get-Content -LiteralPath (Join-Path $local.folder 'manifest.json') -Raw).Contains('TEST_MIX_KEY_DO_NOT_SAVE'))) 'Mix manifest leaked a key.'

    $script:MixApiMode = 'valid'
    function Invoke-RestMethod { param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        $script:MixApiCalls++
        $wire = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        Assert-Regression ($wire.store -eq $false -and $wire.text.format.strict -eq $true) 'Mix request lost structured output or privacy settings.'
        $context = $wire.input[1].content[0].text | ConvertFrom-Json
        Assert-Regression (@($context.presets).Count -eq 2 -and @($wire.input[1].content | Where-Object { $_.type -eq 'input_image' }).Count -eq 0) 'Mix request unexpectedly transmitted photos.'
        $plans = @($context.indexes | ForEach-Object { @{ index = $_; name = 'Test Mix'; reason = 'Warm palette with restrained contrast'; weights = @{ tone = @((20 + $_ * 3), (80 - $_ * 3)); color = @(10,90); texture = @(30,70); curves = @(50,50) } } })
        $response = $fixture.responses[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $response.output[0].content[0].text = $(if ($script:MixApiMode -eq 'malformed') { '{bad' } else { @{ plans = $plans } | ConvertTo-Json -Depth 20 -Compress })
        return $response
    }
    $r = New-TestMixRequest; $r.useAi = $true; $r.count = 8; $r.variation = 100; $r.mixGroups.color = 'base'
    $ai = Run-Generation $r $mixRoot
    Assert-Regression ($script:MixApiCalls -eq 2 -and $r.usageSummary.calls -eq 2 -and @($ai.rows).Count -eq 8) 'AI mix batching failed.'
    $saved = Read-Xmp (Join-Path $ai.folder $ai.rows[0].File)
    Assert-Regression ((Get-CrsValue $saved $saved.Desc 'Saturation') -eq '20') 'AI overrode a locked component.'
    $calls = @((Read-UsageEvents).events | Where-Object { $_.runId -eq $r.runId -and $_.kind -eq 'api' })
    Assert-Regression ($calls[-1].phase -eq 'mix_design' -and $calls[-1].mode -eq 'mix' -and $r.usageSummary.inputTokens -eq 2000) 'AI mix usage lost phase/mode/tokens.'
    $script:MixApiCalls = 0; $script:MixApiMode = 'malformed'; $r = New-TestMixRequest; $r.useAi = $true
    Expect-RegressionFailure { Run-Generation $r $mixRoot }
    Assert-Regression ($script:MixApiCalls -eq 1 -and $r.usageSummary.inputTokens -eq 1000 -and -not $r.runFolder) 'Invalid AI mix response lost usage or silently exported.'
    # A changed input is rejected before any paid request.
    [IO.File]::AppendAllText($bPath, ' '); $r = New-TestMixRequest; $r.useAi = $true; $script:MixApiCalls = 0
    Expect-RegressionFailure { Run-Generation $r $mixRoot }
    Assert-Regression ($script:MixApiCalls -eq 0) 'Changed mix source reached the API.'
    $mixB = Get-MixSource $bPath
    # Partial output retains mixture provenance.
    $r = New-TestMixRequest; $r.cancelPath = Join-Path $temporary 'cancel-mix'; $script:MixCancelPath = $r.cancelPath
    function Export-MixCandidate($Candidate,$Base,$Target) { $name = & $mixExporter $Candidate $Base $Target; [IO.File]::WriteAllText($script:MixCancelPath, 'cancel'); return $name }
    Expect-RegressionFailure { Run-Generation $r $mixRoot }
    $partial = Get-Content -LiteralPath (Join-Path $r.runFolder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Regression ($partial.status -eq 'cancelled' -and $partial.generatedCount -eq 1 -and @($partial.mix.sources).Count -eq 2) 'Cancelled mix lost provenance.'
    $dashboard = Get-UsageDashboard $mixRoot 7 'all'
    Assert-Regression (@($dashboard.runs | Where-Object { $_.Mode -eq '믹스매치' }).Count -ge 2) 'Mix runs were mislabeled.'
    Write-Host 'PASS: local/AI mix, batching and usage, attribute/child sliders, RGB curves, profile/WB/mask preservation, hashes, partial provenance, no local API.'
} finally { Set-Item Function:Invoke-RestMethod $mixTransport; Set-Item Function:Export-MixCandidate $mixExporter }
