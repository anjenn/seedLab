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
    Click-Control 'GeneratorNav'; Click-Control 'Demo'
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
    Click-Control 'DashboardNav'
    if ((Find-Control 'RunKpi').Current.Name -ne '1') { throw 'Dashboard did not show the local generation.' }
    Write-Host 'PASS: real EXE launch, navigation, sample import, local generation through Start-Job, 24 XMPs, results and persistent dashboard.'
    Write-Host 'No external API was called. The test used isolated usage/output directories.'
} finally {
    if ($windowElement) { $windowElement.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close() }
    $env:SEEDLAB_TEST_USAGE_DIR = $previousUsage
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
