<#
  deploy-all-psexec.ps1  —  массовая раскатка enable-mic-http.ps1 на список ПК
  в РАБОЧЕЙ ГРУППЕ (без домена) через PsExec (Sysinternals). Запускать с одной
  «админской» машины. На каждом целевом ПК поставит политику микрофона на ВЕСЬ ПК
  (HKLM, все пользователи).

  ТРЕБОВАНИЯ:
    * PsExec (PsTools, Sysinternals) — положите psexec.exe рядом или укажите -PsExec.
    * На целевых ПК один и тот же ЛОКАЛЬНЫЙ админ-аккаунт с известным паролем.
    * ПК доступны по сети, включён доступ к админ-шаре C$ (по умолчанию включён).
    * Файл со списком ПК: по одной строке (имя или IP). Строки с # игнорируются.

  ИСПОЛЬЗОВАНИЕ:
    1) Создайте computers.txt рядом со скриптом (имена/IP офисных ПК, по строке).
    2) Запустите:
         powershell -ExecutionPolicy Bypass -File deploy-all-psexec.ps1 `
           -Origin "http://192.168.0.100:8765" -AdminUser "Admin"
    3) Введите пароль локального админа (спросит один раз, в открытом виде не хранится).
    4) После раскатки на ПК нужно закрыть/открыть браузер.

  Примечание про безопасность: PsExec передаёт пароль по сети — это нормально только
  для ИЗОЛИРОВАННОЙ офисной LAN. В пароль/лог он не пишется.
#>

param(
    [Parameter(Mandatory = $true)][string]$Origin,
    [Parameter(Mandatory = $true)][string]$AdminUser,
    [string]$ListFile = '.\computers.txt',
    [string]$Script = '.\enable-mic-http.ps1',
    [string]$PsExec = 'psexec.exe'
)

if (-not (Test-Path $ListFile)) { Write-Host "Нет файла со списком ПК: $ListFile  (по строке на ПК: имя или IP)" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Script)) { Write-Host "Нет скрипта: $Script" -ForegroundColor Red; exit 1 }
$psx = Get-Command $PsExec -ErrorAction SilentlyContinue
if (-not $psx) { Write-Host "Не найден psexec.exe. Скачайте PsTools (Sysinternals), положите рядом или укажите -PsExec." -ForegroundColor Red; exit 1 }
if ($Origin -notmatch '^https?://[^/\s]+$') { Write-Host "Origin должен быть вида http://192.168.0.100:8765 (без пути)." -ForegroundColor Red; exit 1 }

$sec = Read-Host "Пароль для $AdminUser на целевых ПК" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
if ([string]::IsNullOrEmpty($pass)) { Write-Host "Пустой пароль — отмена." -ForegroundColor Red; exit 1 }

$computers = @(Get-Content $ListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
Write-Host ("ПК в списке: " + $computers.Count + "   Origin: " + $Origin) -ForegroundColor Cyan

$ok = 0; $fail = 0
foreach ($pc in $computers) {
    Write-Host ""
    Write-Host "=== $pc ===" -ForegroundColor Yellow
    $mapped = $false
    try {
        # 1) аутентифицируемся на админ-шаре и копируем скрипт
        & net use "\\$pc\C$" $pass "/user:$AdminUser" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "не удалось подключить \\$pc\C$ (проверьте доступность, аккаунт, C$)" }
        $mapped = $true
        Copy-Item -Path $Script -Destination "\\$pc\C$\Windows\Temp\enable-mic-http.ps1" -Force -ErrorAction Stop
        Write-Host "  скрипт скопирован" -ForegroundColor DarkGray

        # 2) запускаем его на ПК как админ (HKLM, все пользователи)
        $pxArgs = @("\\$pc", '-u', $AdminUser, '-p', $pass, '-accepteula', '-h', '-nobanner',
            'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', 'C:\Windows\Temp\enable-mic-http.ps1', '-Scope', 'Machine', '-Origin', $Origin)
        & $PsExec @pxArgs
        if ($LASTEXITCODE -eq 0) { Write-Host "  OK  политика поставлена" -ForegroundColor Green; $ok++ }
        else { Write-Host ("  psexec вернул код " + $LASTEXITCODE) -ForegroundColor Red; $fail++ }
    }
    catch {
        Write-Host ("  ОШИБКА: " + $_.Exception.Message) -ForegroundColor Red; $fail++
    }
    finally {
        if ($mapped) { & net use "\\$pc\C$" /delete 2>$null | Out-Null }
    }
}
$pass = $null
Write-Host ""
Write-Host ("Готово. Успешно: $ok,  ошибок: $fail.") -ForegroundColor Cyan
Write-Host "На целевых ПК закройте и откройте браузер заново, чтобы политика применилась."
Write-Host "Проверка на ПК:  chrome://policy  ->  OverrideSecurityRestrictionsOnInsecureOrigin = $Origin"
