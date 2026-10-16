function Invoke-TrackedResponse($Request, $Body, [string]$Phase, [int]$BatchIndex) {
    Test-GenerationCancelled $Request
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Body.model = $Request.model; $Body.store = $false; $Body.service_tier = 'default'
    if ($Request.model -match '^gpt-[56]') { $Body.reasoning = @{ effort = 'low' } }
    $event = New-TrackingBase ($Request.runId + ':' + $Phase + ':' + $BatchIndex) 'api' $Request.runId $Request.model
    $event.phase = $Phase; $event.mode = $(if ($Request.generationMode -eq 'reference') { 'reference' } else { 'seed' }); $event.batchIndex = $BatchIndex
    $event.status = 'pending'; $event.usageKnown = $false
    Write-UsageEvent $event
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 60 -Compress))
        $response = Invoke-RestMethod -Uri 'https://api.openai.com/v1/responses' -Method Post -Headers @{ Authorization = 'Bearer ' + $Request.apiKey } -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 240
    } catch {
        $watch.Stop(); $event.status = 'failed'; $event.durationMs = $watch.ElapsedMilliseconds
        $event.updatedAtUtc = [DateTime]::UtcNow.ToString('o'); Write-UsageEvent $event
        Test-GenerationCancelled $Request
        throw ('AI 요청 실패 (' + $Phase + '). 사용량 미확인 호출은 대시보드에 별도로 남습니다. ' + $_.Exception.Message)
    }
    $watch.Stop(); $event.durationMs = $watch.ElapsedMilliseconds
    $event.status = $(if ($response.status -eq 'completed') { 'completed' } else { 'incomplete' })
    $refusals = @($response.output | Where-Object { $_.type -eq 'message' } | ForEach-Object { $_.content } | Where-Object { $_.type -eq 'refusal' })
    if ($refusals.Count) { $event.status = 'refused' }
    $event.responseId = $response.id; $event.responseModel = $response.model; $event.serviceTier = $response.service_tier
    $event.priceDate = '2026-10-16'; $event.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $event.usageKnown = ($null -ne $response.usage -and $null -ne $response.usage.input_tokens -and $null -ne $response.usage.output_tokens)
    $event.webSearchCalls = @($response.output | Where-Object { $_.type -eq 'web_search_call' -and $_.action.type -eq 'search' }).Count
    $event.estimatedUSD = $null
    if ($event.usageKnown) {
        $event.inputTokens = [long]$response.usage.input_tokens; $event.outputTokens = [long]$response.usage.output_tokens
        $event.cachedTokens = [long]$response.usage.input_tokens_details.cached_tokens
        $event.cacheWriteTokens = [long]$response.usage.input_tokens_details.cache_write_tokens
        $event.reasoningTokens = [long]$response.usage.output_tokens_details.reasoning_tokens
    }
    # Save billed usage before any content parsing, recipe checks or XMP output.
    Write-UsageEvent $event
    if ($event.usageKnown) {
        try {
            $price = Invoke-Engine $script:TrackingAppRoot @{ operation = 'cost'; model = $response.model; usage = $response.usage; serviceTier = $response.service_tier; searchCalls = $event.webSearchCalls }
            # Aliases may be resolved to a snapshot. Fall back only to the explicitly requested known alias.
            if ($null -eq $price.estimatedUSD) { $price = Invoke-Engine $script:TrackingAppRoot @{ operation = 'cost'; model = $Request.model; usage = $response.usage; serviceTier = $response.service_tier; searchCalls = $event.webSearchCalls } }
            $event.estimatedUSD = $price.estimatedUSD; $event.tokenUSD = $price.tokenUSD; $event.searchUSD = $price.searchUSD
        } catch { $event.estimatedUSD = $null }
        Write-UsageEvent $event
    }
    if (-not $Request.usageSummary) { $Request.usageSummary = @{ inputTokens = 0L; outputTokens = 0L; cachedTokens = 0L; reasoningTokens = 0L; calls = 0; searchCalls = 0; estimatedUSD = 0.0; costKnown = $true } }
    $u = $Request.usageSummary
    $u.inputTokens += [long]$event.inputTokens; $u.outputTokens += [long]$event.outputTokens
    $u.cachedTokens += [long]$event.cachedTokens; $u.reasoningTokens += [long]$event.reasoningTokens
    $u.calls++; $u.searchCalls += $event.webSearchCalls
    if ($null -eq $event.estimatedUSD) { $u.costKnown = $false } else { $u.estimatedUSD += $event.estimatedUSD }
    # A cancellation during HTTP must still account for the returned usage.
    Test-GenerationCancelled $Request
    if ($refusals.Count) { throw 'AI가 요청을 거절했습니다. 입력 사진이나 보정 설명을 변경하세요. 확인된 사용량은 기록되었습니다.' }
    if ($response.status -ne 'completed') { throw ('AI 응답이 완료되지 않았습니다 (' + $Phase + '). 레퍼런스 수를 줄이거나 모델을 변경하세요.') }
    return $response
}
function Get-ResponseText($Response) {
    $parts = @($Response.output | Where-Object { $_.type -eq 'message' } | ForEach-Object { $_.content } | Where-Object { $_.type -eq 'output_text' } | ForEach-Object { $_.text })
    if (-not $parts.Count) { throw 'AI가 분석 결과를 반환하지 않았습니다.' }
    return $parts -join "`n"
}
function New-StructuredBody([string]$Prompt, $Context, $Schema, [string]$Name, [int]$Budget, $Images = @()) {
    $content = @(@{ type = 'input_text'; text = ($Context | ConvertTo-Json -Depth 40 -Compress) })
    foreach ($image in @($Images)) {
        $content += @{ type = 'input_text'; text = $image.label }
        $content += @{ type = 'input_image'; image_url = $image.data; detail = 'high' }
    }
    return @{ input = @(@{ role = 'developer'; content = $Prompt }, @{ role = 'user'; content = $content });
        text = @{ format = @{ type = 'json_schema'; name = $Name; strict = $true; schema = $Schema } }; max_output_tokens = $Budget }
}
