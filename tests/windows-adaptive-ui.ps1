param([string]$ScreenshotPath = '')
$ErrorActionPreference = 'Stop'
$previousUsage = $env:SEEDLAB_TEST_USAGE_DIR
$script:MaskUiRoot = Split-Path $PSScriptRoot -Parent
$script:MaskUiTemporary = Join-Path ([IO.Path]::GetTempPath()) ('SeedLab Mask UI ' + [Guid]::NewGuid().ToString('N'))
$script:MaskUiScreenshot = $ScreenshotPath
$env:SEEDLAB_TEST_USAGE_DIR = Join-Path $script:MaskUiTemporary 'usage'
function Assert-MaskUI([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
$exercise = @'
$window.Left = -12000; $window.Top = 0; $window.ShowInTaskbar = $false
$window.Show(); $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
try {
    function Show-Notice([string]$Message,[string]$Title,[string]$Icon) { throw ($Title + ': ' + $Message) }
    if ($script:MaskUiPass -eq 1) {
        Assert-MaskUI ($controls.RefMaskMode.SelectedItem.Tag -eq 'automatic' -and $controls.RefMaskTemplateTools.Visibility -eq 'Collapsed') 'Reference masks still require a template by default.'
        $script:ProjectRoot = Join-Path $script:MaskUiTemporary 'Project'; [void][IO.Directory]::CreateDirectory($script:ProjectRoot)
        Add-Seeds @((Get-ChildItem -LiteralPath (Join-Path $script:AppRoot 'tests\fixtures\seeds') -Filter '*.xmp' | Select-Object -First 1).FullName)
        $photo = Join-Path $script:MaskUiTemporary 'reference.png'; $bitmap = [Drawing.Bitmap]::new(16,16)
        try { $bitmap.Save($photo,[Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
        Add-References @($photo)
        $controls.RefApiKey.Password = 'TEST_MASK_KEY_NOT_SAVED'; $controls.RefSubject.IsChecked = $false; $controls.RefBackground.IsChecked = $true
        Set-View 'reference'
        $request = New-ReferenceRequest
        Assert-MaskUI ($request.referenceMaskMode -eq 'automatic' -and -not $request.referenceMaskTemplate -and -not $request.maskSubject -and $request.maskBackground) 'Automatic reference request needed a template or ignored the flags.'
        if ($script:MaskUiScreenshot) {
            $controls.RefMaskMode.BringIntoView()
            for ($i=0;$i -lt 3;$i++) { $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::ApplicationIdle); $window.UpdateLayout() }
            $image = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $image.Render($window); $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
            $stream = [IO.File]::Create($script:MaskUiScreenshot); try { $encoder.Save($stream) } finally { $stream.Dispose() }
        }
        $controls.RefMaskMode.SelectedIndex = 1
        Assert-MaskUI ($controls.RefMaskTemplateTools.Visibility -eq 'Visible') 'Optional template tools did not appear.'
        $controls.RefMaskMode.SelectedIndex = 0
        Set-View 'generator'; $controls.UseAi.IsChecked = $false; $controls.AutoSubjectMask.IsChecked = $true; $controls.AutoBackgroundMask.IsChecked = $true
        $controls.Count.Text = '1'; $controls.Output.Text = Join-Path $script:ProjectRoot 'outputs'
        Start-Generation
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while ($script:Job -and [DateTime]::UtcNow -lt $deadline) { $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background); Start-Sleep -Milliseconds 100 }
        Assert-MaskUI (-not $script:Job -and $controls.Status.Text -like 'XMP 1/1*') ('Local auto-mask generation failed: ' + $controls.Status.Text)
        $x = Read-Xmp (Join-Path $script:LastFolder $controls.Results.SelectedItem.File)
        Assert-MaskUI (@(Get-ReferenceMaskGroups $x).Count -eq 2 -and $controls.DetailMask.Text.Contains('Lightroom')) 'Generated preset omitted adaptive masks or the apply instruction.'
        $ledger = Read-UsageEvents
        Assert-MaskUI (@($ledger.events | Where-Object { $_.kind -eq 'api' }).Count -eq 0) 'Adding automatic masks called an external API.'
        Set-View 'reference'; Save-AutoNow; Save-Settings
    } else {
        Assert-MaskUI ($controls.AutoSubjectMask.IsChecked -and $controls.AutoBackgroundMask.IsChecked -and -not $controls.UseAi.IsChecked) 'Seed auto-mask options did not restore.'
        Assert-MaskUI ($controls.RefMaskMode.SelectedItem.Tag -eq 'automatic' -and -not $controls.RefSubject.IsChecked -and $controls.RefBackground.IsChecked) 'Reference auto-mask mode or flags did not restore.'
        Assert-MaskUI ($controls.Results.Items.Count -eq 1 -and $controls.Results.SelectedItem.Details.maskInstructions.source -eq 'automatic') 'Saved result lost the mask instructions.'
        # Older projects that stored a template continue to use it.
        $legacy = Get-ProjectState | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $legacy.options.PSObject.Properties.Remove('refMaskMode')
        $legacy.refMask = ConvertTo-ProjectPath (Join-Path $script:LastFolder $controls.Results.SelectedItem.File)
        $legacy.refSubjectIndex = 0; $legacy.refBackgroundIndex = 1
        Restore-ProjectState $legacy
        Assert-MaskUI ($controls.RefMaskMode.SelectedItem.Tag -eq 'template' -and $script:ReferenceMask) 'Legacy project template mode changed.'
    }
} finally { if ($script:Job) { Stop-TrackedJob -Force; Remove-Job $script:Job -Force; $script:Job=$null }; $window.Close() }
'@
try {
    $source = [IO.File]::ReadAllText((Join-Path $script:MaskUiRoot 'app.ps1'),[Text.Encoding]::UTF8)
    $source = $source.Replace('$PSScriptRoot','$script:MaskUiRoot').Replace('[void]$window.ShowDialog()',$exercise)
    $source = $source.Replace('[void][Windows.MessageBox]::Show($_.Exception.Message, ''Preset Seed Lab 시작 오류'')','throw')
    for ($script:MaskUiPass=1;$script:MaskUiPass -le 2;$script:MaskUiPass++) { & ([scriptblock]::Create($source)) }
    Write-Host 'PASS: template-free reference requests, optional template controls, real local Start-Job with both masks and AI off, no API calls, project/options/results restart, legacy templates.'
} catch { Write-Host ('FAIL: '+$_.Exception.Message+"`n"+$_.ScriptStackTrace); exit 1 }
finally { $env:SEEDLAB_TEST_USAGE_DIR=$previousUsage; if (Test-Path -LiteralPath $script:MaskUiTemporary) { Remove-Item -LiteralPath $script:MaskUiTemporary -Recurse -Force } }
