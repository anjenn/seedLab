$script:References = [Collections.ObjectModel.ObservableCollection[object]]::new()
$script:ReferenceSerial = 0; $script:ReferenceTarget = ''; $script:ReferenceMask = ''; $script:ReferenceMaskHash = ''
$script:RefKeywordChecks = [Collections.Generic.List[object]]::new()
$controls.ReferenceList.ItemsSource = $script:References
$controls.RefOutput.Text = $controls.Output.Text
Add-KeywordChips $controls.RefKeywordGroups $script:RefKeywordChecks

function Update-ReferenceCount {
    $controls.RefPhotoCount.Text = $(if ($script:References.Count) { $script:References.Count.ToString() + '장 선택 · 최대 24장' } else { '0장 선택 · 최대 24장' })
    $controls.RefEmpty.Visibility = $(if ($script:References.Count) { 'Collapsed' } else { 'Visible' })
    foreach ($name in @('RefRemove','RefClear')) { $controls[$name].IsEnabled = $script:References.Count -gt 0 }
    Update-RunSummary
}
function Add-References($Paths, [switch]$Quiet) {
    $errors = @(); $added = 0
    foreach ($path in @($Paths)) {
        try {
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if (@($script:References | Where-Object { $_.hash -eq $hash }).Count) { continue }
            if ($script:References.Count -ge 24) { $errors += '레퍼런스는 최대 24장입니다. 나머지 사진은 추가하지 않았습니다.'; break }
            $stored = Import-ProjectFile $path 'references'
            $script:ReferenceSerial++
            $script:References.Add([pscustomobject]@{ id = ('R{0:000}' -f $script:ReferenceSerial); name = [IO.Path]::GetFileName($path); path = $stored; hash = $hash; thumb = (New-Thumbnail $stored 200) }); $added++
        } catch { $errors += ([IO.Path]::GetFileName($path) + ': ' + $_.Exception.Message) }
    }
    Update-ReferenceCount
    if ($Quiet) { return }
    if ($added) { Set-Status ('레퍼런스 사진 ' + $added + '장 추가' + $(if ($script:ProjectRoot) { ' · 프로젝트에 복사됨' } else { '' })) }
    if ($errors.Count) { Show-Notice ($errors -join "`n") '레퍼런스 추가' }
}
function Remove-SelectedReferences { foreach ($item in @($controls.ReferenceList.SelectedItems)) { [void]$script:References.Remove($item) }; Update-ReferenceCount }
function Set-ReferenceTarget([string]$Path) {
    $Path = Import-ProjectFile $Path 'photos'
    $script:ReferenceTarget = $Path
    $controls.RefTargetPath.Text = $(if ($Path) { [IO.Path]::GetFileName($Path) } else { '보정 전 JPG/PNG를 넣으면 그 사진에 맞춰 보정값을 추정합니다.' })
    $controls.RefTargetPath.ToolTip = $(if ($Path) { $Path } else { $null })
    $controls.RefTargetThumb.Source = $(if ($Path) { New-Thumbnail $Path 120 } else { $null })
    $controls.RefTargetClear.Visibility = $(if ($Path) { 'Visible' } else { 'Collapsed' })
    Request-AutoSave
}
# Loads a Lightroom AI mask template and pre-selects subject/background groups by name.
function Set-ReferenceMask([string]$Path) {
    $x = Read-Xmp $Path; $groups = @(Get-ReferenceMaskGroups $x)
    if (-not $groups.Count) { throw '템플릿에서 마스크 그룹을 찾지 못했습니다.' }
    $Path = Import-ProjectFile $Path 'masks'
    $script:ReferenceMask = $Path; $script:ReferenceMaskHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $controls.RefSubjectGroup.ItemsSource = $groups; $controls.RefBackgroundGroup.ItemsSource = $groups
    $subject = @($groups | Where-Object { $_.Name -match '(?i)subject|person|people|portrait|인물|피사체' } | Select-Object -First 1)
    $background = @($groups | Where-Object { $_.Name -match '(?i)background|배경|^bg$' } | Select-Object -First 1)
    $controls.RefSubjectGroup.SelectedIndex = $(if ($subject.Count) { $subject[0].Index } else { 0 })
    $controls.RefBackgroundGroup.SelectedIndex = $(if ($background.Count) { $background[0].Index } elseif ($groups.Count -gt 1) { 1 } else { -1 })
    Update-MaskState; Request-AutoSave
}
function Clear-ReferenceMask { $script:ReferenceMask = ''; $script:ReferenceMaskHash = ''; $controls.RefSubjectGroup.ItemsSource = @(); $controls.RefBackgroundGroup.ItemsSource = @(); Update-MaskState; Request-AutoSave }
# The info box explains what the current subject/background choices will do before a run starts.
function Update-MaskState {
    $hasTemplate = [bool]$script:ReferenceMask
    $controls.RefSubjectGroup.IsEnabled = $hasTemplate -and [bool]$controls.RefSubject.IsChecked
    $controls.RefBackgroundGroup.IsEnabled = $hasTemplate -and [bool]$controls.RefBackground.IsChecked
    $controls.RefMaskClear.Visibility = $(if ($hasTemplate) { 'Visible' } else { 'Collapsed' })
    if (-not ($controls.RefSubject.IsChecked -or $controls.RefBackground.IsChecked)) { $text = '전체 보정만 만듭니다. 마스크 템플릿이 필요하지 않습니다.'; $ok = $true }
    elseif ($hasTemplate) { $text = [IO.Path]::GetFileName($script:ReferenceMask) + ' · ' + @($controls.RefSubjectGroup.ItemsSource).Count + '개 그룹. 인물·배경 매핑이 맞는지 확인하세요.'; $ok = $true }
    else { $text = '템플릿 필요 · Select Subject와 Select Background를 저장한 XMP를 선택하거나, 전체 보정만 원하면 두 항목을 끄세요.'; $ok = $false }
    $controls.RefMaskInfo.Text = $text
    $tone = Get-Brush $(if ($ok) { 'AccentBrush' } else { 'WarnBrush' })
    $controls.RefMaskBar.Background = $tone; $controls.RefMaskIcon.Foreground = $tone
    $controls.RefMaskIcon.Text = $(if ($ok) { [string][char]0xE73E } else { [string][char]0xE946 })
}
$script:References.Add_CollectionChanged({ Update-ReferenceCount })
$controls.RefAdd.Add_Click({ Add-References (Pick-Files 'Reference photos (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png' $true) })
$controls.RefRemove.Add_Click({ if (-not $controls.ReferenceList.SelectedItems.Count) { Set-Status '뺄 사진을 먼저 선택하세요. Ctrl/Shift로 여러 장을 고를 수 있습니다.' 'error'; return }; Remove-SelectedReferences })
$controls.RefClear.Add_Click({ $script:References.Clear() })
$controls.ReferenceList.Add_KeyDown({ param($sender, $e) if ($e.Key -eq 'Delete') { Remove-SelectedReferences; $e.Handled = $true } })
$controls.RefCard.Add_DragOver({ param($sender, $e) Set-DropFeedback $sender $e })
$controls.RefCard.Add_DragLeave({ param($sender, $e) Clear-DropFeedback $sender })
$controls.RefCard.Add_Drop({ param($sender, $e) Clear-DropFeedback $sender; $paths = @(Get-DropPaths $e @('.jpg','.jpeg','.png')); if ($paths.Count) { Add-References $paths } else { Set-Status 'JPG·PNG 사진이나 사진이 든 폴더를 놓아 주세요.' 'error' } })
$controls.RefTargetButton.Add_Click({ $files = @(Pick-Files 'Unedited target (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png' $false); if ($files.Count) { try { Set-ReferenceTarget $files[0] } catch { Show-Notice $_.Exception.Message '원본 사진' } } })
$controls.RefTargetClear.Add_Click({ Set-ReferenceTarget '' })
$controls.RefChooseOutput.Add_Click({ $folder = Pick-Folder $controls.RefOutput.Text; if ($folder) { $controls.RefOutput.Text = $folder } })
$controls.RefFidelity.Add_ValueChanged({ $controls.RefFidelityValue.Text = [int]$controls.RefFidelity.Value })
$controls.RefVariation.Add_ValueChanged({ $controls.RefVariationValue.Text = [int]$controls.RefVariation.Value })
$controls.RefCount.Add_TextChanged({ Test-CountBox $controls.RefCount })
$controls.RefCount.Add_PreviewTextInput({ param($sender, $e) if ($e.Text -notmatch '^\d+$') { $e.Handled = $true } })
$controls.RefMode.Add_SelectionChanged({ Update-RunSummary })
$controls.RefSearch.Add_Checked({ Update-RunSummary }); $controls.RefSearch.Add_Unchecked({ Update-RunSummary })
$controls.RefKeywordClear.Add_Click({ foreach ($check in $script:RefKeywordChecks) { $check.IsChecked = $false } })
foreach ($name in @('RefSubject','RefBackground')) { $controls[$name].Add_Checked({ Update-MaskState }); $controls[$name].Add_Unchecked({ Update-MaskState }) }
$controls.RefMaskButton.Add_Click({
    try { $files = @(Pick-Files 'Lightroom AI mask preset (*.xmp)|*.xmp' $false); if ($files.Count) { Set-ReferenceMask $files[0] } }
    catch { Show-Notice $_.Exception.Message '마스크 템플릿' }
})
$controls.RefMaskClear.Add_Click({ Clear-ReferenceMask })
Update-MaskState
function New-ReferenceRequest {
    if (-not $script:References.Count) { throw '레퍼런스 사진을 하나 이상 추가하세요.' }
    $count = 0; if (-not [int]::TryParse($controls.RefCount.Text, [ref]$count) -or $count -lt 1 -or $count -gt 120) { throw '총 생성 개수는 1~120입니다.' }
    if ([string]::IsNullOrWhiteSpace($controls.RefApiKey.Password)) { $controls.RefApiKey.Focus(); throw '이미지 분석용 API 키를 입력하세요.' }
    if ([string]::IsNullOrWhiteSpace($controls.RefModel.Text)) { throw '이미지 입력과 구조화 출력을 지원하는 모델을 지정하세요.' }
    if ([string]::IsNullOrWhiteSpace($controls.RefOutput.Text)) { throw '저장 폴더를 지정하세요.' }
    $mode = $controls.RefMode.SelectedItem.Tag
    if ($mode -eq 'individual' -and $count -lt $script:References.Count) { throw '사진별 모드에서는 총 생성 개수를 레퍼런스 수 이상으로 지정하세요.' }
    $request = @{ generationMode = 'reference'; useAi = $true; references = @($script:References | ForEach-Object { @{ id = $_.id; path = $_.path; hash = $_.hash } }); seeds = @();
        count = $count; referenceMode = $mode; referenceSearch = [bool]$controls.RefSearch.IsChecked; referenceTarget = $script:ReferenceTarget;
        apiKey = $controls.RefApiKey.Password; model = $controls.RefModel.Text.Trim(); note = $controls.RefNote.Text;
        fidelity = [int]$controls.RefFidelity.Value; variation = [int]$controls.RefVariation.Value;
        keywordIds = @($script:RefKeywordChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag });
        referenceMaskTemplate = $script:ReferenceMask; referenceMaskHash = $script:ReferenceMaskHash;
        maskSubject = [bool]$controls.RefSubject.IsChecked; maskBackground = [bool]$controls.RefBackground.IsChecked;
        subjectMaskIndex = $(if ($controls.RefSubjectGroup.SelectedItem) { $controls.RefSubjectGroup.SelectedItem.Index } else { $null });
        backgroundMaskIndex = $(if ($controls.RefBackgroundGroup.SelectedItem) { $controls.RefBackgroundGroup.SelectedItem.Index } else { $null });
        output = [IO.Path]::GetFullPath($controls.RefOutput.Text); randomSeed = (Get-Random -Minimum 1 -Maximum 2147483647) }
    Test-ReferenceMaskTemplate $request
    return $request
}
