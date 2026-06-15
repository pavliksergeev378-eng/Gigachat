<#
  enable-mic-http.ps1  —  включает доступ к МИКРОФОНУ (голосовой ввод в Plane-агенте)
  для офисного http-адреса на ОДНОМ ПК. Полностью ОФЛАЙН: без интернета, без сертификатов.

  Что делает: ставит политику браузера OverrideSecurityRestrictionsOnInsecureOrigin.
  Браузер начинает считать указанный http-origin «защищённым контекстом» (secure
  context), и getUserMedia (микрофон) на http://<ip> разблокируется.

  ПО УМОЛЧАНИЮ пишет в HKLM — политика на ВЕСЬ ПК, для ВСЕХ пользователей. Поэтому
  нужны права администратора, скрипт сам поднимет UAC. После этого ЛЮБОЙ обычный
  пользователь, залогинившись на этот ПК, пользуется микрофоном без каких-либо
  действий.

  --- Как запускать (один раз на каждом ПК в рабочей группе) ---
  1) Впишите адрес вашего сервера в $DefaultOrigin ниже (РОВНО как в адресной строке
     браузера: схема + хост + порт, без пути). Можно несколько через запятую.
  2) Правый клик по файлу -> «Выполнить с помощью PowerShell»
     (или из консоли:  powershell -ExecutionPolicy Bypass -File enable-mic-http.ps1 ).
  3) Подтвердите UAC (права админа нужны один раз).
  4) ПОЛНОСТЬЮ закройте браузер (все окна) и откройте заново.

  --- Параметры ---
  -Origin  "http://192.168.0.100:8765"   адрес(а) РОВНО как в адресной строке; несколько — через запятую
  -Scope   Machine | User                Machine (по умолч.) = все юзеры ПК (HKLM, нужен админ)
                                         User = только текущий пользователь (HKCU, без админа)
#>

param(
    [string]$Origin = '',
    [ValidateSet('Machine', 'User')][string]$Scope = 'Machine'
)

# ===================== ВПИШИТЕ АДРЕС ВАШЕГО СЕРВЕРА =====================
# Как в адресной строке браузера. Несколько адресов — через запятую
# (например, доступ по IP и по короткому имени):
#   'http://192.168.0.100:8765'
#   'http://192.168.0.100:8765, http://giga:8765'
$DefaultOrigin = 'http://192.168.0.100:8765'
# =======================================================================

if ([string]::IsNullOrWhiteSpace($Origin)) { $Origin = $DefaultOrigin }

# разбить на список и нормализовать (убрать пробелы и хвостовой / )
$Origins = @()
foreach ($o in ($Origin -split '[,;]+')) {
    $t = $o.Trim().TrimEnd('/')
    if ($t) { $Origins += $t }
}
$bad = @($Origins | Where-Object { $_ -notmatch '^https?://[^/\s]+$' })
if ($Origins.Count -eq 0 -or $bad.Count -gt 0) {
    Write-Host "Origin должен быть вида  http://192.168.0.100:8765  (схема + хост [+ порт], без / и пути)." -ForegroundColor Red
    if ($bad.Count -gt 0) { Write-Host ("Неверно: " + ($bad -join ', ')) -ForegroundColor Red }
    Write-Host "Впишите адрес в `$DefaultOrigin вверху файла или передайте -Origin." -ForegroundColor Red
    exit 1
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Machine-режим без админских прав -> перезапуск через UAC (окно остаётся открытым)
if ($Scope -eq 'Machine' -and -not (Test-Admin)) {
    Write-Host "Политика ставится на ВЕСЬ ПК (все пользователи) — нужны права администратора. Поднимаю UAC..." -ForegroundColor Yellow
    $joined = ($Origins -join ',')
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', ('"' + $PSCommandPath + '"'),
            '-Scope', 'Machine', '-Origin', ('"' + $joined + '"')
        )
    }
    catch {
        Write-Host ("Не удалось поднять UAC (" + $_.Exception.Message + ").") -ForegroundColor Red
        Write-Host "Запустите файл правым кликом -> «Запуск от имени администратора»," -ForegroundColor Red
        Write-Host "ИЛИ только для текущего пользователя:  -Scope User" -ForegroundColor Red
    }
    exit
}

$root = 'HKLM:'
if ($Scope -eq 'User') { $root = 'HKCU:' }

$browsers = @(
    @{ Name = 'Google Chrome'; Path = "$root\SOFTWARE\Policies\Google\Chrome" },
    @{ Name = 'Microsoft Edge'; Path = "$root\SOFTWARE\Policies\Microsoft\Edge" },
    @{ Name = 'Yandex Browser'; Path = "$root\SOFTWARE\Policies\YandexBrowser" },
    @{ Name = 'Chromium'; Path = "$root\SOFTWARE\Policies\Chromium" },
    @{ Name = 'Brave'; Path = "$root\SOFTWARE\Policies\BraveSoftware\Brave" }
)

Write-Host ""
Write-Host ("Адрес(а) : " + ($Origins -join '   ')) -ForegroundColor Cyan
Write-Host ("Область  : $Scope  ($root  — " + $(if ($Scope -eq 'Machine') { 'все пользователи ПК' } else { 'только текущий пользователь' }) + ")") -ForegroundColor Cyan
Write-Host ""

foreach ($b in $browsers) {
    $key = Join-Path $b.Path 'OverrideSecurityRestrictionsOnInsecureOrigin'
    try {
        # идемпотентность: снести старые значения и записать заново 1..N
        if (Test-Path $key) { Remove-Item -Path $key -Recurse -Force -ErrorAction Stop }
        New-Item -Path $key -Force | Out-Null
        $i = 1
        foreach ($o in $Origins) {
            Set-ItemProperty -Path $key -Name "$i" -Value $o -Type String
            $i++
        }
        Write-Host ("  OK   " + $b.Name.PadRight(16) + " <- " + ($Origins -join ', ')) -ForegroundColor Green
    }
    catch {
        Write-Host ("  --   " + $b.Name.PadRight(16) + " пропущен (" + $_.Exception.Message + ")") -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Готово. ПОЛНОСТЬЮ закройте браузер (все окна) и откройте заново." -ForegroundColor Cyan
Write-Host "Проверка: откройте в браузере  chrome://policy  — там должна быть строка:" -ForegroundColor Cyan
Write-Host ("    OverrideSecurityRestrictionsOnInsecureOrigin = " + ($Origins -join ',')) -ForegroundColor White
Write-Host "После этого в Plane-агенте кнопка микрофона начнёт спрашивать доступ и работать."
Write-Host ""
