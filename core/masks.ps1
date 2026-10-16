# Adaptive selectors describe a Lightroom operation, not a raster selection.
# Schema checked against Adobe Lightroom's installed Adaptive - Subject presets.
# Background uses the inverse of the same subject selector (never guessed subtype 0).
function New-AdaptiveMaskGroup($X, [ValidateSet('Subject','Background')][string]$Kind, $Values) {
    $li = $X.Doc.CreateElement('rdf', 'li', $script:RdfNs)
    $node = $X.Doc.CreateElement('rdf', 'Description', $script:RdfNs); [void]$li.AppendChild($node)
    $name = $(if ($Kind -eq 'Subject') { '인물·피사체' } else { '배경' })
    foreach ($entry in @{ What = 'Correction'; CorrectionAmount = '1'; CorrectionActive = 'true'; CorrectionName = ($name + ' · Seed Lab'); CorrectionSyncID = [Guid]::NewGuid().ToString('N').ToUpperInvariant() }.GetEnumerator()) { Set-Crs $X.Doc $node $entry.Key $entry.Value }
    $limits = @{ LocalExposure2012 = 1.25; LocalContrast2012 = 1; LocalHighlights2012 = 1; LocalShadows2012 = 1; LocalWhites2012 = 1; LocalBlacks2012 = 1; LocalTemperature = 1; LocalTint = 1; LocalSaturation = 1; LocalTexture = 1; LocalClarity2012 = 1; LocalDehaze = 1 }
    foreach ($key in $limits.Keys) { Set-Crs $X.Doc $node $key '0' }
    $pairs = $(if ($Values -is [Collections.IDictionary]) { @($Values.GetEnumerator() | ForEach-Object { @{ Name = $_.Key; Value = $_.Value } }) } else { @($Values.PSObject.Properties) })
    foreach ($pair in $pairs) {
        $value = 0.0
        if (-not $limits.ContainsKey([string]$pair.Name) -or -not [double]::TryParse([string]$pair.Value, [Globalization.NumberStyles]::Float, $script:Invariant, [ref]$value) -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or [Math]::Abs($value) -gt $limits[$pair.Name]) { throw '자동 마스크 보정값이 지원 범위를 벗어났습니다.' }
        Set-Crs $X.Doc $node $pair.Name $value.ToString('0.####', $script:Invariant)
    }
    $masks = $X.Doc.CreateElement('crs', 'CorrectionMasks', $script:CrsNs); $seq = $X.Doc.CreateElement('rdf', 'Seq', $script:RdfNs); $selector = $X.Doc.CreateElement('rdf', 'li', $script:RdfNs)
    $attributes = @{ What = 'Mask/Image'; MaskActive = 'true'; MaskName = $name; MaskBlendMode = '0'; MaskInverted = $(if ($Kind -eq 'Background') { 'true' } else { 'false' }); MaskSyncID = [Guid]::NewGuid().ToString('N').ToUpperInvariant(); MaskValue = '1'; MaskVersion = '1'; MaskSubType = '1'; ReferencePoint = '0.500000 0.500000'; ErrorReason = '0' }
    foreach ($entry in $attributes.GetEnumerator()) { Set-Crs $X.Doc $selector $entry.Key $entry.Value }
    [void]$seq.AppendChild($selector); [void]$masks.AppendChild($seq); [void]$node.AppendChild($masks)
    return ,$li
}
function Get-ReferenceMaskMode($Request) {
    if (-not ($Request.maskSubject -or $Request.maskBackground)) { return 'none' }
    if ($Request.referenceMaskMode) {
        if ($Request.referenceMaskMode -notin @('automatic','template')) { throw '마스크 선택 방식을 확인하세요.' }
        return [string]$Request.referenceMaskMode
    }
    # Existing saved requests with a template retain their previous behavior.
    return $(if ($Request.referenceMaskTemplate) { 'template' } else { 'automatic' })
}
function Get-MaskInstructions($Request) {
    $reference = $Request.generationMode -eq 'reference'
    $subject = $(if ($reference) { [bool]$Request.maskSubject } else { [bool]$Request.addSubjectMask })
    $background = $(if ($reference) { [bool]$Request.maskBackground } else { [bool]$Request.addBackgroundMask })
    $source = $(if ($reference) { Get-ReferenceMaskMode $Request } elseif ($subject -or $background) { 'automatic' } else { 'none' })
    return @{ source = $source; subject = $subject; background = $background;
        selection = $(if ($source -eq 'automatic') { 'Lightroom Select Subject; background = inverted subject' } elseif ($source -eq 'template') { 'Imported template selections' } else { $null });
        requiresLightroomComputation = ($subject -or $background) }
}
function Get-SeedMaskValues($Candidate, [string]$Kind) {
    $scale = [double]$Candidate.variation / 100 * (0.3 + 0.7 * (1 - [double]$Candidate.fidelity / 100))
    return @{ LocalExposure2012 = $(if ($Kind -eq 'Subject') { (0.18 + $Candidate.axes.exposure * 0.12) / 4 * $scale } else { (-0.15 + $Candidate.axes.exposure * 0.15) / 4 * $scale });
        LocalContrast2012 = $Candidate.axes.contrast * 0.16 * $scale; LocalClarity2012 = -$Candidate.axes.softness * 0.14 * $scale; LocalSaturation = $Candidate.axes.saturation * 0.14 * $scale }
}
function Add-SeedAdaptiveMasks($X, $Candidate, [bool]$Subject, [bool]$Background) {
    $proofs = [Collections.Generic.List[object]]::new()
    if (-not ($Subject -or $Background)) { return @() }
    $block = $X.Desc.SelectSingleNode('crs:MaskGroupBasedCorrections', $X.Ns)
    if (-not $block) { $block = $X.Doc.CreateElement('crs', 'MaskGroupBasedCorrections', $script:CrsNs); [void]$block.AppendChild($X.Doc.CreateElement('rdf', 'Seq', $script:RdfNs)); [void]$X.Desc.AppendChild($block) }
    $seq = $block.SelectSingleNode('rdf:Seq', $X.Ns)
    if (-not $seq) { throw '기존 마스크 구조에 자동 마스크를 추가할 수 없습니다.' }
    foreach ($kind in @('Subject','Background')) {
        if (($kind -eq 'Subject' -and -not $Subject) -or ($kind -eq 'Background' -and -not $Background)) { continue }
        $li = New-AdaptiveMaskGroup $X $kind (Get-SeedMaskValues $Candidate $kind)
        [void]$seq.AppendChild($li); $node = $li.SelectSingleNode('rdf:Description', $X.Ns)
        $proofs.Add(@{ id = $node.GetAttribute('CorrectionSyncID', $script:CrsNs); xml = $node.OuterXml })
    }
    return @($proofs.ToArray())
}
function Test-SavedAdaptiveMasks($X, $Proofs) {
    foreach ($proof in @($Proofs)) {
        $node = $X.Desc.SelectSingleNode("crs:MaskGroupBasedCorrections/rdf:Seq/rdf:li/rdf:Description[@crs:CorrectionSyncID='" + $proof.id + "']", $X.Ns)
        if (-not $node -or $node.OuterXml -ne $proof.xml) { throw '자동 마스크 저장 검증에 실패했습니다.' }
    }
}
