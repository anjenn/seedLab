# Results page: run summary header, candidate list and a readable detail panel.
$script:FieldLabels = @{
    Exposure2012 = '노출'; Contrast2012 = '대비'; Highlights2012 = '하이라이트'; Shadows2012 = '섀도'; Whites2012 = '화이트'; Blacks2012 = '블랙'
    Texture = '텍스처'; Clarity2012 = '클래리티'; Dehaze = '디헤이즈'; Vibrance = '비브런스'; Saturation = '채도'; Temperature = '색온도'; Tint = '틴트'
    GrainAmount = '그레인'; GrainSize = '그레인 크기'; GrainFrequency = '그레인 거칠기'; ColorGradeMidtoneSat = '중간톤 그레이딩 채도'
    ColorGradeMidtoneHue = '중간톤 그레이딩 색상'; ColorGradeMidtoneLum = '중간톤 그레이딩 휘도'; ColorGradeShadowLum = '섀도 그레이딩 휘도'; ColorGradeHighlightLum = '하이라이트 그레이딩 휘도'
    ColorGradeGlobalHue = '전체 그레이딩 색상'; ColorGradeGlobalSat = '전체 그레이딩 채도'; ColorGradeGlobalLum = '전체 그레이딩 휘도'; ColorGradeBlending = '그레이딩 혼합'
    SplitToningShadowHue = '섀도 토닝 색상'; SplitToningShadowSaturation = '섀도 토닝 채도'; SplitToningHighlightHue = '하이라이트 토닝 색상'; SplitToningHighlightSaturation = '하이라이트 토닝 채도'; SplitToningBalance = '토닝 균형'
    # Local mask keys (lower case). Lookups are case-insensitive, so temperature/tint/saturation/texture/dehaze reuse the entries above.
    exposure = '노출'; contrast = '대비'; highlights = '하이라이트'; shadows = '섀도'; whites = '화이트'; blacks = '블랙'; clarity = '클래리티'
}
$script:HslLabels = @{ HueAdjustment = 'HSL 색상'; SaturationAdjustment = 'HSL 채도'; LuminanceAdjustment = 'HSL 휘도' }
$script:ColorLabels = @{ Red = '빨강'; Orange = '주황'; Yellow = '노랑'; Green = '초록'; Aqua = '아쿠아'; Blue = '파랑'; Purple = '보라'; Magenta = '마젠타' }

function Format-FieldName([string]$Key) {
    if ($script:FieldLabels.ContainsKey($Key)) { return $script:FieldLabels[$Key] }
    foreach ($prefix in $script:HslLabels.Keys) {
        if ($Key.StartsWith($prefix)) { $color = $Key.Substring($prefix.Length); return $script:HslLabels[$prefix] + ' · ' + $(if ($script:ColorLabels.ContainsKey($color)) { $script:ColorLabels[$color] } else { $color }) }
    }
    return $Key
}
function Get-NamedValues($Source) {
    if ($null -eq $Source) { return @() }
    if ($Source -is [Collections.IDictionary]) { return @($Source.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Key; Value = $_.Value } }) }
    return @($Source.PSObject.Properties | Where-Object { $_.MemberType -like '*Property' } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
}
function New-ValueChip([string]$Label, $Value, [bool]$Signed) {
    $number = 0.0; $text = [string]$Value
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        $text = $number.ToString($(if ($Signed) { '+0.##;-0.##;0' } else { '0.##' }), [Globalization.CultureInfo]::InvariantCulture)
    }
    $chip = [Windows.Controls.Border]::new(); $chip.CornerRadius = [Windows.CornerRadius]::new(8); $chip.Background = Get-Brush 'SubtleBrush'; $chip.BorderBrush = Get-Brush 'LineBrush'
    $chip.BorderThickness = [Windows.Thickness]::new(1); $chip.Padding = [Windows.Thickness]::new(9,4,9,4); $chip.Margin = [Windows.Thickness]::new(0,0,6,6)
    $row = [Windows.Controls.StackPanel]::new(); $row.Orientation = 'Horizontal'
    $name = [Windows.Controls.TextBlock]::new(); $name.Text = $Label; $name.FontSize = 12; $name.Foreground = Get-Brush 'MutedBrush'; $name.Margin = [Windows.Thickness]::new(0,0,6,0)
    $value = [Windows.Controls.TextBlock]::new(); $value.Text = $text; $value.FontSize = 12; $value.FontWeight = [Windows.FontWeights]::SemiBold; $value.Foreground = Get-Brush 'TextBrush'
    [void]$row.Children.Add($name); [void]$row.Children.Add($value); $chip.Child = $row
    return $chip
}
function Add-ChipGroup($Panel, $Pairs, [bool]$Signed) {
    foreach ($pair in @($Pairs)) { [void]$Panel.Children.Add((New-ValueChip (Format-FieldName $pair.Name) $pair.Value $Signed)) }
}
function Set-ResultNotice([string]$Text) {
    $controls.Detail.Text = $Text
    $controls.ResultsNotice.Visibility = $(if ([string]::IsNullOrWhiteSpace($Text)) { 'Collapsed' } else { 'Visible' })
}
function Show-ResultDetail($Row) {
    $controls.DetailPanel.Visibility = $(if ($Row) { 'Visible' } else { 'Collapsed' })
    $controls.DetailEmpty.Visibility = $(if ($Row) { 'Collapsed' } else { 'Visible' })
    if (-not $Row) { return }
    $reference = $Row.Mode -eq '레퍼런스'
    $controls.DetailName.Text = $Row.Name; $controls.DetailKeyword.Text = $Row.Keyword; $controls.DetailMode.Text = $Row.ModeText
    $controls.DetailSeed.Text = $Row.Seed
    $controls.DetailReason.Text = $(if ($Row.Reason) { $Row.Reason } else { '기록된 이유가 없습니다.' })
    $controls.DetailChangesTitle.Text = $(if ($reference) { '추정 보정값' } elseif ($Row.Details.mode -like 'mix_*') { '기준 프리셋 대비 변경' } else { '씨드 대비 변경' })
    $controls.DetailChanges.Children.Clear(); $controls.DetailLocal.Children.Clear()
    $pairs = @(Get-NamedValues $(if ($reference) { $Row.Details.values } else { $Row.Details.delta }))
    if ($pairs.Count) { Add-ChipGroup $controls.DetailChanges $pairs (-not $reference) }
    else { $none = [Windows.Controls.TextBlock]::new(); $none.Text = '바뀐 전역 보정값이 없습니다.'; $none.Style = $window.FindResource('Muted'); [void]$controls.DetailChanges.Children.Add($none) }
    if ($reference) {
        foreach ($area in @(@{ key = 'subject'; title = '인물 보정' }, @{ key = 'background'; title = '배경 보정' })) {
            if ($Row.Details.maskInstructions -and -not $Row.Details.maskInstructions.($area.key)) { continue }
            $local = @(Get-NamedValues $Row.Details.($area.key) | Where-Object { [double]$_.Value -ne 0 })
            if (-not $local.Count) { continue }
            $title = [Windows.Controls.TextBlock]::new(); $title.Text = $area.title; $title.Style = $window.FindResource('Section'); $title.Margin = [Windows.Thickness]::new(0,10,0,8)
            $wrap = [Windows.Controls.WrapPanel]::new(); Add-ChipGroup $wrap $local $true
            [void]$controls.DetailLocal.Children.Add($title); [void]$controls.DetailLocal.Children.Add($wrap)
        }
    }
    $controls.DetailFile.Text = $Row.File
    $controls.DetailMask.Text = $(if ($Row.Details.maskInstructions.source -eq 'automatic') { '자동 마스크는 Lightroom에서 프리셋을 적용할 때 계산합니다. 필요하면 마스크를 업데이트하세요.' } elseif ([int]$Row.MaskChanges) { '마스크 보정값 ' + $Row.MaskChanges + '개를 설정했습니다.' } else { '' })
    $controls.DetailMask.Visibility = $(if ([int]$Row.MaskChanges) { 'Visible' } else { 'Collapsed' })
}
function Show-Results($Rows, [string]$Folder, [string]$Title, [string]$Meta, [bool]$Partial, [bool]$Activate = $true) {
    $position = 0
    $items = @(foreach ($row in @($Rows | Where-Object { $null -ne $_ })) {
        $position++
        $number = $(if ($null -ne $row.Details -and $null -ne $row.Details.index) { [int]$row.Details.index + 1 } else { $position })
        $modeText = $(if ($row.Mode -eq 'ai') { 'AI 설계' } elseif ($row.Mode -eq 'local') { '로컬 변주' } else { [string]$row.Mode })
        $row | Add-Member -NotePropertyName No -NotePropertyValue $number -Force
        $row | Add-Member -NotePropertyName ModeText -NotePropertyValue $modeText -Force
        $row
    })
    $script:LastFolder = $Folder
    $controls.Results.ItemsSource = $items
    $controls.ResultsEmpty.Visibility = 'Collapsed'; $controls.ResultsBody.Visibility = 'Visible'
    $controls.ResultSummary.Text = $Title; $controls.ResultMeta.Text = $Meta; $controls.ResultMeta.ToolTip = $Folder
    $controls.ResultBadge.Background = Get-Brush $(if ($Partial) { 'NeutralPillBrush' } else { 'AccentSoftBrush' })
    $controls.ResultBadgeIcon.Text = $(if ($Partial) { [string][char]0xE7BA } else { [string][char]0xE73E })
    $controls.ResultBadgeIcon.Foreground = Get-Brush $(if ($Partial) { 'WarnBrush' } else { 'AccentBrush' })
    foreach ($name in @('OpenOutput','ResultsOpenFolder')) { $controls[$name].IsEnabled = [bool]$Folder }
    if ($Activate) { Set-View 'results' } elseif ($script:CurrentView -and $script:CurrentView -ne 'results') { $controls.OpenOutput.Visibility = $(if ($Folder) { 'Visible' } else { 'Collapsed' }) }
    if ($items.Count) { $controls.Results.SelectedIndex = 0; $controls.Results.ScrollIntoView($items[0]) } else { Show-ResultDetail $null }
    Request-AutoSave
}
function Clear-Results {
    $script:LastFolder = $null; $controls.Results.ItemsSource = $null; Show-ResultDetail $null; Set-ResultNotice ''
    $controls.ResultsBody.Visibility = 'Collapsed'; $controls.ResultsEmpty.Visibility = 'Visible'
    $controls.OpenOutput.Visibility = 'Collapsed'; $controls.OpenOutput.IsEnabled = $false
}
function Show-SelectedFile {
    $row = $controls.Results.SelectedItem
    if (-not $row -or -not $script:LastFolder) { return }
    $path = Join-Path $script:LastFolder $row.File
    if ([IO.File]::Exists($path)) { Start-Process explorer.exe -ArgumentList ('/select,"' + $path + '"') } else { Open-Folder $script:LastFolder }
}
$controls.Results.Add_SelectionChanged({ Show-ResultDetail $controls.Results.SelectedItem })
$controls.Results.Add_MouseDoubleClick({ Show-SelectedFile })
$controls.RevealFile.Add_Click({ Show-SelectedFile })
$controls.ResultsOpenFolder.Add_Click({ Open-Folder $script:LastFolder })
$controls.ResultsGoGenerate.Add_Click({ Set-View 'generator' })
