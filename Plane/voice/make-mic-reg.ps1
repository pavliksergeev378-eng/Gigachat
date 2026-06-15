<#
  make-mic-reg.ps1 — генерирует ГОТОВЫЕ .reg-файлы для включения микрофона
  (голосового ввода) на офисном http-адресе. Запускается ОДИН раз айтишником,
  чтобы получить файлы под ваш ТОЧНЫЙ адрес. Сами .reg потом раздаются обычным
  пользователям — двойной клик, без прав администратора.

  Механизм: политика браузера OverrideSecurityRestrictionsOnInsecureOrigin в разделе
  HKEY_CURRENT_USER (поэтому без админа). Браузер начинает считать ваш http-origin
  «защищённым контекстом», и микрофон на http://<ip>:8765 разблокируется.

  АДРЕС (origin) — РОВНО как в адресной строке браузера: схема + хост + порт, без пути.
  Агенты раздаёт Caddy на порту 8765, поэтому обычно это  http://<ip-сервера>:8765
  (или http://имя:8765, или http://имя — если повесили на 80 порт).

  Использование:
    powershell -ExecutionPolicy Bypass -File make-mic-reg.ps1 -Origin "http://192.168.0.100:8765"
    (несколько адресов — через запятую, например по IP и по имени)

  Создаст рядом два файла:
    Включить-микрофон.reg    — раздать пользователям: двойной клик -> Да -> перезапуск браузера
    Выключить-микрофон.reg   — откат (удаляет политику)
#>

param(
    [string]$Origin = 'http://192.168.0.100:8765',
    [string]$OutDir = $PSScriptRoot
)

# нормализуем список origin'ов
$Origins = @()
foreach ($o in ($Origin -split '[,;]+')) { $t = $o.Trim().TrimEnd('/'); if ($t) { $Origins += $t } }
$bad = @($Origins | Where-Object { $_ -notmatch '^https?://[^/\s]+$' })
if ($Origins.Count -eq 0 -or $bad.Count -gt 0) {
    Write-Host "Origin должен быть вида  http://192.168.0.100:8765  (схема + хост [+ порт], без / и пути)." -ForegroundColor Red
    if ($bad.Count -gt 0) { Write-Host ("Неверно: " + ($bad -join ', ')) -ForegroundColor Red }
    exit 1
}

# браузеры (Chromium-семейство — все читают эту политику)
$browsers = @(
    'SOFTWARE\Policies\Google\Chrome',
    'SOFTWARE\Policies\Microsoft\Edge',
    'SOFTWARE\Policies\YandexBrowser',
    'SOFTWARE\Policies\Chromium',
    'SOFTWARE\Policies\BraveSoftware\Brave'
)

$nl = "`r`n"   # .reg требует CRLF
$joined = ($Origins -join ', ')

# ---- Включить ----
$on = "Windows Registry Editor Version 5.00$nl$nl"
$on += "; GigaChat: разрешить микрофон (голосовой ввод) для адреса  $joined$nl"
$on += "; Двойной клик -> Да -> ПОЛНОСТЬЮ перезапустить браузер. Откат: Выключить-микрофон.reg$nl$nl"
foreach ($b in $browsers) {
    $on += "[HKEY_CURRENT_USER\$b\OverrideSecurityRestrictionsOnInsecureOrigin]$nl"
    $i = 1
    foreach ($o in $Origins) { $on += '"' + $i + '"="' + $o + '"' + $nl; $i++ }
    $on += $nl
}

# ---- Выключить (откат) ----
$off = "Windows Registry Editor Version 5.00$nl$nl"
$off += "; GigaChat: откат — убрать разрешение микрофона для http-адреса.$nl$nl"
foreach ($b in $browsers) {
    $off += "[-HKEY_CURRENT_USER\$b\OverrideSecurityRestrictionsOnInsecureOrigin]$nl$nl"
}

$onPath = Join-Path $OutDir 'Включить-микрофон.reg'
$offPath = Join-Path $OutDir 'Выключить-микрофон.reg'

# .reg с заголовком «Version 5.00» ДОЛЖЕН быть UTF-16 LE с BOM — иначе regedit не примет.
$enc = [System.Text.Encoding]::Unicode
[System.IO.File]::WriteAllText($onPath, $on, $enc)
[System.IO.File]::WriteAllText($offPath, $off, $enc)

Write-Host ""
Write-Host ("Адрес(а): " + $joined) -ForegroundColor Cyan
Write-Host ("Создано:  " + $onPath) -ForegroundColor Green
Write-Host ("Создано:  " + $offPath) -ForegroundColor Green
Write-Host ""
Write-Host "Раздайте 'Включить-микрофон.reg' пользователям:" -ForegroundColor Cyan
Write-Host "  двойной клик -> «Да» -> ПОЛНОСТЬЮ закрыть и открыть браузер." -ForegroundColor Cyan
