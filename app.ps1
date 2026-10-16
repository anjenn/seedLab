try {
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'functions.ps1')
$script:AppRoot = $PSScriptRoot
$script:Seeds = New-Object 'Collections.ObjectModel.ObservableCollection[object]'
$script:Job = $null; $script:LastFolder = $null; $script:ActiveRequest = $null; $script:Dashboard = $null; $script:DashboardBusy = $false
$script:KeywordChecks = [Collections.Generic.List[object]]::new(); $script:CurrentView = ''; $script:SyncingKey = $false
[xml]$xaml = [IO.File]::ReadAllText((Join-Path $script:AppRoot 'ui.xaml'), [Text.Encoding]::UTF8)
$window = [Windows.Markup.XamlReader]::Load(([Xml.XmlNodeReader]::new($xaml)))
$controls = @{}
foreach ($element in $xaml.SelectNodes('//*')) { $name = $element.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml'); if ($name) { $controls[$name] = $window.FindName($name) } }
$controls.SeedGrid.ItemsSource = $script:Seeds
$controls.Output.Text = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SeedLabOutputs'
$script:Photo = ''; $script:Mask = ''
$keywords = Get-Content -LiteralPath (Join-Path $script:AppRoot 'keywords.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$script:AxisNames = @{ exposure = '밝기'; contrast = '대비'; softness = '부드러움'; warmth = '따뜻함'; magenta = '마젠타'; saturation = '채도'; shadowLift = '암부'; red = '레드'; green = '그린'; blue = '블루'; grain = '그레인' }

function Get-KeywordHint($Keyword) {
    $parts = @($Keyword.axes.PSObject.Properties | Where-Object { [Math]::Abs([double]$_.Value) -ge 0.1 } | Sort-Object { -[Math]::Abs([double]$_.Value) } | Select-Object -First 4 |
        ForEach-Object { $script:AxisNames[$_.Name] + $(if ([double]$_.Value -gt 0) { ' ↑' } else { ' ↓' }) })
    if (-not $parts.Count) { return $Keyword.category + ' · 균형 잡힌 변화' }
    return $Keyword.category + ' · ' + ($parts -join ' · ')
}
function Add-KeywordChips($Panel, $List) {
    foreach ($category in @($keywords | Select-Object -ExpandProperty category -Unique)) {
        $label = [Windows.Controls.TextBlock]::new(); $label.Text = $category; $label.Style = $window.FindResource('Section')
        [void]$Panel.Children.Add($label)
        $wrap = [Windows.Controls.WrapPanel]::new(); $wrap.Margin = [Windows.Thickness]::new(0,0,0,6)
        foreach ($keyword in @($keywords | Where-Object { $_.category -eq $category })) {
            $check = [Windows.Controls.CheckBox]::new(); $check.Content = $keyword.label; $check.Tag = $keyword.id
            $check.Style = $window.FindResource('Chip'); $check.ToolTip = Get-KeywordHint $keyword
            $check.Add_Checked({ Update-KeywordSummary }); $check.Add_Unchecked({ Update-KeywordSummary })
            $List.Add($check); [void]$wrap.Children.Add($check)
        }
        [void]$Panel.Children.Add($wrap)
    }
}
# Edits schedule one debounced save of the open project and, if enabled, the API key.
$script:AutoSaveTimer = [Windows.Threading.DispatcherTimer]::new(); $script:AutoSaveTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
$script:AutoSaveTimer.Add_Tick({ Save-AutoNow })
function Request-AutoSave { if (-not $script:Restoring) { $script:AutoSaveTimer.Stop(); $script:AutoSaveTimer.Start() } }
function Save-AutoNow {
    $script:AutoSaveTimer.Stop()
    Save-Project
    if ($controls.RememberKey.IsChecked) {
        try { if ($controls.ApiKey.Password) { Save-ApiKey $controls.ApiKey.Password } else { [void](Remove-ApiKey) } } catch { Set-Status ('API 키를 저장하지 못했습니다: ' + $_.Exception.Message) 'error' }
    }
}
Add-KeywordChips $controls.KeywordGroups $script:KeywordChecks
. (Join-Path $script:AppRoot 'dashboard.ps1')
. (Join-Path $script:AppRoot 'reference-ui.ps1')
. (Join-Path $script:AppRoot 'results-ui.ps1')
. (Join-Path $script:AppRoot 'project.ps1')

function Pick-Files([string]$Filter, [bool]$Multi) {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = $Filter; $dialog.Multiselect = $Multi
    if ($dialog.ShowDialog($window)) { return @($dialog.FileNames) }; return @()
}
function Pick-Folder([string]$Initial, [string]$Description = '') {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $Initial; $dialog.Description = $Description; $dialog.ShowNewFolderButton = $true
    try { if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath } } finally { $dialog.Dispose() }
    return $null
}
function Open-Folder([string]$Path) { if ($Path -and [IO.Directory]::Exists($Path)) { Start-Process explorer.exe -ArgumentList ('"' + $Path + '"') } }
function Show-Notice([string]$Message, [string]$Title, [string]$Icon = 'Warning') { [void][Windows.MessageBox]::Show($window, $Message, $Title, 'OK', $Icon) }
function Show-Question([string]$Message, [string]$Title, [string]$Buttons = 'YesNo') { return [string][Windows.MessageBox]::Show($window, $Message, $Title, $Buttons, 'Question') }
function Set-Status([string]$Text, [string]$Tone = 'normal') {
    $controls.Status.Text = $Text
    $controls.Status.Foreground = switch ($Tone) { 'success' { '#2E7D55' } 'error' { '#B4372F' } 'busy' { '#2F5A97' } default { '#64728A' } }
}
function Set-StatePill([string]$State, [string]$Text = '') {
    $palette = switch ($State) { 'busy' { @('#EAF1FC', '#4F76B6', '#2F5A97', '생성 중') } 'cancel' { @('#FFF4DE', '#C98A1B', '#7F5A12', '중지 중') } default { @('#E8F4EE', '#3C9A6A', '#2E7D55', '준비됨') } }
    $controls.StatePill.Background = $palette[0]; $controls.StateDot.Fill = $palette[1]; $controls.StateText.Foreground = $palette[2]
    $controls.StateText.Text = $(if ($Text) { $Text } else { $palette[3] })
}
# Thumbnails decode at a small size and honor EXIF rotation; files are not kept open.
function New-Thumbnail([string]$Path, [int]$Size = 160) {
    try {
        $angle = 0; $stream = [IO.File]::OpenRead($Path)
        try {
            $image = [Drawing.Image]::FromStream($stream, $false, $false)
            try { if ($image.PropertyIdList -contains 274) { $angle = @{ 3 = 180; 6 = 90; 8 = 270 }[[int][BitConverter]::ToUInt16($image.GetPropertyItem(274).Value, 0)] } } finally { $image.Dispose() }
        } finally { $stream.Dispose() }
        $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit(); $bitmap.CacheOption = 'OnLoad'; $bitmap.DecodePixelWidth = $Size; $bitmap.UriSource = [Uri]::new($Path); $bitmap.EndInit()
        $source = $(if ($angle) { [Windows.Media.Imaging.TransformedBitmap]::new($bitmap, [Windows.Media.RotateTransform]::new($angle)) } else { $bitmap })
        $source.Freeze(); return $source
    } catch { return $null }
}
function Get-DropPaths($EventArgs, [string[]]$Extensions) {
    if (-not $EventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { return @() }
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($path in @($EventArgs.Data.GetData([Windows.DataFormats]::FileDrop))) {
        if ([IO.Directory]::Exists($path)) { foreach ($file in @(Get-ChildItem -LiteralPath $path -File -Recurse | Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() })) { $paths.Add($file.FullName) } }
        elseif ($Extensions -contains [IO.Path]::GetExtension($path).ToLowerInvariant()) { $paths.Add($path) }
    }
    return @($paths.ToArray())
}
function Set-DropFeedback($Card, $EventArgs) {
    $accepted = $EventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop) -and $Card.IsEnabled
    $EventArgs.Effects = $(if ($accepted) { 'Copy' } else { 'None' }); $EventArgs.Handled = $true
    if ($accepted) { $Card.BorderBrush = '#4F76B6'; $Card.Background = '#FAFCFF' }
}
function Clear-DropFeedback($Card) { $Card.ClearValue([Windows.Controls.Border]::BorderBrushProperty); $Card.ClearValue([Windows.Controls.Border]::BackgroundProperty) }
function Test-CountBox($Box) {
    $n = 0; $valid = [int]::TryParse($Box.Text, [ref]$n) -and $n -ge 1 -and $n -le 120
    if ($valid) { $Box.ClearValue([Windows.Controls.Control]::BorderBrushProperty) } else { $Box.BorderBrush = '#D9534F' }
    Update-RunSummary
}

function Update-SeedCount {
    $used = @($script:Seeds | Where-Object { $_.Use }).Count
    $controls.SeedCount.Text = $(if ($script:Seeds.Count) { '{0}개 중 {1}개 사용' -f $script:Seeds.Count, $used } else { '등록된 씨드 없음' })
    $controls.SeedEmpty.Visibility = $(if ($script:Seeds.Count) { 'Collapsed' } else { 'Visible' })
    $controls.SeedToggleAll.Content = $(if ($script:Seeds.Count -and $used -eq $script:Seeds.Count) { '모두 해제' } else { '모두 사용' })
    foreach ($name in @('SeedToggleAll','RemoveSeeds','ClearSeeds')) { $controls[$name].IsEnabled = $script:Seeds.Count -gt 0 }
    Update-RunSummary; Request-AutoSave
}
function Update-KeywordSummary {
    foreach ($set in @(@{ checks = $script:KeywordChecks; summary = 'KeywordSummary'; clear = 'KeywordClear' }, @{ checks = $script:RefKeywordChecks; summary = 'RefKeywordSummary'; clear = 'RefKeywordClear' })) {
        if ($null -eq $set.checks) { continue }
        $n = @($set.checks | Where-Object { $_.IsChecked }).Count
        $controls[$set.summary].Text = $(if ($n) { '선택 ' + $n + '개' } else { '선택 없음' })
        $controls[$set.clear].Visibility = $(if ($n) { 'Visible' } else { 'Collapsed' })
    }
    Update-RunSummary; Request-AutoSave
}
# Plain-language preview of what the next run will do, including how many paid API calls to expect.
function Update-RunSummary {
    $text = ''; $warn = $false
    if ($script:CurrentView -eq 'generator') {
        $used = @($script:Seeds | Where-Object { $_.Use }).Count
        $picked = @($script:KeywordChecks | Where-Object { $_.IsChecked }).Count
        $count = 0; $validCount = [int]::TryParse($controls.Count.Text, [ref]$count) -and $count -ge 1 -and $count -le 120
        if (-not $script:Seeds.Count) { $text = '씨드 XMP를 등록하면 생성할 수 있어요'; $warn = $true }
        elseif (-not $used) { $text = '사용할 씨드를 하나 이상 체크하세요'; $warn = $true }
        elseif (-not $validCount) { $text = '생성 개수는 1–120 사이로 입력하세요'; $warn = $true }
        else {
            $text = '씨드 {0}개 · 키워드 {1} · 후보 {2}개' -f $used, $(if ($picked) { $picked.ToString() + '개' } else { '자동' }), $count
            $text += $(if ($controls.UseAi.IsChecked) { ' · AI 호출 약 ' + [Math]::Ceiling($count / 12) + '회' } else { ' · 로컬 변주 (API 비용 없음)' })
        }
    } elseif ($script:CurrentView -eq 'reference') {
        $photos = $script:References.Count; $mode = $controls.RefMode.SelectedItem.Tag
        $count = 0; $validCount = [int]::TryParse($controls.RefCount.Text, [ref]$count) -and $count -ge 1 -and $count -le 120
        if (-not $photos) { $text = '레퍼런스 사진을 추가하면 생성할 수 있어요'; $warn = $true }
        elseif (-not $validCount) { $text = '총 생성 개수는 1–120 사이로 입력하세요'; $warn = $true }
        elseif ($mode -eq 'individual' -and $count -lt $photos) { $text = '사진별 모드는 총 생성 개수가 사진 수(' + $photos + ') 이상이어야 해요'; $warn = $true }
        else {
            $batches = [Math]::Ceiling($photos / 4); $search = $(if ($controls.RefSearch.IsChecked) { 1 } else { 0 })
            $calls = $batches + $search + $(if ($mode -eq 'individual') { $batches } else { 1 })
            $text = '레퍼런스 {0}장 · {1} · 후보 {2}개 · API 약 {3}회{4}' -f $photos, $(if ($mode -eq 'individual') { '사진별 스타일' } else { '공통 스타일' }), $count, $calls, $(if ($search) { ' (검색 포함)' } else { '' })
        }
    }
    $controls.RunSummary.Text = $text
    $controls.RunSummary.Foreground = $(if ($warn) { '#8A5A12' } else { '#1F2A3D' })
    $controls.RunSummary.Visibility = $(if ($text) { 'Visible' } else { 'Collapsed' })
}

function Add-Seeds($Paths) {
    $errors = New-Object Collections.Generic.List[string]; $added = 0; $skipped = 0
    foreach ($path in @($Paths)) {
        try {
            $seed = Get-Seed $path
            if (@($script:Seeds | Where-Object { $_.id -eq $seed.id }).Count) { $skipped++; continue }
            $seed.path = Import-ProjectFile $path 'seeds'; $script:Seeds.Add($seed); $added++
        }
        catch { $errors.Add([IO.Path]::GetFileName($path) + ': ' + $_.Exception.Message) }
    }
    Update-SeedCount
    if ($added -or $skipped) { Set-Status ('씨드 {0}개 추가{1}{2}' -f $added, $(if ($skipped) { ' · 이미 등록된 ' + $skipped + '개 건너뜀' } else { '' }), $(if ($added -and $script:ProjectRoot) { ' · 프로젝트에 복사됨' } else { '' })) }
    if ($errors.Count) { Show-Notice ($errors -join "`n") '일부 파일을 읽지 못했습니다' }
}
function Remove-SelectedSeeds { foreach ($item in @($controls.SeedGrid.SelectedItems)) { [void]$script:Seeds.Remove($item) }; Update-SeedCount }
function Set-AiPhoto([string]$Path) {
    $Path = Import-ProjectFile $Path 'photos'
    $script:Photo = $Path
    $controls.PhotoPath.Text = $(if ($Path) { [IO.Path]::GetFileName($Path) } else { 'JPG/PNG · 1024px 이하로 줄여 분석에만 사용합니다' })
    $controls.PhotoPath.ToolTip = $(if ($Path) { $Path } else { $null })
    $controls.PhotoThumb.Source = $(if ($Path) { New-Thumbnail $Path 120 } else { $null })
    $controls.PhotoClear.Visibility = $(if ($Path) { 'Visible' } else { 'Collapsed' })
    Request-AutoSave
}
function Set-SeedMask([string]$Path) {
    $Path = Import-ProjectFile $Path 'masks'
    $script:Mask = $Path
    $controls.MaskPath.Text = $(if ($Path) { [IO.Path]::GetFileName($Path) } else { '선택 안 함' })
    $controls.MaskPath.ToolTip = $(if ($Path) { $Path } else { $null })
    $controls.MaskClear.Visibility = $(if ($Path) { 'Visible' } else { 'Collapsed' })
    Request-AutoSave
}
$script:Seeds.Add_CollectionChanged({ Update-SeedCount })
$controls.SeedGrid.AddHandler([Windows.Controls.Primitives.ToggleButton]::ClickEvent, [Windows.RoutedEventHandler]{ Update-SeedCount })
$controls.SeedGrid.Add_PreviewKeyDown({ param($sender, $e) if ($e.Key -eq 'Delete') { Remove-SelectedSeeds; $e.Handled = $true } })
$controls.SeedCard.Add_DragOver({ param($sender, $e) Set-DropFeedback $sender $e })
$controls.SeedCard.Add_DragLeave({ param($sender, $e) Clear-DropFeedback $sender })
$controls.SeedCard.Add_Drop({ param($sender, $e) Clear-DropFeedback $sender; $paths = @(Get-DropPaths $e @('.xmp')); if ($paths.Count) { Add-Seeds $paths } else { Set-Status 'XMP 파일이나 XMP가 든 폴더를 놓아 주세요.' 'error' } })
$controls.AddFiles.Add_Click({ Add-Seeds (Pick-Files 'Lightroom preset (*.xmp)|*.xmp' $true) })
$controls.AddFolder.Add_Click({ $folder = Pick-Folder ''; if ($folder) { Add-Seeds @(Get-ChildItem -LiteralPath $folder -Filter '*.xmp' -File -Recurse | ForEach-Object { $_.FullName }) } })
$controls.Demo.Add_Click({ Add-Seeds @(Get-ChildItem -LiteralPath (Join-Path $script:AppRoot 'examples') -Filter '*.xmp' | ForEach-Object { $_.FullName }); Set-Status '예제는 동작 확인용 가상 씨드입니다. 실제 취향에는 내 프리셋을 사용하세요.' })
$controls.ClearSeeds.Add_Click({
    if ($script:Seeds.Count -and [Windows.MessageBox]::Show($window, ('등록한 씨드 ' + $script:Seeds.Count + '개를 목록에서 모두 뺄까요? 원본 파일은 그대로 남습니다.'), '씨드 비우기', 'YesNo', 'Question') -eq 'Yes') { $script:Seeds.Clear() }
})
$controls.RemoveSeeds.Add_Click({ if (-not $controls.SeedGrid.SelectedItems.Count) { Set-Status '목록에서 뺄 씨드 행을 먼저 선택하세요.' 'error'; return }; Remove-SelectedSeeds })
$controls.SeedToggleAll.Add_Click({
    $target = @($script:Seeds | Where-Object { $_.Use }).Count -ne $script:Seeds.Count
    foreach ($seed in $script:Seeds) { $seed.Use = $target }
    $controls.SeedGrid.Items.Refresh(); Update-SeedCount
})
$controls.KeywordClear.Add_Click({ foreach ($check in $script:KeywordChecks) { $check.IsChecked = $false } })
$controls.Fidelity.Add_ValueChanged({ $controls.FidelityValue.Text = [int]$controls.Fidelity.Value })
$controls.Variation.Add_ValueChanged({ $controls.VariationValue.Text = [int]$controls.Variation.Value })
$controls.Count.Add_TextChanged({ Test-CountBox $controls.Count })
$controls.Count.Add_PreviewTextInput({ param($sender, $e) if ($e.Text -notmatch '^\d+$') { $e.Handled = $true } })
$controls.UseAi.Add_Checked({ Update-RunSummary }); $controls.UseAi.Add_Unchecked({ Update-RunSummary })
$controls.PhotoButton.Add_Click({ $files = @(Pick-Files 'Photo (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png' $false); if ($files.Count) { try { Set-AiPhoto $files[0] } catch { Show-Notice $_.Exception.Message '분석용 사진' } } })
$controls.PhotoClear.Add_Click({ Set-AiPhoto '' })
$controls.MaskButton.Add_Click({ $files = @(Pick-Files 'Mask preset (*.xmp)|*.xmp' $false); if ($files.Count) { try { Set-SeedMask $files[0] } catch { Show-Notice $_.Exception.Message '마스크 템플릿' } } })
$controls.MaskClear.Add_Click({ Set-SeedMask '' })
$controls.ChooseOutput.Add_Click({ $folder = Pick-Folder $controls.Output.Text; if ($folder) { $controls.Output.Text = $folder } })
$controls.OpenOutput.Add_Click({ Open-Folder $script:LastFolder })
# One OpenAI key serves both creation screens; it only lives in these two PasswordBoxes.
$controls.ApiKey.Add_PasswordChanged({ if (-not $script:SyncingKey -and $controls.RefApiKey.Password -ne $controls.ApiKey.Password) { $script:SyncingKey = $true; $controls.RefApiKey.Password = $controls.ApiKey.Password; $script:SyncingKey = $false } })
$controls.RefApiKey.Add_PasswordChanged({ if (-not $script:SyncingKey -and $controls.ApiKey.Password -ne $controls.RefApiKey.Password) { $script:SyncingKey = $true; $controls.ApiKey.Password = $controls.RefApiKey.Password; $script:SyncingKey = $false } })

function Set-Busy([bool]$Busy) {
    foreach ($name in @('GeneratorForm','ReferenceForm','ProjectPick')) { $controls[$name].IsEnabled = -not $Busy }
    $controls.Generate.IsEnabled = -not $Busy; $controls.Cancel.IsEnabled = $Busy
    $controls.Cancel.Visibility = $(if ($Busy) { 'Visible' } else { 'Collapsed' })
    $controls.Progress.Visibility = $(if ($Busy) { 'Visible' } else { 'Collapsed' }); $controls.Progress.IsIndeterminate = $true
    Set-StatePill $(if ($Busy) { 'busy' } else { 'idle' })
}
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)
$timer.Add_Tick({
    if (-not $script:Job) { return }
    if ($script:Job.State -eq 'Running' -or $script:Job.State -eq 'NotStarted') {
        $elapsed = ([DateTime]::Now - $script:JobStarted).ToString('m\:ss')
        Set-StatePill $(if ($script:CancelRequested) { 'cancel' } else { 'busy' }) ($(if ($script:CancelRequested) { '중지 중 · ' } else { '생성 중 · ' }) + $elapsed)
        $progress = @($script:Job.ChildJobs[0].Progress | Select-Object -Last 1)
        if ($progress.Count -and -not $script:CancelRequested) {
            $controls.Status.Text = $progress[0].StatusDescription
            $percent = $progress[0].PercentComplete
            $controls.Progress.IsIndeterminate = $percent -lt 0
            if ($percent -ge 0) { $controls.Progress.Value = $percent }
        }
        return
    }
    $timer.Stop(); Set-Busy $false; Refresh-Dashboard
    $reply = @(Receive-Job $script:Job -ErrorAction SilentlyContinue)
    $state = $script:Job.State
    Remove-Job $script:Job -Force; $script:Job = $null
    if ($script:ActiveRequest.cancelPath -and [IO.File]::Exists($script:ActiveRequest.cancelPath)) { [IO.File]::Delete($script:ActiveRequest.cancelPath) }
    $requestedCount = $script:ActiveRequest.count; $mode = $(if ($script:ActiveRequest.generationMode -eq 'reference') { '레퍼런스' } elseif ($script:ActiveRequest.useAi) { 'AI 설계' } else { '로컬 변주' })
    $script:ActiveRequest = $null; $script:CancelRequested = $false
    if ($state -eq 'Stopped') { Set-Status '중지됨. 이미 처리된 API 요청은 과금될 수 있습니다.' 'error'; return }
    if (-not $reply.Count -or -not $reply[-1].success) {
        $message = $(if ($reply.Count) { $reply[-1].error } else { '작업 프로세스를 실행하지 못했습니다.' })
        $partial = $(if ($reply.Count) { $reply[-1] } else { $null })
        Set-Status $(if ($partial.cancelled) { '중지됨' } else { '생성 실패' }) 'error'
        if ($partial.folder) {
            $saved = @($partial.rows).Count
            Show-Results @($partial.rows) $partial.folder $(if ($partial.cancelled) { '생성을 중지했어요' } else { '생성을 끝까지 완료하지 못했어요' }) ('저장된 XMP {0}/{1}개 · {2} · {3}' -f $saved, $requestedCount, $mode, $partial.folder) $true
            $controls.Status.Text += ' · 저장된 XMP ' + $saved + '/' + $requestedCount + '개'
        }
        Set-ResultNotice $message
        if (-not $partial.cancelled) { Show-Notice $message '생성 실패' 'Error' }
        return
    }
    $result = $reply[-1].result
    $saved = @($result.rows).Count
    $usage = 'XMP {0}/{1}개 · 입력 {2:N0} / 출력 {3:N0} 토큰' -f $saved, $requestedCount, $result.inputTokens, $result.outputTokens
    if ($null -ne $result.cost) { $usage += ' · 예상 $' + ([double]$result.cost).ToString('0.0000', [Globalization.CultureInfo]::InvariantCulture) }
    $meta = '{0} · 요청 {1}개 중 {2}개 저장{3} · {4}' -f $mode, $requestedCount, $saved, $(if ($saved -lt $requestedCount) { ' (유사 후보 제외)' } else { '' }), $result.folder
    Show-Results @($result.rows) $result.folder ('프리셋 ' + $saved + '개를 만들었어요') $meta $false
    Set-ResultNotice (@($result.warnings) -join "`n")
    Set-Status $usage 'success'
})
function Start-Generation {
    if ($script:Job) { return }
    try {
        if ($script:CurrentView -eq 'reference') {
            $request = New-ReferenceRequest
        } else {
        [void]$controls.SeedGrid.CommitEdit(); [void]$controls.SeedGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true)
        $seeds = @($script:Seeds | Where-Object { $_.Use })
        if (-not $seeds.Count) { Set-View 'generator'; throw '사용할 씨드 XMP를 하나 이상 선택하세요.' }
        $count = 0; if (-not [int]::TryParse($controls.Count.Text, [ref]$count) -or $count -lt 1 -or $count -gt 120) { throw '생성 개수는 1부터 120까지입니다.' }
        if ($controls.UseAi.IsChecked -and [string]::IsNullOrWhiteSpace($controls.ApiKey.Password)) { $controls.ApiKey.Focus(); throw 'API 키를 입력하거나 AI 사용을 끄세요. AI를 끄면 API 비용 없이 로컬 규칙으로 변주합니다.' }
        if ($controls.UseAi.IsChecked -and [string]::IsNullOrWhiteSpace($controls.Model.Text)) { throw 'API 모델을 입력하세요.' }
        if ([string]::IsNullOrWhiteSpace($controls.Output.Text)) { throw '저장 폴더를 지정하세요.' }
        $maskCheck = $null
        if ($script:Mask) { $maskCheck = Read-Xmp $script:Mask; if (-not @($maskCheck.Desc.SelectNodes('crs:MaskGroupBasedCorrections | crs:PaintBasedCorrections', $maskCheck.Ns)).Count) { throw '템플릿에 마스크가 없습니다.' } }
        $request = @{ seeds = $seeds; count = $count; fidelity = [int]$controls.Fidelity.Value; variation = [int]$controls.Variation.Value;
            keywordIds = @($script:KeywordChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag });
            useAi = [bool]$controls.UseAi.IsChecked; apiKey = $controls.ApiKey.Password; model = $controls.Model.Text.Trim();
            photo = $script:Photo; note = $controls.Note.Text; maskTemplate = $script:Mask; maskTemplateHash = $maskCheck.Hash; varyMasks = [bool]$controls.VaryMasks.IsChecked;
            output = [IO.Path]::GetFullPath($controls.Output.Text); randomSeed = (Get-Random -Minimum 1 -Maximum 2147483647) }
        }
        $request.cancelPath = Join-Path ([IO.Path]::GetTempPath()) ('SeedLab-Cancel-' + [Guid]::NewGuid().ToString('N'))
        $script:CancelRequested = $false
        Record-RunStart $request; $script:ActiveRequest = $request
        Set-Busy $true; $script:JobStarted = [DateTime]::Now
        Set-Status $(if ($request.generationMode -eq 'reference') { '레퍼런스 분석·검색·보정값 추정 중… 사용량 대시보드에서 진행된 호출을 확인할 수 있어요.' } elseif ($request.useAi) { 'AI가 방향을 설계하고 있습니다…' } else { '씨드 기반 변주를 생성하고 있습니다…' }) 'busy'
        $script:Job = Start-Job -ScriptBlock { param($root, $req); try { . (Join-Path $root 'functions.ps1'); @{ success = $true; result = (Run-Generation $req $root) } } catch { @{ success = $false; error = $_.Exception.Message; cancelled = ($_.Exception -is [OperationCanceledException]); folder = $req.runFolder; rows = $(if ($req.exportedRows) { @($req.exportedRows.ToArray()) } else { @() }) } } } -ArgumentList $script:AppRoot, $request
        $timer.Start()
    } catch { Set-Busy $false; if ($script:ActiveRequest -and -not $script:Job) { Record-RunFinish $script:ActiveRequest 'failed'; $script:ActiveRequest = $null; Refresh-Dashboard }; Show-Notice $_.Exception.Message '확인' }
}
$controls.Generate.Add_Click({ Start-Generation })
$controls.Cancel.Add_Click({ Stop-TrackedJob })

foreach ($name in @('Note','RefNote','Model','RefModel','Output','RefOutput','Count','RefCount')) { $controls[$name].Add_TextChanged({ Request-AutoSave }) }
foreach ($name in @('Fidelity','Variation','RefFidelity','RefVariation')) { $controls[$name].Add_ValueChanged({ Request-AutoSave }) }
foreach ($name in @('UseAi','VaryMasks','RefSearch','RefSubject','RefBackground')) { $controls[$name].Add_Checked({ Request-AutoSave }); $controls[$name].Add_Unchecked({ Request-AutoSave }) }
foreach ($name in @('RefMode','RefSubjectGroup','RefBackgroundGroup')) { $controls[$name].Add_SelectionChanged({ Request-AutoSave }) }
$script:References.Add_CollectionChanged({ Request-AutoSave })
$controls.ApiKey.Add_PasswordChanged({ if ($controls.RememberKey.IsChecked) { Request-AutoSave } })

function Update-KeyHint {
    $text = $(if ($controls.RememberKey.IsChecked) { 'Windows 계정으로 암호화해 이 PC에만 저장 · 두 화면 공용' } else { '꺼 두면 키는 메모리에만 있고 앱을 닫을 때 지워집니다' })
    $controls.KeyHint.Text = $text; $controls.RefKeyHint.Text = $text
}
function Set-RememberKey([bool]$On) {
    if ($script:SyncingRemember) { return }
    $script:SyncingRemember = $true
    try {
        foreach ($name in @('RememberKey','RefRememberKey')) { if ([bool]$controls[$name].IsChecked -ne $On) { $controls[$name].IsChecked = $On } }
        if (-not $script:Restoring) {
            if ($On -and $controls.ApiKey.Password) { try { Save-ApiKey $controls.ApiKey.Password; Set-Status 'API 키를 암호화해 이 PC에 저장했습니다.' 'success' } catch { Set-Status ('API 키를 저장하지 못했습니다: ' + $_.Exception.Message) 'error' } }
            elseif ($On) { Set-Status '키를 입력하면 이 PC에 암호화해 저장합니다.' }
            elseif (Remove-ApiKey) { Set-Status '저장된 API 키를 삭제했습니다.' }
        }
    } finally { $script:SyncingRemember = $false }
    Update-KeyHint
}
foreach ($name in @('RememberKey','RefRememberKey')) { $controls[$name].Add_Checked({ Set-RememberKey $true }); $controls[$name].Add_Unchecked({ Set-RememberKey $false }) }
$controls.ProjectPick.Add_Click({
    $folder = Pick-Folder $(if ($script:ProjectRoot) { $script:ProjectRoot } else { [Environment]::GetFolderPath('MyDocuments') }) '프로젝트로 쓸 폴더를 고르거나 새 폴더를 만드세요. 기존 Seed Lab 프로젝트 폴더를 고르면 그 작업을 엽니다.'
    if ($folder) { try { Open-Project $folder $true } catch { Show-Notice $_.Exception.Message '프로젝트' } }
})
$controls.ProjectOpenFolder.Add_Click({ Open-Folder $script:ProjectRoot })
# Last line of defense: report handler errors instead of closing the whole app.
$window.Dispatcher.Add_UnhandledException({ param($sender, $e)
    $e.Handled = $true
    if ($script:LastUnhandled -and ([DateTime]::Now - $script:LastUnhandled).TotalSeconds -lt 2) { return }
    $script:LastUnhandled = [DateTime]::Now; Show-Notice ('예상하지 못한 오류가 발생했습니다.' + "`n" + $e.Exception.Message) '오류' 'Error'
})

$script:StartProject = ''
$script:StartView = Restore-Settings
$script:Restoring = $true
try { $savedKey = Read-ApiKey; if ($savedKey) { $controls.ApiKey.Password = $savedKey; Set-RememberKey $true } }
catch { Set-Status '저장된 API 키를 읽지 못했습니다. 다른 Windows 계정이나 PC에서 저장된 키일 수 있으니 다시 입력하세요.' 'error' }
finally { $script:Restoring = $false }
Update-KeyHint
if ($script:StartProject) {
    if ([IO.File]::Exists((Join-Path $script:StartProject $script:ProjectFileName))) { try { Open-Project $script:StartProject } catch { Set-Status ('지난 프로젝트를 열지 못했습니다: ' + $_.Exception.Message) 'error' } }
    else { Set-Status ('지난 프로젝트 폴더를 찾을 수 없습니다: ' + $script:StartProject) 'error' }
}
Update-ProjectCard

$window.Add_PreviewKeyDown({ param($sender, $e)
    $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -eq [Windows.Input.ModifierKeys]::Control
    if ($ctrl) {
        $view = switch ($e.Key.ToString()) { { $_ -in 'D1','NumPad1' } { 'generator' } { $_ -in 'D2','NumPad2' } { 'reference' } { $_ -in 'D3','NumPad3' } { 'results' } { $_ -in 'D4','NumPad4' } { 'dashboard' } }
        if ($view) { Set-View $view; $e.Handled = $true }
        elseif ($e.Key -eq [Windows.Input.Key]::Enter) { if ($controls.Generate.IsVisible -and $controls.Generate.IsEnabled) { Start-Generation }; $e.Handled = $true }
        elseif ($e.Key -eq [Windows.Input.Key]::O -and -not $script:Job) {
            if ($script:CurrentView -eq 'generator') { Add-Seeds (Pick-Files 'Lightroom preset (*.xmp)|*.xmp' $true) } elseif ($script:CurrentView -eq 'reference') { Add-References (Pick-Files 'Reference photos (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png' $true) }
            $e.Handled = $true
        }
    } elseif ($e.Key -eq [Windows.Input.Key]::F5 -and $script:CurrentView -eq 'dashboard') { Refresh-Dashboard; $e.Handled = $true }
})
$window.Add_Closing({ param($sender, $e)
    if ($script:Job -and $script:Job.State -in @('Running','NotStarted')) {
        if ([Windows.MessageBox]::Show($window, '생성 작업이 진행 중입니다. 창을 닫으면 작업을 중지합니다. 그래도 닫을까요?', '작업 진행 중', 'YesNo', 'Warning') -ne 'Yes') { $e.Cancel = $true; return }
    }
    Save-AutoNow; Save-Settings
    $timer.Stop(); $usageTimer.Stop(); $controls.ApiKey.Clear(); $controls.RefApiKey.Clear(); Stop-TrackedJob -Force; if ($script:Job) { Remove-Job $script:Job -Force }
})
$window.Add_Loaded({ Update-SeedCount; Update-ReferenceCount; Update-KeywordSummary; Set-View $script:StartView })
[void]$window.ShowDialog()
} catch {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show($_.Exception.Message, 'Preset Seed Lab 시작 오류')
}
