# =============================================================================
# Активация workflow в n8n — простой скрипт
# Запускать ПОСЛЕ import-workflows.ps1
# =============================================================================

param(
    [switch]$Deactivate = $false,  # выключить вместо включения
    [switch]$Force = $false        # перезагрузить (deactivate + activate)
)

# ---- НАСТРОЙКИ (впиши свои) ----
$n8n    = "http://130.100.92.170:5678"
$apiKey = "ТВОЙ_API_КЛЮЧ_ИЗ_n8n"   # Settings → API → Create API key
$prefix = "[GigaChat] "
# ---------------------------------

$headers = @{ "X-N8N-API-KEY" = $apiKey }

Write-Host "Получаю список workflow..."
try {
    $list = Invoke-RestMethod -Uri "$n8n/api/v1/workflows?limit=250" -Headers $headers
} catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)"
    exit 1
}

$success = 0
$fail = 0

foreach ($wf in $list.data) {
    if ($wf.isArchived) { continue }
    if ($wf.name -notlike "$prefix*") { continue }

    $id = $wf.id
    $name = $wf.name

    if ($Force -and -not $Deactivate -and $wf.active) {
        # Перезагрузка (deactivate → activate)
        Write-Host "Перезагружаю: $name" -NoNewline
        try {
            Invoke-RestMethod -Method POST -Uri "$n8n/api/v1/workflows/$id/deactivate" -Headers $headers | Out-Null
            Start-Sleep -Milliseconds 200
            Invoke-RestMethod -Method POST -Uri "$n8n/api/v1/workflows/$id/activate" -Headers $headers | Out-Null
            Write-Host " OK" -ForegroundColor Green
            $success++
        } catch {
            Write-Host " ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
            $fail++
        }
        continue
    }

    if ($Deactivate) {
        if (-not $wf.active) { Write-Host "Уже выключен: $name"; continue }
        Write-Host "Выключаю: $name" -NoNewline
    } else {
        if ($wf.active) { Write-Host "Уже активен: $name"; continue }
        Write-Host "Активирую: $name" -NoNewline
    }

    $action = if ($Deactivate) { "deactivate" } else { "activate" }
    try {
        Invoke-RestMethod -Method POST -Uri "$n8n/api/v1/workflows/$id/$action" -Headers $headers | Out-Null
        Write-Host " OK" -ForegroundColor Green
        $success++
    } catch {
        Write-Host " ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "Готово. Успешно: $success, Ошибок: $fail"
