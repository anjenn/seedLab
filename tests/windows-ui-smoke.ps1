param([string]$AppRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('SeedLab UI ' + [Guid]::NewGuid().ToString('N'))
$previousUsage = $env:SEEDLAB_TEST_USAGE_DIR
$env:SEEDLAB_TEST_USAGE_DIR = Join-Path $temporary 'usage'
$windowElement = $null
function Find-Control([string]$Id) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $element = $windowElement.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
    if (-not $element) { throw ('Missing UI control: ' + $Id) }
    return $element
}
function Click-Control([string]$Id) { (Find-Control $Id).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke() }
function Check-KeywordChoices([string]$PageId) {
    $catalog = Get-Content -LiteralPath (Join-Path $AppRoot 'keywords.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::CheckBox)
    $checkboxes = (Find-Control $PageId).FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    $names = @($checkboxes | ForEach-Object { $_.Current.Name })
    foreach ($keyword in $catalog) {
        if (@($names | Where-Object { $_ -eq $keyword.label }).Count -ne 1) { throw ('Missing or duplicate keyword: ' + $keyword.label) }
    }
    return $checkboxes
}
try {
    # Seeds come from a prepared project that the app reopens on start, exercising project restore.
    $project = Join-Path $temporary 'Smoke Project'; $seedDir = Join-Path $project 'seeds'
    [void][IO.Directory]::CreateDirectory($seedDir); [void][IO.Directory]::CreateDirectory($env:SEEDLAB_TEST_USAGE_DIR)
    $fixtures = @(Get-ChildItem -LiteralPath (Join-Path $AppRoot 'tests\fixtures\seeds') -Filter '*.xmp')
    foreach ($fixture in $fixtures) { Copy-Item -LiteralPath $fixture.FullName -Destination $seedDir }
    $state = @{ app = 'PresetSeedLab'; version = 1; seeds = @($fixtures | ForEach-Object { @{ file = ('seeds\' + $_.Name); use = $true } }) }
    [IO.File]::WriteAllText((Join-Path $project 'seedlab-project.json'), ($state | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $env:SEEDLAB_TEST_USAGE_DIR 'settings.json'), (@{ version = 1; project = $project; view = 'generator' } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $before = @([Diagnostics.Process]::GetProcessesByName('powershell') | ForEach-Object { $_.Id })
    $null = Start-Process -FilePath (Join-Path $AppRoot 'PresetSeedLab.exe') -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not $windowElement -and [DateTime]::UtcNow -lt $deadline) {
        $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
        foreach ($item in $windows) {
            if ($item.Current.Name -eq 'Seed Lab · Preset Studio' -and $item.Current.ProcessId -notin $before) { $windowElement = $item; break }
        }
        if (-not $windowElement) { Start-Sleep -Milliseconds 200 }
    }
    if (-not $windowElement) { throw 'EXE did not open its WPF window within 20 seconds.' }
    Click-Control 'GeneratorNav'
    if ((Find-Control 'SeedCount').Current.Name -ne ('{0}개 중 {0}개 사용' -f $fixtures.Count)) { throw ('Project seeds were not restored: ' + (Find-Control 'SeedCount').Current.Name) }
    $choices = Check-KeywordChoices 'GeneratorPage'
    $styleChoice = @($choices | Where-Object { $_.Current.Name -eq '큐트 판타지' })[0]
    $styleChoice.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle()
    $toggle = (Find-Control 'UseAi').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
    if ($toggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::Off) { $toggle.Toggle() }
    if ($toggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::Off) { throw 'Offline mode was not enabled.' }
    (Find-Control 'Output').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue((Join-Path $temporary 'output'))
    Click-Control 'Generate'
    $deadline = [DateTime]::UtcNow.AddSeconds(40); $status = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        $status = (Find-Control 'Status').Current.Name
        if ($status -match '^XMP \d+/\d+개') { break }
        Start-Sleep -Milliseconds 200
    }
    if ($status -notmatch '^XMP 24/24') { throw ('UI generation failed: ' + $status) }
    $files = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'output') -Filter '*.xmp' -Recurse)
    if ($files.Count -ne 24) { throw 'UI did not export 24 XMP files.' }
    $manifestPath = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'output') -Filter 'manifest.json' -Recurse)[0].FullName
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($manifest.variants | Where-Object { $_.Details.keywordId -ne 'cute_fantasy' }).Count) { throw 'Selected style keyword was not used for generation.' }
    Click-Control 'ReferenceNav'; $null = Find-Control 'RefAdd'
    $null = Check-KeywordChoices 'ReferencePage'
    Click-Control 'MixNav'; Click-Control 'MixFromSeeds'
    $mixToggle = (Find-Control 'MixUseAi').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
    if ($mixToggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::Off) { throw 'Mix AI was enabled by default.' }
    (Find-Control 'RatioSlider').GetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern).SetValue(25)
    (Find-Control 'MixOutput').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue((Join-Path $temporary 'mix-output'))
    Click-Control 'Generate'
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    while ([DateTime]::UtcNow -lt $deadline) {
        $status = (Find-Control 'Status').Current.Name
        if ($status -match '^XMP 1/1') { break }
        Start-Sleep -Milliseconds 200
    }
    if ($status -notmatch '^XMP 1/1') { throw ('UI mix generation failed: ' + $status) }
    $mixFile = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'mix-output') -Filter 'manifest.json' -Recurse)[0].FullName
    $mixture = Get-Content -LiteralPath $mixFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($mixture.mode -ne 'mix' -or $mixture.mix.useAi -or $mixture.usage.calls -ne 0 -or @($mixture.mix.sources).Count -ne 12 -or $mixture.mix.sources[0].weight -ne 25) { throw 'UI mixture did not preserve source weights or local mode.' }
    Click-Control 'DashboardNav'
    if ((Find-Control 'RunKpi').Current.Name -ne '2') { throw 'Dashboard did not show both local generations.' }
    Write-Host 'PASS: real EXE launch, project restore of 12 seeds, navigation, local generation through Start-Job, 24 seed XMPs and 1 mixed XMP, ratio slider, results and persistent dashboard.'
    Write-Host 'No external API was called. The test used isolated usage/output directories.'
} finally {
    if ($windowElement) { $windowElement.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close() }
    $env:SEEDLAB_TEST_USAGE_DIR = $previousUsage
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
