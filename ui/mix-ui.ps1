$script:MixSources = [Collections.ObjectModel.ObservableCollection[object]]::new()
$script:RefreshingMix = $false
$controls.MixGrid.ItemsSource = $script:MixSources
$controls.MixOutput.Text = $controls.Output.Text
function Get-MixGroupChoices {
    return @{ tone = [string]$controls.MixTone.SelectedValue; color = [string]$controls.MixColor.SelectedValue; texture = [string]$controls.MixTexture.SelectedValue; curves = [string]$controls.MixCurves.SelectedValue }
}
function Set-MixGroupChoices($Choices) {
    foreach ($pair in @(@('tone','MixTone'),@('color','MixColor'),@('texture','MixTexture'),@('curves','MixCurves'))) {
        if ($Choices -and $Choices.($pair[0]) -in @($controls[$pair[1]].Items | ForEach-Object { $_.id })) { $controls[$pair[1]].SelectedValue = $Choices.($pair[0]) }
    }
}
function Refresh-MixChoices {
    if ($script:RefreshingMix) { return }
    $script:RefreshingMix = $true
    try {
        $base = $controls.MixBase.SelectedValue; $selected = Get-MixGroupChoices
        $controls.MixBase.ItemsSource = @([pscustomobject]@{ id = 'random'; name = '랜덤 · 후보마다 선택' }) + @($script:MixSources)
        $controls.MixBase.SelectedValue = $base
        if (-not $controls.MixBase.SelectedItem -and $script:MixSources.Count) { $controls.MixBase.SelectedValue = $script:MixSources[0].id }
        $options = @([pscustomobject]@{ id = 'random'; label = '랜덤으로 섞기' }, [pscustomobject]@{ id = 'blend'; label = '비율대로 섞기' }, [pscustomobject]@{ id = 'base'; label = '기준 프리셋 유지' })
        $options += @($script:MixSources | ForEach-Object { [pscustomobject]@{ id = $_.id; label = $_.name } })
        foreach ($name in @('MixTone','MixColor','MixTexture','MixCurves')) { $controls[$name].ItemsSource = $options; $controls[$name].SelectedValue = 'blend' }
        Set-MixGroupChoices $selected
    } finally { $script:RefreshingMix = $false }
    Update-MixSummary
}
function Update-MixSummary {
    $active = @($script:MixSources | Where-Object { $_.weight -gt 0 }); $sum = ($active | Measure-Object -Property weight -Sum).Sum
    $controls.MixSummary.Text = $(if ($sum -gt 0) { '사용 ' + $active.Count + '개 · ' + ((@($active | ForEach-Object { $_.name + ' ' + ([double](100 * $_.weight / $sum)).ToString('0.#') + '%' })) -join ' / ') } else { '혼합할 프리셋 2개 이상을 추가하고 비율을 설정하세요.' })
    $choices = Get-MixGroupChoices
    $random = $controls.MixBase.SelectedValue -eq 'random' -or @($choices.Values | Where-Object { $_ -eq 'random' }).Count -gt 0
    $controls.MixRandomHint.Visibility = $(if ($random) { 'Visible' } else { 'Collapsed' })
    $controls.MixRandomAll.IsEnabled = $active.Count -ge 2
    $controls.MixRemove.IsEnabled = $script:MixSources.Count -gt 0; $controls.MixEqual.IsEnabled = $script:MixSources.Count -gt 0
    Update-RunSummary; Request-AutoSave
}
function Add-MixSources($Paths, [switch]$Quiet) {
    $errors = [Collections.Generic.List[string]]::new(); $added = 0
    foreach ($path in @($Paths)) {
        try {
            $source = Get-MixSource $path
            if (@($script:MixSources | Where-Object { $_.id -eq $source.id }).Count) { continue }
            if ($script:MixSources.Count -ge 12) { throw '믹스매치는 한 번에 최대 12개를 등록할 수 있습니다.' }
            $source.path = Import-ProjectFile $path 'mix'; $script:MixSources.Add($source); $added++
        } catch { $errors.Add([IO.Path]::GetFileName($path) + ': ' + $_.Exception.Message) }
    }
    if (-not $Quiet) {
        Set-Status ('믹스매치 프리셋 ' + $added + '개 추가')
        if ($errors.Count) { Show-Notice ($errors -join "`n") '믹스매치 입력 확인' }
    }
}
function Remove-MixSources { foreach ($item in @($controls.MixGrid.SelectedItems)) { [void]$script:MixSources.Remove($item) } }
function New-MixRequest {
    if ($script:MixSources.Count -lt 2) { throw '혼합할 XMP를 2개 이상 추가하세요.' }
    $count = 0
    if (-not [int]::TryParse($controls.MixCount.Text, [ref]$count) -or $count -lt 1 -or $count -gt 24) { throw '믹스매치 생성 개수는 1~24입니다.' }
    if (-not $controls.MixBase.SelectedItem) { throw '기준 프리셋을 선택하세요.' }
    if ([string]::IsNullOrWhiteSpace($controls.MixOutput.Text)) { throw '저장 폴더를 지정하세요.' }
    $ai = [bool]$controls.MixUseAi.IsChecked
    if ($ai -and ([string]::IsNullOrWhiteSpace($controls.MixApiKey.Password) -or [string]::IsNullOrWhiteSpace($controls.MixModel.Text))) { throw 'AI로 섞으려면 API 키와 모델을 입력하세요. AI를 끄면 비용 없이 혼합합니다.' }
    return @{ generationMode = 'mix'; sources = @($script:MixSources | Select-Object id,name,path,weight); baseId = $controls.MixBase.SelectedValue;
        mixGroups = (Get-MixGroupChoices); count = $count; variation = [int]$controls.MixVariation.Value; fidelity = 0; keywordIds = @();
        randomSeed = (Get-Random -Minimum 1 -Maximum 2147483647); useAi = $ai; apiKey = $(if ($ai) { $controls.MixApiKey.Password } else { '' });
        model = $controls.MixModel.Text.Trim(); note = $controls.MixNote.Text; output = [IO.Path]::GetFullPath($controls.MixOutput.Text) }
}
$script:MixSources.Add_CollectionChanged({ Refresh-MixChoices })
$controls.MixGrid.AddHandler([Windows.Controls.Primitives.RangeBase]::ValueChangedEvent, [Windows.RoutedPropertyChangedEventHandler[double]]{
    param($sender, $e)
    if ($e.OriginalSource -is [Windows.Controls.Slider] -and $e.OriginalSource.DataContext) { $e.OriginalSource.DataContext.weight = [double]$e.NewValue; Update-MixSummary }
})
$controls.MixGrid.Add_PreviewKeyDown({ param($sender,$e) if ($e.Key -eq 'Delete') { Remove-MixSources; $e.Handled = $true } })
$controls.MixAdd.Add_Click({ Add-MixSources (Pick-Files 'Lightroom preset (*.xmp)|*.xmp' $true) })
$controls.MixFolder.Add_Click({ $folder = Pick-Folder ''; if ($folder) { Add-MixSources @(Get-ChildItem -LiteralPath $folder -Filter '*.xmp' -File -Recurse | ForEach-Object { $_.FullName }) } })
$controls.MixFromSeeds.Add_Click({ Add-MixSources @($script:Seeds | Where-Object { $_.Use } | ForEach-Object { $_.path }) })
$controls.MixRemove.Add_Click({ Remove-MixSources })
$controls.MixRandomAll.Add_Click({
    Set-MixGroupChoices @{ tone = 'random'; color = 'random'; texture = 'random'; curves = 'random' }
    $controls.MixBase.SelectedValue = 'random'; Update-MixSummary
    Set-Status '네 항목과 기준 프리셋을 후보마다 무작위로 정합니다. 생성 개수를 정하고 믹스매치 생성을 누르세요.'
})
$controls.MixEqual.Add_Click({ foreach ($source in $script:MixSources) { $source.weight = 50.0 }; $controls.MixGrid.Items.Refresh(); Update-MixSummary })
$controls.MixCard.Add_DragOver({ param($sender,$e) Set-DropFeedback $sender $e })
$controls.MixCard.Add_DragLeave({ param($sender,$e) Clear-DropFeedback $sender })
$controls.MixCard.Add_Drop({ param($sender,$e) Clear-DropFeedback $sender; Add-MixSources @(Get-DropPaths $e @('.xmp')) })
foreach ($name in @('MixTone','MixColor','MixTexture','MixCurves','MixBase')) { $controls[$name].Add_SelectionChanged({ if (-not $script:RefreshingMix) { Update-MixSummary } }) }
$controls.MixCount.Add_TextChanged({
    $n = 0
    if ([int]::TryParse($controls.MixCount.Text, [ref]$n) -and $n -ge 1 -and $n -le 24) { $controls.MixCount.ClearValue([Windows.Controls.Control]::BorderBrushProperty) } else { $controls.MixCount.BorderBrush = Get-Brush 'DangerBrush' }
    Update-RunSummary; Request-AutoSave
})
$controls.MixCount.Add_PreviewTextInput({ param($sender,$e) if ($e.Text -notmatch '^\d+$') { $e.Handled = $true } })
$controls.MixVariation.Add_ValueChanged({ $controls.MixVariationValue.Text = [int]$controls.MixVariation.Value; Request-AutoSave })
$controls.MixUseAi.Add_Checked({ Update-RunSummary; Request-AutoSave }); $controls.MixUseAi.Add_Unchecked({ Update-RunSummary; Request-AutoSave })
$controls.MixChooseOutput.Add_Click({ $folder = Pick-Folder $controls.MixOutput.Text; if ($folder) { $controls.MixOutput.Text = $folder } })
foreach ($name in @('MixOutput','MixModel','MixNote')) { $controls[$name].Add_TextChanged({ Request-AutoSave }) }
