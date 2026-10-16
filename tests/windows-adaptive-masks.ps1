# Runs with the isolated files and offline fixtures in ValidateOnWindows.ps1.
$maskCore = @{ operation = 'reference_generate'; referenceIds = @($fixture.referenceIds); referenceMode = 'common'; recipes = @($fixture.recipes); count = 1; fidelity = 85; variation = 60; randomSeed = 21; keywordIds = @() }
$maskCandidate = (Invoke-Engine $appRoot $maskCore).candidates[0]
$maskIds = @{}
foreach ($flags in @(@($true,$true),@($true,$false),@($false,$true),@($false,$false))) {
    $request = @{ generationMode = 'reference'; referenceMaskMode = 'automatic'; maskSubject = $flags[0]; maskBackground = $flags[1] }
    Test-ReferenceMaskTemplate $request
    $file = Join-Path $temporary ('auto-' + [Guid]::NewGuid().ToString('N') + '.xmp')
    $null = Export-ReferenceCandidate $maskCandidate $request $appRoot $file
    $x = Read-Xmp $file; $groups = @(Get-ReferenceMaskGroups $x)
    Assert-Regression ($groups.Count -eq ([int]$flags[0] + [int]$flags[1])) 'Automatic mask enable flags were ignored.'
    foreach ($group in $groups) {
        $selector = $group.Node.SelectSingleNode('crs:CorrectionMasks/rdf:Seq/rdf:li', $x.Ns)
        Assert-Regression ($selector.GetAttribute('MaskSubType', $script:CrsNs) -eq '1' -and $selector.GetAttribute('What', $script:CrsNs) -eq 'Mask/Image') 'Wrong automatic selector type.'
        $background = $group.Name -like '배경*'
        Assert-Regression ($selector.GetAttribute('MaskInverted', $script:CrsNs) -eq $background.ToString().ToLowerInvariant()) 'Background was not the inverse subject.'
        foreach ($id in @($selector.GetAttribute('MaskSyncID', $script:CrsNs), (Get-CrsValue $x $group.Node 'CorrectionSyncID'))) {
            Assert-Regression ($id -match '^[A-F0-9]{32}$' -and -not $maskIds.ContainsKey($id)) 'Generated mask IDs were not unique.'; $maskIds[$id] = $true
        }
        Assert-Regression (-not $selector.HasAttribute('MaskDigest', $script:CrsNs) -and -not $selector.HasAttribute('InputDigest', $script:CrsNs)) 'An image-specific selection was fabricated.'
        $encoded = $(if ($background) { $maskCandidate.encodedBackground } else { $maskCandidate.encodedSubject })
        foreach ($value in $encoded.PSObject.Properties) { Assert-Regression ([Math]::Abs([double](Get-CrsValue $x $group.Node $value.Name) - [double]$value.Value) -lt 0.0001) 'Mask recipe units changed.' }
    }
}
Assert-Regression ((Get-ReferenceMaskMode @{ maskSubject = $true; referenceMaskTemplate = $maskPath }) -eq 'template') 'Legacy template request changed behavior.'
foreach ($bad in @(@{ maskSubject = $true; referenceMaskMode = 'invalid' }, @{ maskSubject = $true; referenceMaskMode = 'template'; referenceMaskTemplate = '' })) {
    $rejected = $false; try { Test-ReferenceMaskTemplate $bad } catch { $rejected = $true }; Assert-Regression $rejected 'Invalid mask configuration was accepted.'
}
$invalid = $false; try { $x = Read-Xmp $seeds[0].path; $null = New-AdaptiveMaskGroup $x 'Subject' @{ LocalExposure2012 = [double]::NaN } } catch { $invalid = $true }
Assert-Regression $invalid 'Nonfinite generated mask values were accepted.'
# Append to existing masks; no imported selection or unrelated base setting is rewritten.
$maskedSeed = Get-Seed $maskPath; $original = Read-Xmp $maskPath; $originalGroups = @(Get-ReferenceMaskGroups $original)
$seedCandidate = (Invoke-Engine $appRoot @{ operation = 'generate'; seeds = @($seeds[0]); count = 1; fidelity = 85; variation = 70; randomSeed = 22; keywordIds = @('soft') }).candidates[0]
$withMasks = Join-Path $temporary 'existing-and-auto.xmp'
$null = Export-Candidate $seedCandidate $maskedSeed $withMasks '' $false '' $true $true
$saved = Read-Xmp $withMasks; $groups = @(Get-ReferenceMaskGroups $saved)
Assert-Regression ($groups.Count -eq $originalGroups.Count + 2) 'Automatic masks replaced imported masks.'
for ($i = 0; $i -lt $originalGroups.Count; $i++) { Assert-Regression ($groups[$i].Node.OuterXml -eq $originalGroups[$i].Node.OuterXml) 'An existing mask changed.' }
# Real local pipeline: no AI key, no additional paid calls, metadata survives partial manifests.
$request = @{ seeds = @($seeds[0]); count = 2; fidelity = 85; variation = 70; keywordIds = @('soft'); useAi = $false; output = $temporary; randomSeed = 23; addSubjectMask = $true; addBackgroundMask = $true }
$local = Run-Generation $request $appRoot
$manifest = Get-Content -LiteralPath (Join-Path $local.folder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Regression ($manifest.generatedCount -eq 2 -and $manifest.usage.calls -eq 0 -and $manifest.masks.source -eq 'automatic') 'Local automatic masks required AI or lost metadata.'
foreach ($row in $local.rows) { $x = Read-Xmp (Join-Path $local.folder $row.File); Assert-Regression (@(Get-ReferenceMaskGroups $x).Count -eq 2 -and $row.Details.maskInstructions.background) 'Local preset omitted its masks.' }
Save-PartialManifest $request 'cancelled'
$partial = Get-Content -LiteralPath (Join-Path $local.folder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Regression ($partial.masks.source -eq 'automatic' -and $partial.masks.subject -and $partial.masks.background) 'Partial export lost mask instructions.'
# Compare the operational schema with the local Adobe preset if Lightroom is installed.
$adobe = Join-Path $env:ProgramFiles 'Adobe\Adobe Lightroom CC\Resources\Settings\Premium\Adaptive - Subject\Light.xmp'
if (Test-Path -LiteralPath $adobe) {
    $official = Read-Xmp $adobe; $expected = $official.Desc.SelectSingleNode('crs:MaskGroupBasedCorrections/rdf:Seq/rdf:li/rdf:Description/crs:CorrectionMasks/rdf:Seq/rdf:li', $official.Ns)
    $generated = (Get-ReferenceMaskGroups $x)[0].Node.SelectSingleNode('crs:CorrectionMasks/rdf:Seq/rdf:li', $x.Ns)
    foreach ($key in @('What','MaskActive','MaskBlendMode','MaskValue','MaskVersion','MaskSubType','ReferencePoint','ErrorReason')) { Assert-Regression ($generated.GetAttribute($key,$script:CrsNs) -eq $expected.GetAttribute($key,$script:CrsNs)) ('Adobe adaptive selector schema differs: ' + $key) }
}
Write-Host 'PASS: template-free subject/inverse-background selectors, enable flags, unique IDs, recipe units, existing mask preservation, local generation without API, partial metadata and installed Adobe schema.'
