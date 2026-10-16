function Format-Count($Value) { return ([long]$Value).ToString('N0') }
function Format-Cost($Value) { if ($null -eq $Value) { return '—' }; return '$' + ([double]$Value).ToString('0.0000', [Globalization.CultureInfo]::InvariantCulture) }
function Set-View([string]$View) {
    $script:CurrentView = $View
    foreach ($name in @('DashboardPage','GeneratorPage','ReferencePage','MixPage','ResultsPage')) { $controls[$name].Visibility = 'Collapsed' }
    foreach ($name in @('DashboardNav','GeneratorNav','ReferenceNav','MixNav','ResultsNav')) { $controls[$name].Background = 'Transparent'; $controls[$name].Foreground = Get-Brush 'SideNavBrush'; $controls[$name].FontWeight = [Windows.FontWeights]::Normal }
    switch ($View) {
        'dashboard' { $page = 'DashboardPage'; $nav = 'DashboardNav'; $title = '사용량 대시보드'; $subtitle = '토큰과 이용 추세를 한눈에 확인하세요.' }
        'generator' { $page = 'GeneratorPage'; $nav = 'GeneratorNav'; $title = '프리셋 생성'; $subtitle = '내 스타일을 유지하며 새로운 보정 방향을 탐색하세요.' }
        'reference' { $page = 'ReferencePage'; $nav = 'ReferenceNav'; $title = '레퍼런스로 만들기'; $subtitle = '사진의 스타일을 분석해 전체·인물·배경 보정값을 추정합니다.' }
        'mix' { $page = 'MixPage'; $nav = 'MixNav'; $title = '프리셋 믹스매치'; $subtitle = '내 프리셋의 톤과 색감을 원하는 비율로 조합하세요.' }
        'results' { $page = 'ResultsPage'; $nav = 'ResultsNav'; $title = '생성 결과'; $subtitle = '후보별 변화와 보정값을 확인하고 Lightroom의 프리셋 가져오기로 불러오세요.' }
    }
    $controls[$page].Visibility = 'Visible'; $controls[$nav].Background = Get-Brush 'SideActiveBrush'; $controls[$nav].Foreground = [Windows.Media.Brushes]::White; $controls[$nav].FontWeight = [Windows.FontWeights]::SemiBold
    $controls.PageTitle.Text = $title; $controls.PageTitle.ToolTip = $subtitle
    # The primary action only appears where a run can be configured.
    $controls.Generate.Visibility = $(if ($View -in @('generator','reference','mix')) { 'Visible' } else { 'Collapsed' })
    foreach ($pair in @(@('generator','CountGroup'), @('reference','RefCountGroup'), @('mix','MixCountGroup'))) { $controls[$pair[1]].Visibility = $(if ($View -eq $pair[0]) { 'Visible' } else { 'Collapsed' }) }
    $controls.Generate.Content = $(if ($View -eq 'mix') { '믹스매치 생성' } elseif ($View -eq 'reference') { '레퍼런스 프리셋 생성' } else { '프리셋 생성' })
    $controls.OpenOutput.Visibility = $(if ($script:LastFolder -and $View -ne 'results') { 'Visible' } else { 'Collapsed' })
    Update-RunSummary
    if ($View -eq 'dashboard') { Refresh-Dashboard }
}
function Add-ChartText([string]$Text, [double]$X, [double]$Y, [double]$Size = 10) {
    $label = [Windows.Controls.TextBlock]::new(); $label.Text = $Text; $label.FontSize = $Size; $label.Foreground = Get-Brush 'FaintBrush'
    [Windows.Controls.Canvas]::SetLeft($label, $X); [Windows.Controls.Canvas]::SetTop($label, $Y); [void]$controls.TrendCanvas.Children.Add($label)
}
function Draw-UsageChart {
    if (-not $script:Dashboard) { return }
    $canvas = $controls.TrendCanvas; $canvas.Children.Clear()
    $width = $canvas.ActualWidth; if ($width -lt 100) { $width = 560 }
    $metric = $controls.TrendMetric.SelectedItem.Tag
    $series = @($script:Dashboard.chart); if (-not $series.Count) { return }
    $maximum = 0.0
    foreach ($day in $series) { $value = $(if ($metric -eq 'tokens') { $day.totalTokens } elseif ($metric -eq 'calls') { $day.calls } else { $day.runs }); $maximum = [Math]::Max($maximum, [double]$value) }
    if ($metric -eq 'tokens') { $top = $(if ($maximum -eq 0) { 100 } else { $unit = [Math]::Pow(10, [Math]::Floor([Math]::Log10($maximum))); [Math]::Ceiling($maximum / $unit) * $unit }) }
    else { $top = [Math]::Max(4, [Math]::Ceiling($maximum / 4) * 4) }
    $left = 42.0; $plotWidth = [Math]::Max(50, $width - 54); $plotHeight = 146.0; $baseY = 160.0
    for ($tick = 0; $tick -le 4; $tick++) {
        $y = $baseY - $plotHeight * $tick / 4
        $line = [Windows.Shapes.Line]::new(); $line.X1 = $left; $line.X2 = $width - 5; $line.Y1 = $y; $line.Y2 = $y; $line.Stroke = Get-Brush 'ChartGridBrush'; $line.StrokeThickness = 1
        [void]$canvas.Children.Add($line)
        $n = $top * $tick / 4; $label = $(if ($n -ge 1000000) { ($n/1000000).ToString('0.#') + 'M' } elseif ($n -ge 1000) { ($n/1000).ToString('0.#') + 'k' } else { $n.ToString('0') })
        Add-ChartText $label 0 ($y - 7)
    }
    $slot = $plotWidth / $series.Count; $barWidth = [Math]::Min(36, $slot * 0.56)
    for ($i = 0; $i -lt $series.Count; $i++) {
        $day = $series[$i]; $x = $left + $slot * ($i + 0.5) - $barWidth / 2
        $tooltip = '{0}: 입력 {1:N0} · 출력 {2:N0} · 호출 {3} · 생성 작업 {4}' -f $day.date, $day.inputTokens, $day.outputTokens, $day.calls, $day.runs
        if ($day.endDate) { $tooltip = $day.date + ' ~ ' + $day.endDate + "`n" + $tooltip }
        $bottomValue = $(if ($metric -eq 'tokens') { [double]$day.inputTokens } elseif ($metric -eq 'calls') { [double]$day.calls } else { [double]$day.runs })
        $bottomHeight = $bottomValue / $top * $plotHeight
        if ($bottomHeight -gt 0) {
            $bar = [Windows.Shapes.Rectangle]::new(); $bar.Width = $barWidth; $bar.Height = $bottomHeight
            $bar.Fill = Get-Brush $(if ($metric -eq 'tokens') { 'ChartInputBrush' } else { 'AccentBrush' }); $bar.RadiusX = 4; $bar.RadiusY = 4; $bar.ToolTip = $tooltip
            [Windows.Controls.Canvas]::SetLeft($bar, $x); [Windows.Controls.Canvas]::SetTop($bar, $baseY - $bottomHeight); [void]$canvas.Children.Add($bar)
        }
        if ($metric -eq 'tokens' -and $day.outputTokens -gt 0) {
            $bar = [Windows.Shapes.Rectangle]::new(); $bar.Width = $barWidth; $bar.Height = [double]$day.outputTokens / $top * $plotHeight
            $bar.Fill = Get-Brush 'AccentBrush'; $bar.RadiusX = 4; $bar.RadiusY = 4; $bar.ToolTip = $tooltip
            [Windows.Controls.Canvas]::SetLeft($bar, $x); [Windows.Controls.Canvas]::SetTop($bar, $baseY - $bottomHeight - $bar.Height); [void]$canvas.Children.Add($bar)
        }
        if ($series.Count -le 10 -or $i % [Math]::Ceiling($series.Count / 6.0) -eq 0 -or $i -eq $series.Count - 1) { Add-ChartText $day.date.Substring(5).Replace('-', '/') ($x + $barWidth / 2 - 15) 172 }
    }
    if ($maximum -eq 0) { Add-ChartText '이 기간에는 기록된 사용량이 없어요.' ([Math]::Max(50, $width / 2 - 100)) 70 13 }
    $controls.TrendLegend.Visibility = $(if ($metric -eq 'tokens') { 'Visible' } else { 'Collapsed' })
}
function Refresh-Dashboard {
    if ($script:DashboardBusy) { return }
    $script:DashboardBusy = $true
    try {
        $days = $controls.Period.SelectedItem.Tag
        $model = $(if ($controls.ModelFilter.SelectedItem) { $controls.ModelFilter.SelectedItem.Tag } else { 'all' })
        $data = Get-UsageDashboard $script:AppRoot $days $model; $script:Dashboard = $data
        $t = $data.totals
        $controls.TokenKpi.Text = Format-Count $t.totalTokens
        $controls.TokenKpi.ToolTip = '입력 ' + (Format-Count $t.inputTokens) + ' · 출력 ' + (Format-Count $t.outputTokens) + ' (추론 포함)'
        $controls.TokenComparison.Text = $(if ($null -ne $data.changePercent) { '이전 기간 대비 ' + ([int]$data.changePercent).ToString('+0;-0;0') + '%' } elseif ($t.totalTokens -gt 0) { '확인된 응답의 입력 + 출력' } else { '아직 기록된 토큰이 없습니다' })
        $controls.CallKpi.Text = Format-Count $t.calls
        $controls.CallDetail.Text = '확인된 응답 ' + $t.knownCalls + '건 · 미확인 ' + $t.unknownCalls + '건'
        $controls.RunKpi.Text = Format-Count $t.runs
        $controls.RunDetail.Text = '프리셋 ' + (Format-Count $t.generatedPresets) + '개 · 레퍼런스 작업 ' + $t.referenceRuns + '회'
        $controls.CostKpi.Text = Format-Cost $(if ($t.calls -gt 0 -and $t.costUnknownCalls -eq $t.calls) { $null } else { $t.estimatedUSD })
        $controls.CostDetail.Text = $(if ($t.costUnknownCalls -gt 0) { '비용 미확인 ' + $t.costUnknownCalls + '건 제외' } else { '기록 시점의 요금표 기준' })
        $controls.CacheDetail.Text = '검색 ' + $t.webSearchCalls + '회 · 캐시 입력 ' + (Format-Count $t.cachedTokens) + ' · 추론 ' + (Format-Count $t.reasoningTokens) + ' (출력에 포함)'
        $controls.TrendRange.Text = $data.start.Replace('-', '.') + ' — ' + $data.end.Replace('-', '.') + ' · ' + $data.chartUnit + ' 합계'
        $controls.ModelUsage.ItemsSource = @($data.models | ForEach-Object { [pscustomobject]@{ Model = $_.model; Tokens = (Format-Count $_.totalTokens); Cost = $(if ($_.costUnknownCalls -eq $_.calls) { '—' } else { Format-Cost $_.estimatedUSD }) } })
        $controls.UsageCalls.ItemsSource = @($data.calls | Select-Object -First 200 | ForEach-Object {
            $_ | Add-Member -NotePropertyName InputText -NotePropertyValue $(if ($_.UsageKnown) { Format-Count $_.Input } else { '—' })
            $_ | Add-Member -NotePropertyName OutputText -NotePropertyValue $(if ($_.UsageKnown) { Format-Count $_.Output } else { '—' })
            $_ | Add-Member -NotePropertyName TotalText -NotePropertyValue $(if ($_.UsageKnown) { Format-Count $_.Total } else { '—' })
            $_ | Add-Member -NotePropertyName CostText -NotePropertyValue (Format-Cost $_.USD)
            $_ | Add-Member -NotePropertyName PhaseText -NotePropertyValue $(if ($_.Phase -eq 'mix_design') { '믹스매치 설계' } elseif ($_.Phase -eq 'reference_analysis') { '사진 분석' } elseif ($_.Phase -eq 'reference_research') { '보정 검색' } elseif ($_.Phase -eq 'reference_recipe') { '보정 추정' } else { '씨드 변주' })
            $_
        })
        $controls.UsageRuns.ItemsSource = @($data.runs | Select-Object -First 200)
        $controls.HistoryHint.Text = '최근 200건 · CSV는 선택 기간 전체'
        $notices = @()
        if ($t.unknownCalls -gt 0) { $notices += '응답을 받지 못한 ' + $t.unknownCalls + '건은 토큰·비용 합계에서 제외됩니다. 실제 청구와 차이가 있을 수 있어요.' }
        if ($data.unreadableLines -gt 0 -or $data.discardedEvents -gt 0) { $notices += '읽을 수 없는 기록 ' + ($data.unreadableLines + $data.discardedEvents) + '건을 건너뛰었습니다.' }
        $controls.UsageNotice.Visibility = $(if ($notices.Count) { 'Visible' } else { 'Collapsed' }); $controls.UsageNoticeText.Text = $notices -join ' '
        $controls.ModelFilter.Items.Clear()
        $item = [Windows.Controls.ComboBoxItem]::new(); $item.Content = '전체 모델'; $item.Tag = 'all'; [void]$controls.ModelFilter.Items.Add($item)
        foreach ($id in @($data.allModels | Sort-Object)) { $item = [Windows.Controls.ComboBoxItem]::new(); $item.Content = $id; $item.Tag = $id; [void]$controls.ModelFilter.Items.Add($item) }
        $controls.ModelFilter.SelectedIndex = 0
        foreach ($item in $controls.ModelFilter.Items) { if ($item.Tag -eq $model) { $controls.ModelFilter.SelectedItem = $item; break } }
        Draw-UsageChart
    } catch {
        $controls.UsageNotice.Visibility = 'Visible'; $controls.UsageNoticeText.Text = '사용 기록을 표시하지 못했습니다: ' + $_.Exception.Message
    } finally { $script:DashboardBusy = $false }
}
function Export-UsageCsv([bool]$Daily) {
    if (-not $script:Dashboard) { return }
    $dialog = [Microsoft.Win32.SaveFileDialog]::new(); $dialog.Filter = 'CSV (*.csv)|*.csv'
    $dialog.FileName = $(if ($Daily) { 'SeedLab_Daily.csv' } else { 'SeedLab_Calls.csv' })
    if (-not $dialog.ShowDialog($window)) { return }
    $rows = $(if ($Daily) { @($script:Dashboard.daily) } else { @($script:Dashboard.calls) })
    if (-not $rows.Count) { [void][Windows.MessageBox]::Show('내보낼 사용 기록이 없습니다.', 'CSV 내보내기'); return }
    $csv = $(if ($Daily) { $rows | Select-Object date,inputTokens,outputTokens,totalTokens,cachedTokens,cacheWriteTokens,reasoningTokens,webSearchCalls,searchUSD,calls,knownCalls,unknownCalls,costUnknownCalls,runs,referenceRuns,generatedPresets,estimatedUSD } else { $rows | Select-Object Time,Model,Mode,Phase,Status,Input,Output,Total,Cached,CacheWrite,Reasoning,SearchCalls,SearchUSD,USD,UsageKnown,PriceDate,RunId,EventId })
    # Prevent spreadsheet formulas in editable model IDs / imported strings.
    foreach ($row in $csv) { foreach ($p in $row.PSObject.Properties) { if ($p.Value -is [string] -and $p.Value -match '^\s*[=+@-]') { $p.Value = "'" + $p.Value } } }
    $csv | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
    Set-Status ('CSV를 저장했습니다 · ' + $dialog.FileName) 'success'
}
function Stop-TrackedJob([switch]$Force) {
    if (-not $script:Job -or $script:Job.State -notin @('Running','NotStarted')) { return }
    if (-not $Force) {
        [IO.File]::WriteAllText($script:ActiveRequest.cancelPath, 'cancel')
        $script:CancelRequested = $true; $controls.Cancel.IsEnabled = $false
        Set-Status '중지 요청됨 · 현재 API 응답의 사용량을 기록한 뒤 종료합니다.' 'error'; Set-StatePill 'cancel'
        return
    }
    Stop-Job $script:Job
    if ($script:Job.State -eq 'Stopped' -and $script:ActiveRequest) {
        $last = @((Read-UsageEvents).events | Where-Object { $_.kind -eq 'run_result' -and $_.runId -eq $script:ActiveRequest.runId } | Select-Object -Last 1)
        $folder = ''
        if ($last.Count -and $last[0].status -eq 'completed') { return }
        if ($last.Count) { $script:ActiveRequest.generatedCount = $last[0].generatedCount; $folder = $last[0].folder }
        if ($folder) {
            $manifestPath = Join-Path $folder 'manifest.json'
            if (Test-Path -LiteralPath $manifestPath) {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $manifest.status = 'cancelled'; Write-AtomicJson $manifestPath $manifest
            }
        }
        Record-RunFinish $script:ActiveRequest 'cancelled' $folder
        if ($script:ActiveRequest.cancelPath -and [IO.File]::Exists($script:ActiveRequest.cancelPath)) { [IO.File]::Delete($script:ActiveRequest.cancelPath) }
    }
}
$controls.DashboardNav.Add_Click({ Set-View 'dashboard' })
$controls.GeneratorNav.Add_Click({ Set-View 'generator' })
$controls.ReferenceNav.Add_Click({ Set-View 'reference' })
$controls.MixNav.Add_Click({ Set-View 'mix' })
$controls.ResultsNav.Add_Click({ Set-View 'results' })
$controls.RefreshUsage.Add_Click({ Refresh-Dashboard })
$controls.Period.Add_SelectionChanged({ if (-not $script:DashboardBusy) { Refresh-Dashboard } })
$controls.ModelFilter.Add_SelectionChanged({ if (-not $script:DashboardBusy) { Refresh-Dashboard } })
$controls.TrendMetric.Add_SelectionChanged({ Draw-UsageChart })
$controls.TrendCanvas.Add_SizeChanged({ Draw-UsageChart })
$controls.UsageRuns.Add_MouseDoubleClick({ $row = $controls.UsageRuns.SelectedItem; if ($row -and $row.Folder -and [IO.Directory]::Exists($row.Folder)) { Open-Folder $row.Folder } elseif ($row) { Set-Status '이 작업의 결과 폴더를 찾을 수 없습니다.' 'error' } })
$controls.ExportUsage.Add_Click({ Export-UsageCsv $false })
$controls.ExportDaily.Add_Click({ Export-UsageCsv $true })
$usageTimer = [Windows.Threading.DispatcherTimer]::new(); $usageTimer.Interval = [TimeSpan]::FromSeconds(5)
$usageTimer.Add_Tick({ if ($script:CurrentView -eq 'dashboard' -and $script:Job) { Refresh-Dashboard } }); $usageTimer.Start()
