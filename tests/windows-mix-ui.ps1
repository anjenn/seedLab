param([string]$ScreenshotPath = '')
$ErrorActionPreference = 'Stop'
$previousUsage = $env:SEEDLAB_TEST_USAGE_DIR
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('SeedLab Mix UI ' + [Guid]::NewGuid().ToString('N'))
$env:SEEDLAB_TEST_USAGE_DIR = Join-Path $temporary 'usage'
$script:MixUiTestRoot = Split-Path $PSScriptRoot -Parent
$script:MixUiTemporary = $temporary; $script:MixUiScreenshot = $ScreenshotPath
function Assert-MixUI([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
$exercise = @'
$window.Left = -12000; $window.Top = 0; $window.ShowInTaskbar = $false
$window.Show(); $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
try {
    function Show-Notice([string]$Message,[string]$Title,[string]$Icon) { throw ($Title + ': ' + $Message) }
    if ($script:MixUiPass -eq 1) {
        Assert-MixUI (-not $controls.MixUseAi.IsChecked) 'AI was not opt-in.'
        $script:ProjectRoot = Join-Path $script:MixUiTemporary 'My Mix Project'; [void][IO.Directory]::CreateDirectory($script:ProjectRoot)
        Add-Seeds @(Get-ChildItem -LiteralPath (Join-Path $script:AppRoot 'tests\fixtures\seeds') -Filter '*.xmp' | Select-Object -First 2 | ForEach-Object { $_.FullName })
        Set-View 'mix'
        $controls.MixFromSeeds.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert-MixUI ($script:MixSources.Count -eq 2) 'Import from seeds failed.'
        $script:MixSources[0].weight = 25.0; $script:MixSources[1].weight = 75.0; $controls.MixGrid.Items.Refresh(); Update-MixSummary
        $controls.MixTone.SelectedValue = $script:MixSources[1].id; $controls.MixTexture.SelectedValue = 'base'
        $controls.MixNote.Text = '핑크 톤은 부드럽게'; $controls.MixCount.Text = '1'; $controls.MixVariation.Value = 60
        $controls.MixOutput.Text = Join-Path $script:ProjectRoot 'outputs'
        $controls.MixApiKey.Password = 'TEST_SHARED_MIX_KEY'
        Assert-MixUI ($controls.ApiKey.Password -eq 'TEST_SHARED_MIX_KEY' -and $controls.RefApiKey.Password -eq 'TEST_SHARED_MIX_KEY') 'API key did not sync to all screens.'
        $controls.MixUseAi.IsChecked = $true
        Assert-MixUI ($controls.RunSummary.Text.Contains('AI 설계 약 1회')) 'AI call estimate missing.'
        $controls.MixUseAi.IsChecked = $false
        Assert-MixUI ($controls.RunSummary.Text.Contains('API 비용 없음')) 'Local run summary missing.'
        $req = New-MixRequest
        Assert-MixUI (-not $req.useAi -and -not $req.apiKey -and $req.generationMode -eq 'mix') 'Local UI request included AI credentials.'
        $controls.MixRandomAll.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert-MixUI ($controls.MixBase.SelectedValue -eq 'random' -and @((Get-MixGroupChoices).Values | Where-Object { $_ -eq 'random' }).Count -eq 4 -and $controls.MixRandomHint.Visibility -eq 'Visible') 'Random-all button did not set all groups and the base.'
        Refresh-MixChoices
        Assert-MixUI ($controls.MixBase.SelectedValue -eq 'random' -and $controls.MixTone.SelectedValue -eq 'random') 'Refreshing sources discarded random choices.'
        $controls.MixColor.SelectedValue = $script:MixSources[1].id
        $partial = New-MixRequest
        Assert-MixUI ($partial.mixGroups.tone -eq 'random' -and $partial.mixGroups.color -eq $script:MixSources[1].id) 'Random groups cannot be combined with an explicit donor.'
        $controls.MixColor.SelectedValue = 'random'; $controls.MixCount.Text = '3'
        $request = New-MixRequest
        Assert-MixUI ($request.baseId -eq 'random' -and $request.mixGroups.curves -eq 'random' -and $controls.RunSummary.Text.Contains('랜덤 혼합')) 'Random UI request or summary is incorrect.'
        for ($paint = 0; $paint -lt 4; $paint++) { $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle); $window.UpdateLayout(); Start-Sleep -Milliseconds 40 }
        if ($script:MixUiScreenshot) {
            $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($window); $png = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream = [IO.File]::Create($script:MixUiScreenshot); try { $png.Save($stream) } finally { $stream.Dispose() }
        }
        Start-Generation
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while ($script:Job -and [DateTime]::UtcNow -lt $deadline) { $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background); Start-Sleep -Milliseconds 100 }
        Assert-MixUI (-not $script:Job -and $controls.Status.Text -like 'XMP 3/3*') ('Mix generation failed: ' + $controls.Status.Text)
        Assert-MixUI ($controls.DetailReason.Text.Contains('%') -and $controls.DetailMode.Text -eq '믹스매치') 'Result details omitted mixture ratios.'
        foreach ($row in $controls.Results.Items) {
            Assert-MixUI ($row.Details.randomized -and $row.Details.baseId -in @($script:MixSources.id) -and $row.Reason.Contains('기준 프리셋:')) 'Random output lost its actual base or original recipe.'
        }
        $ledger = Read-UsageEvents
        Assert-MixUI (@($ledger.events | Where-Object { $_.kind -eq 'api' }).Count -eq 0) 'Local UI mix recorded an API call.'
        Set-View 'mix'; Save-AutoNow; Save-Settings
        $projectText = [IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'seedlab-project.json'))
        $state = $projectText | ConvertFrom-Json
        Assert-MixUI (@($state.mixSources).Count -eq 2 -and $state.mixSources[0].file -like 'seeds\*' -and $state.mixSources[0].weight -eq 25) 'Mixture was not saved with relative copied paths.'
        Assert-MixUI (-not $projectText.Contains('TEST_SHARED_MIX_KEY') -and -not ([IO.File]::ReadAllText((Get-SettingsPath))).Contains('TEST_SHARED_MIX_KEY')) 'Shared key leaked into project/settings.'
    } else {
        Assert-MixUI ($script:CurrentView -eq 'mix' -and $script:MixSources.Count -eq 2) 'Mix tab/sources did not restore.'
        Assert-MixUI ($script:MixSources[0].weight -eq 25 -and $script:MixSources[1].weight -eq 75) 'Mixture weights did not restore.'
        Assert-MixUI ($controls.MixBase.SelectedValue -eq 'random' -and $controls.MixTone.SelectedValue -eq 'random' -and $controls.MixTexture.SelectedValue -eq 'random') 'Component choices did not restore.'
        Assert-MixUI ($controls.MixCount.Text -eq '3' -and $controls.MixVariation.Value -eq 60 -and $controls.MixNote.Text -eq '핑크 톤은 부드럽게') 'Mix options did not restore.'
        Assert-MixUI ($controls.Results.Items.Count -eq 3 -and $controls.Detail.Text.Contains('기준 프리셋')) 'Last mixture results/warnings did not restore.'
    }
} finally { if ($script:Job) { Stop-TrackedJob -Force; Remove-Job $script:Job -Force; $script:Job = $null }; $window.Close() }
'@
try {
    $source = [IO.File]::ReadAllText((Join-Path $script:MixUiTestRoot 'app.ps1'), [Text.Encoding]::UTF8)
    $source = $source.Replace('$PSScriptRoot', '$script:MixUiTestRoot').Replace('[void]$window.ShowDialog()', $exercise)
    $source = $source.Replace('[void][Windows.MessageBox]::Show($_.Exception.Message, ''Preset Seed Lab 시작 오류'')', 'throw')
    for ($script:MixUiPass = 1; $script:MixUiPass -le 2; $script:MixUiPass++) { & ([scriptblock]::Create($source)) }
    Write-Host 'PASS: real app mix page, source import, random-all/per-component choices, random base, local Start-Job generation, shared optional key, output details, no API, project/options/last-results restore.'
} catch { Write-Host ('FAIL: ' + $_.Exception.Message + "`n" + $_.ScriptStackTrace); exit 1 }
finally { $env:SEEDLAB_TEST_USAGE_DIR = $previousUsage; if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force } }
