# Persistence: app preferences, the optional saved API key, and project folders.
# Functions only; event wiring lives in app.ps1 so ValidateOnWindows can dot-source this file.
Add-Type -AssemblyName System.Security
$script:ProjectRoot = ''; $script:ProjectFileName = 'seedlab-project.json'; $script:Restoring = $false
$script:KeyEntropy = [Text.Encoding]::UTF8.GetBytes('PresetSeedLab.ApiKey.v1')

# The API key is stored only on request, encrypted with Windows DPAPI for the current user.
# It lives next to the usage log, never in settings.json or in a project folder that may be synced.
function Get-ApiKeyPath { return Join-Path (Get-UsageDirectory) 'api-key.json' }
function Save-ApiKey([string]$Key) {
    $protected = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($Key), $script:KeyEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [void][IO.Directory]::CreateDirectory((Get-UsageDirectory))
    Write-AtomicJson (Get-ApiKeyPath) @{ version = 1; protection = 'DPAPI CurrentUser'; data = [Convert]::ToBase64String($protected) }
}
function Read-ApiKey {
    $path = Get-ApiKeyPath; if (-not [IO.File]::Exists($path)) { return $null }
    $stored = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($stored.data), $script:KeyEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Text.Encoding]::UTF8.GetString($bytes)
}
function Remove-ApiKey { $path = Get-ApiKeyPath; if ([IO.File]::Exists($path)) { [IO.File]::Delete($path); return $true }; return $false }

# Paths inside the project are stored relative so a project folder can be moved or copied.
function Test-InProject([string]$Path) {
    if (-not $script:ProjectRoot -or -not $Path) { return $false }
    return [IO.Path]::GetFullPath($Path).StartsWith($script:ProjectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}
function ConvertTo-ProjectPath([string]$Path) {
    if (-not $Path) { return '' }
    if (Test-InProject $Path) { return [IO.Path]::GetFullPath($Path).Substring($script:ProjectRoot.TrimEnd('\').Length + 1) }
    return $Path
}
function Resolve-ProjectPath([string]$Path) {
    if (-not $Path) { return '' }
    if ([IO.Path]::IsPathRooted($Path) -or -not $script:ProjectRoot) { return $Path }
    return Join-Path $script:ProjectRoot $Path
}
# Copies an added file into <project>\<Kind> so the project stays self-contained.
# Identical content already in the project is reused; other files with the same name get a numbered name.
function Import-ProjectFile([string]$Path, [string]$Kind) {
    if (-not $script:ProjectRoot -or -not $Path -or (Test-InProject $Path)) { return $Path }
    $dir = Join-Path $script:ProjectRoot $Kind; [void][IO.Directory]::CreateDirectory($dir)
    $source = Get-Item -LiteralPath $Path; $hash = $null
    foreach ($existing in @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Length -eq $source.Length })) {
        if (-not $hash) { $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
        if ((Get-FileHash -LiteralPath $existing.FullName -Algorithm SHA256).Hash -eq $hash) { return $existing.FullName }
    }
    $target = Join-Path $dir $source.Name; $n = 2
    while ([IO.File]::Exists($target)) { $target = Join-Path $dir ('{0} ({1}){2}' -f $source.BaseName, $n, $source.Extension); $n++ }
    [IO.File]::Copy($Path, $target, $false)
    return $target
}

# Generation options shared by settings.json (app defaults) and project files.
function Get-WorkValues([bool]$Relative = $false) {
    $output = $controls.Output.Text; $refOutput = $controls.RefOutput.Text; $mixOutput = $controls.MixOutput.Text
    if ($Relative) { $output = ConvertTo-ProjectPath $output; $refOutput = ConvertTo-ProjectPath $refOutput; $mixOutput = ConvertTo-ProjectPath $mixOutput }
    return @{ output = $output; model = $controls.Model.Text.Trim(); count = $controls.Count.Text; fidelity = [int]$controls.Fidelity.Value; variation = [int]$controls.Variation.Value; useAi = [bool]$controls.UseAi.IsChecked;
        refOutput = $refOutput; refModel = $controls.RefModel.Text.Trim(); refMode = $controls.RefMode.SelectedItem.Tag; refCount = $controls.RefCount.Text; refSearch = [bool]$controls.RefSearch.IsChecked;
        refFidelity = [int]$controls.RefFidelity.Value; refVariation = [int]$controls.RefVariation.Value;
        mixOutput = $mixOutput; mixModel = $controls.MixModel.Text.Trim(); mixCount = $controls.MixCount.Text; mixVariation = [int]$controls.MixVariation.Value; mixUseAi = [bool]$controls.MixUseAi.IsChecked }
}
function Set-WorkValues($Values) {
    if (-not $Values) { return }
    foreach ($pair in @(@('output','Output'), @('model','Model'), @('count','Count'), @('refOutput','RefOutput'), @('refModel','RefModel'), @('refCount','RefCount'), @('mixOutput','MixOutput'), @('mixModel','MixModel'), @('mixCount','MixCount'))) {
        if (-not [string]::IsNullOrWhiteSpace($Values.($pair[0]))) { $controls[$pair[1]].Text = $(if ($pair[0] -like '*utput') { Resolve-ProjectPath ([string]$Values.($pair[0])) } else { [string]$Values.($pair[0]) }) }
    }
    foreach ($pair in @(@('fidelity','Fidelity'), @('variation','Variation'), @('refFidelity','RefFidelity'), @('refVariation','RefVariation'), @('mixVariation','MixVariation'))) { if ($null -ne $Values.($pair[0])) { $controls[$pair[1]].Value = [Math]::Max(0, [Math]::Min(100, [int]$Values.($pair[0]))) } }
    if ($null -ne $Values.useAi) { $controls.UseAi.IsChecked = [bool]$Values.useAi }
    if ($null -ne $Values.mixUseAi) { $controls.MixUseAi.IsChecked = [bool]$Values.mixUseAi }
    if ($null -ne $Values.refSearch) { $controls.RefSearch.IsChecked = [bool]$Values.refSearch }
    foreach ($item in $controls.RefMode.Items) { if ($item.Tag -eq $Values.refMode) { $controls.RefMode.SelectedItem = $item } }
}

# App preferences (window, last view, last project, default options). Never the API key.
function Get-SettingsPath { return Join-Path (Get-UsageDirectory) 'settings.json' }
function Read-Settings { try { $path = Get-SettingsPath; if ([IO.File]::Exists($path)) { return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json) } } catch { }; return $null }
function Save-Settings {
    try {
        $bounds = $(if ($window.WindowState -eq 'Normal') { [Windows.Rect]::new(0, 0, $window.ActualWidth, $window.ActualHeight) } else { $window.RestoreBounds })
        $settings = Get-WorkValues
        $settings.version = 1; $settings.project = $script:ProjectRoot
        $settings.view = $(if ($script:CurrentView -eq 'results') { 'generator' } else { $script:CurrentView })
        $settings.window = @{ width = $(if ($bounds.IsEmpty) { 0 } else { [int]$bounds.Width }); height = $(if ($bounds.IsEmpty) { 0 } else { [int]$bounds.Height }); maximized = ($window.WindowState -eq 'Maximized') }
        [void][IO.Directory]::CreateDirectory((Get-UsageDirectory)); Write-AtomicJson (Get-SettingsPath) $settings
    } catch { }
}
function Restore-Settings {
    $s = Read-Settings; if (-not $s) { return 'generator' }
    Set-WorkValues $s
    $script:StartProject = [string]$s.project
    $area = [Windows.SystemParameters]::WorkArea
    if ($s.window -and [int]$s.window.width -ge $window.MinWidth -and [int]$s.window.height -ge $window.MinHeight) { $window.Width = [Math]::Min([int]$s.window.width, $area.Width); $window.Height = [Math]::Min([int]$s.window.height, $area.Height) }
    if ($s.window.maximized) { $window.WindowState = 'Maximized' }
    return $(if ($s.view -in @('generator','reference','mix','dashboard')) { $s.view } else { 'generator' })
}

# Project folders: seedlab-project.json plus copies of every added file.
function Get-ProjectState {
    return @{ app = 'PresetSeedLab'; version = 1; updatedAt = [DateTime]::UtcNow.ToString('o'); options = (Get-WorkValues $true)
        seeds = @($script:Seeds | ForEach-Object { @{ file = (ConvertTo-ProjectPath $_.path); use = [bool]$_.Use } })
        keywords = @($script:KeywordChecks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
        refKeywords = @($script:RefKeywordChecks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
        seedMask = (ConvertTo-ProjectPath $script:Mask); varyMasks = [bool]$controls.VaryMasks.IsChecked; photo = (ConvertTo-ProjectPath $script:Photo); note = $controls.Note.Text
        references = @($script:References | ForEach-Object { ConvertTo-ProjectPath $_.path }); refTarget = (ConvertTo-ProjectPath $script:ReferenceTarget)
        refMask = (ConvertTo-ProjectPath $script:ReferenceMask); refSubjectIndex = $controls.RefSubjectGroup.SelectedIndex; refBackgroundIndex = $controls.RefBackgroundGroup.SelectedIndex
        refSubject = [bool]$controls.RefSubject.IsChecked; refBackground = [bool]$controls.RefBackground.IsChecked; refNote = $controls.RefNote.Text
        mixSources = @($script:MixSources | ForEach-Object { @{ file = (ConvertTo-ProjectPath $_.path); weight = $_.weight } }); mixBaseId = $controls.MixBase.SelectedValue; mixGroups = (Get-MixGroupChoices); mixNote = $controls.MixNote.Text
        lastFolder = (ConvertTo-ProjectPath $script:LastFolder) }
}
function Save-Project {
    if (-not $script:ProjectRoot -or $script:Restoring) { return }
    try { Write-AtomicJson (Join-Path $script:ProjectRoot $script:ProjectFileName) (Get-ProjectState); Update-ProjectCard ('자동 저장됨 · ' + (Get-Date -Format 'HH:mm')) }
    catch { Update-ProjectCard ('저장하지 못했습니다 · ' + $_.Exception.Message) $true }
}
function Update-ProjectCard([string]$State = '', [bool]$Failed = $false) {
    $open = [bool]$script:ProjectRoot
    $controls.ProjectName.Text = $(if ($open) { [IO.Path]::GetFileName($script:ProjectRoot) } else { '프로젝트를 선택하세요' })
    $controls.ProjectName.ToolTip = $(if ($open) { $script:ProjectRoot } else { $null })
    $controls.ProjectState.Text = $(if ($State) { $State } elseif ($open) { '변경 내용을 자동 저장합니다' } else { '폴더를 선택하면 자동 저장됩니다.' })
    $controls.ProjectState.Foreground = Get-Brush $(if ($Failed) { 'SideDangerBrush' } else { 'SideMutedBrush' })
    $controls.ProjectPick.Content = $(if ($open) { '변경' } else { '폴더 선택' })
    $controls.ProjectPick.Style = $window.FindResource($(if ($open) { 'SideButton' } else { 'Primary' }))
    $controls.ProjectOpenFolder.Visibility = $(if ($open) { 'Visible' } else { 'Collapsed' })
    $controls.ProjectCard.Background = Get-Brush $(if ($open) { 'SidePanelBrush' } else { 'SideAccentPanelBrush' })
}
function Clear-Work {
    $script:Seeds.Clear(); $script:References.Clear(); $script:MixSources.Clear(); Refresh-MixChoices; $controls.MixNote.Text = ''
    foreach ($check in @($script:KeywordChecks) + @($script:RefKeywordChecks)) { $check.IsChecked = $false }
    Set-SeedMask ''; Set-AiPhoto ''; Set-ReferenceTarget ''; Clear-ReferenceMask
    $controls.Note.Text = ''; $controls.RefNote.Text = ''; $controls.VaryMasks.IsChecked = $false; $controls.RefSubject.IsChecked = $true; $controls.RefBackground.IsChecked = $true
    Clear-Results
}
# Moves the current lists into a newly created project by copying their files.
function Import-CurrentWork {
    $failed = 0
    foreach ($seed in @($script:Seeds)) { try { $seed.path = Import-ProjectFile $seed.path 'seeds' } catch { $failed++ } }
    foreach ($source in @($script:MixSources)) { try { $source.path = Import-ProjectFile $source.path 'mix' } catch { $failed++ } }
    foreach ($reference in @($script:References)) { try { $reference.path = Import-ProjectFile $reference.path 'references' } catch { $failed++ } }
    try { if ($script:Mask) { Set-SeedMask $script:Mask } } catch { $failed++ }
    try { if ($script:Photo) { Set-AiPhoto $script:Photo } } catch { $failed++ }
    try { if ($script:ReferenceTarget) { Set-ReferenceTarget $script:ReferenceTarget } } catch { $failed++ }
    try { if ($script:ReferenceMask) { $script:ReferenceMask = Import-ProjectFile $script:ReferenceMask 'masks' } } catch { $failed++ }
    return $failed
}
function Restore-ProjectState($State) {
    $missing = [Collections.Generic.List[string]]::new()
    $script:Restoring = $true
    try {
        Clear-Work
        Set-WorkValues $State.options
        foreach ($entry in @($State.seeds | Where-Object { $_ })) {
            $path = Resolve-ProjectPath $entry.file
            try { $seed = Get-Seed $path; $seed.Use = [bool]$entry.use; if (-not @($script:Seeds | Where-Object { $_.id -eq $seed.id }).Count) { $script:Seeds.Add($seed) } }
            catch { $missing.Add([IO.Path]::GetFileName($path)) }
        }
        foreach ($entry in @($State.mixSources | Where-Object { $_ })) {
            $path = Resolve-ProjectPath $entry.file
            try {
                $source = Get-MixSource $path
                if ($null -ne $entry.weight) { $source.weight = [Math]::Min(100, [Math]::Max(0, [double]$entry.weight)) }
                if ($script:MixSources.Count -lt 12 -and -not @($script:MixSources | Where-Object { $_.id -eq $source.id }).Count) { $script:MixSources.Add($source) }
            } catch { $missing.Add([IO.Path]::GetFileName($path)) }
        }
        if ($State.mixBaseId -in @($script:MixSources | ForEach-Object { $_.id })) { $controls.MixBase.SelectedValue = $State.mixBaseId }
        Set-MixGroupChoices $State.mixGroups; $controls.MixNote.Text = [string]$State.mixNote
        $photos = @()
        foreach ($file in @($State.references | Where-Object { $_ })) { $path = Resolve-ProjectPath $file; if ([IO.File]::Exists($path)) { $photos += $path } else { $missing.Add([IO.Path]::GetFileName($path)) } }
        if ($photos.Count) { Add-References $photos -Quiet }
        foreach ($check in $script:KeywordChecks) { $check.IsChecked = @($State.keywords) -contains [string]$check.Tag }
        foreach ($check in $script:RefKeywordChecks) { $check.IsChecked = @($State.refKeywords) -contains [string]$check.Tag }
        foreach ($item in @(@{ key = 'seedMask'; apply = { param($p) Set-SeedMask $p } }, @{ key = 'photo'; apply = { param($p) Set-AiPhoto $p } }, @{ key = 'refTarget'; apply = { param($p) Set-ReferenceTarget $p } })) {
            $path = Resolve-ProjectPath ([string]$State.($item.key)); if (-not $path) { continue }
            if ([IO.File]::Exists($path)) { & $item.apply $path } else { $missing.Add([IO.Path]::GetFileName($path)) }
        }
        $refMask = Resolve-ProjectPath ([string]$State.refMask)
        if ($refMask) {
            try {
                Set-ReferenceMask $refMask
                foreach ($pair in @(@('refSubjectIndex','RefSubjectGroup'), @('refBackgroundIndex','RefBackgroundGroup'))) { $index = [int]$State.($pair[0]); if ($index -ge -1 -and $index -lt $controls[$pair[1]].Items.Count) { $controls[$pair[1]].SelectedIndex = $index } }
            } catch { $missing.Add([IO.Path]::GetFileName($refMask)) }
        }
        $controls.Note.Text = [string]$State.note; $controls.RefNote.Text = [string]$State.refNote; $controls.VaryMasks.IsChecked = [bool]$State.varyMasks
        if ($null -ne $State.refSubject) { $controls.RefSubject.IsChecked = [bool]$State.refSubject }
        if ($null -ne $State.refBackground) { $controls.RefBackground.IsChecked = [bool]$State.refBackground }
        $last = Resolve-ProjectPath ([string]$State.lastFolder)
        if ($last -and [IO.Directory]::Exists($last)) { try { Restore-LastResults $last } catch { } }
    } finally { $script:Restoring = $false }
    Update-ProjectCard
    $summary = '프로젝트를 열었습니다 · 씨드 {0}개 · 레퍼런스 {1}장' -f $script:Seeds.Count, $script:References.Count
    if ($missing.Count) { Set-Status ($summary + ' · 찾지 못한 파일 ' + $missing.Count + '개 제외: ' + (($missing | Select-Object -First 3) -join ', ')) 'error' } else { Set-Status $summary 'success' }
}
# Opens <Folder>\seedlab-project.json, or (interactively) turns the folder into a new project.
function Open-Project([string]$Folder, [bool]$Interactive = $false) {
    $folder = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
    if ($folder -eq $script:ProjectRoot) { return }
    $file = Join-Path $folder $script:ProjectFileName
    $hasWork = ($script:Seeds.Count + $script:References.Count + $script:MixSources.Count) -gt 0
    if ([IO.File]::Exists($file)) {
        $state = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($state.app -ne 'PresetSeedLab') { throw '이 폴더의 seedlab-project.json은 Seed Lab 프로젝트 파일이 아닙니다.' }
        if ($Interactive -and $hasWork -and -not $script:ProjectRoot) {
            if ((Show-Question ("지금 목록은 프로젝트에 저장되지 않았습니다.`n'" + [IO.Path]::GetFileName($folder) + "' 프로젝트를 열면 현재 목록이 프로젝트 내용으로 바뀝니다. 계속할까요?") '프로젝트 열기' 'OKCancel') -ne 'OK') { return }
        }
        Save-AutoNow
        $script:ProjectRoot = $folder
        Restore-ProjectState $state
        return
    }
    if (-not $Interactive) { return }
    $name = [IO.Path]::GetFileName($folder)
    $note = "'" + $name + "' 폴더를 새 프로젝트로 만듭니다.`n추가한 XMP·사진은 이 폴더의 seeds, references, photos, masks, mix 폴더에 복사되고 작업 상태는 seedlab-project.json에 자동 저장됩니다."
    $carry = $false
    if ($hasWork) {
        $answer = Show-Question ($note + "`n`n지금 목록(씨드 " + $script:Seeds.Count + '개 · 레퍼런스 ' + $script:References.Count + '장 · 믹스매치 ' + $script:MixSources.Count + "개)을 새 프로젝트로 복사할까요?`n예: 복사해서 이어서 작업   아니요: 빈 프로젝트로 시작") '새 프로젝트' 'YesNoCancel'
        if ($answer -eq 'Cancel') { return }; $carry = $answer -eq 'Yes'
    } elseif ((Show-Question $note '새 프로젝트' 'OKCancel') -ne 'OK') { return }
    Save-AutoNow
    [void][IO.Directory]::CreateDirectory($folder)
    $script:ProjectRoot = $folder; $failed = 0
    $script:Restoring = $true
    try { if ($carry) { $failed = Import-CurrentWork } else { Clear-Work }; $controls.Output.Text = Join-Path $folder 'outputs'; $controls.RefOutput.Text = Join-Path $folder 'outputs'; $controls.MixOutput.Text = Join-Path $folder 'outputs' } finally { $script:Restoring = $false }
    Save-Project
    Set-Status ('새 프로젝트를 만들었습니다 · ' + $folder + $(if ($failed) { ' · 복사하지 못한 파일 ' + $failed + '개' } else { '' })) $(if ($failed) { 'error' } else { 'success' })
}
function Restore-LastResults([string]$Folder) {
    $manifestPath = Join-Path $Folder 'manifest.json'; if (-not [IO.File]::Exists($manifestPath)) { return }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $rows = @($manifest.variants | Where-Object { $_ }); $partial = $manifest.status -ne 'completed'
    $mode = $(if ($manifest.mode -eq 'mix') { '믹스매치' } elseif ($manifest.mode -eq 'reference') { '레퍼런스' } elseif ($manifest.mode -eq 'ai') { 'AI 설계' } else { '로컬 변주' })
    $when = ''; try { $when = ([DateTime]$manifest.createdAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } catch { }
    Set-ResultNotice (@($manifest.warnings) -join "`n")
    Show-Results $rows $Folder ('지난 실행 · ' + $(if ($partial) { '부분 결과 ' } else { '프리셋 ' }) + $rows.Count + '개') (($mode, $when, $Folder | Where-Object { $_ }) -join ' · ') $partial $false
}
