# =============================================================================
# Устанавливает OCR-сервер на офисном ПК БЕЗ ИНТЕРНЕТА из локальных wheel-файлов.
# Требования: Python 3.10-3.12 в PATH.
# =============================================================================

$ErrorActionPreference = "Stop"

# ---- Путь к папке со скриптом ----
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

Write-Host "==> Проверка Python..."
$pythonVersion = python --version 2>&1
Write-Host "    $pythonVersion"

# ---- ИЩЕМ WHEELS ----
$wheelsPath = $null

if (Test-Path "wheels") {
    $wc = (Get-ChildItem "wheels" -Filter "*.whl" -File).Count
    if ($wc -gt 0) {
        $wheelsPath = Join-Path $scriptDir "wheels"
        Write-Host "    wheels/: найден ($wc .whl)"
    }
}

if (-not $wheelsPath) {
    $parentWheels = Join-Path $scriptDir "..\wheels"
    if (Test-Path $parentWheels) {
        $wc = (Get-ChildItem $parentWheels -Filter "*.whl" -File).Count
        if ($wc -gt 0) {
            $wheelsPath = $parentWheels
            Write-Host "    ../wheels/: найден ($wc .whl, в корне проекта)"
        }
    }
}

if (-not $wheelsPath) {
    $wheelsZipCandidates = @("ocr-wheels.zip", "wheels.zip", "..\ocr-wheels.zip", "..\wheels.zip")
    foreach ($zip in $wheelsZipCandidates) {
        $zipPath = Join-Path $scriptDir $zip
        if (Test-Path $zipPath) {
            Write-Host ""
            Write-Host "==> Найден $zip - распаковываю в wheels/..."
            Expand-Archive -Path $zipPath -DestinationPath $scriptDir -Force
            if (Test-Path "wheels") {
                $wheelsPath = Join-Path $scriptDir "wheels"
                break
            }
            $looseWhls = Get-ChildItem -Path $scriptDir -Filter "*.whl" -File
            if ($looseWhls.Count -gt 0) {
                New-Item -ItemType Directory -Force -Path "wheels" | Out-Null
                foreach ($f in $looseWhls) {
                    Move-Item -Path $f.FullName -Destination "wheels\" -Force
                }
                $wheelsPath = Join-Path $scriptDir "wheels"
                break
            }
        }
    }
}

# ---- ИЩЕМ МОДЕЛИ EASYOCR ----
$modelsPath = $null

if (Test-Path "easyocr_models") {
    $modelsPath = Join-Path $scriptDir "easyocr_models"
    Write-Host "    easyocr_models/: уже есть"
}

if (-not $modelsPath) {
    $parentModels = Join-Path $scriptDir "..\easyocr_models"
    if (Test-Path $parentModels) {
        $modelsPath = $parentModels
        Write-Host "    ../easyocr_models/: найден (в корне проекта)"
    }
}

if (-not $modelsPath) {
    $modelsZipCandidates = @("ocr-easyocr-models.zip", "easyocr_models.zip", "..\ocr-easyocr-models.zip", "..\easyocr_models.zip")
    foreach ($zip in $modelsZipCandidates) {
        $zipPath = Join-Path $scriptDir $zip
        if (Test-Path $zipPath) {
            Write-Host ""
            Write-Host "==> Найден $zip - распаковываю в easyocr_models/..."
            Expand-Archive -Path $zipPath -DestinationPath $scriptDir -Force
            if (Test-Path "easyocr_models") {
                $modelsPath = Join-Path $scriptDir "easyocr_models"
                break
            }
            $loosePths = Get-ChildItem -Path $scriptDir -Filter "*.pth" -File
            if ($loosePths.Count -gt 0) {
                New-Item -ItemType Directory -Force -Path "easyocr_models" | Out-Null
                foreach ($f in $loosePths) {
                    Move-Item -Path $f.FullName -Destination "easyocr_models\" -Force
                }
                $modelsPath = Join-Path $scriptDir "easyocr_models"
                break
            }
        }
    }
}

# ---- ПРОВЕРКА БАНДЛА ----
Write-Host ""
Write-Host "==> Проверка файлов бандла..."
$missing = @()
if (-not (Test-Path "requirements.txt"))   { $missing += "requirements.txt" }
if (-not (Test-Path "server.py"))           { $missing += "server.py" }
if (-not $wheelsPath)                       { $missing += "wheels/" }
if (-not $modelsPath)                       { $missing += "easyocr_models/" }

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "ОШИБКА: в текущей папке не хватает файлов:" -ForegroundColor Red
    foreach ($m in $missing) { Write-Host "  - $m" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Скачай wheels и модели из GitHub Releases:" -ForegroundColor Yellow
    Write-Host "  https://github.com/Jorden-maker/GigaChat/releases/latest" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Положи ocr-wheels.zip и ocr-easyocr-models.zip в папку ocr-server/"
    exit 1
}

$wheelCount = (Get-ChildItem -Path $wheelsPath -Filter "*.whl").Count
Write-Host "    requirements.txt: OK"
Write-Host "    server.py:        OK"
Write-Host "    wheels:           $wheelCount .whl файлов ($wheelsPath)"
Write-Host "    easyocr_models:   OK ($modelsPath)"

if ($wheelCount -lt 10) {
    Write-Host ""
    Write-Host "ВНИМАНИЕ: в wheels всего $wheelCount пакетов - обычно их 30+." -ForegroundColor Yellow
}

# ---- УДАЛЕНИЕ СТАРОГО VENV ----
if (Test-Path "venv") {
    Write-Host ""
    Write-Host "Виртуальное окружение уже существует. Удаляю и создаю заново..."
    Remove-Item -Recurse -Force "venv"
}

# ---- СОЗДАНИЕ VENV ----
Write-Host ""
Write-Host "==> Создание виртуального окружения..."
python -m venv venv

Write-Host ""
Write-Host "==> Активация..."
& ".\venv\Scripts\Activate.ps1"

Write-Host ""
Write-Host "==> Установка зависимостей из локальных wheels (без интернета)..."
python -m pip install --no-index --find-links=$wheelsPath --upgrade pip
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ОШИБКА: не удалось обновить pip. Возможно, нет pip в бандле или битый wheel." -ForegroundColor Red
    Write-Host "Попробуй: python -m ensurepip --upgrade" -ForegroundColor Yellow
    exit 1
}

# Шаг 1: numpy
Write-Host "  -> Шаг 1/3: numpy..."
python -m pip install --no-index --find-links=$wheelsPath numpy==1.26.4
if ($LASTEXITCODE -ne 0) {
    Write-Host "ОШИБКА: numpy не установился." -ForegroundColor Red
    exit 1
}

# Шаг 2: torch + torchvision
Write-Host "  -> Шаг 2/3: torch + torchvision..."
python -m pip install --no-index --find-links=$wheelsPath torch==2.12.0 torchvision==0.27.0
if ($LASTEXITCODE -ne 0) {
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: torch не установился. EasyOCR будет недоступен (только PyMuPDF для PDF с текстовым слоем)." -ForegroundColor Yellow
}

# Шаг 3: остальные зависимости
Write-Host "  -> Шаг 3/3: остальные зависимости..."
python -m pip install --no-index --find-links=$wheelsPath -r requirements.txt

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ОШИБКА установки. Возможные причины:" -ForegroundColor Red
    Write-Host "  - в wheels не хватает пакета" -ForegroundColor Red
    Write-Host "  - версия Python не совпадает с той, где собирался бандл" -ForegroundColor Red
    Write-Host "  - архитектура отличается (например, ARM vs x86)" -ForegroundColor Red
    Write-Host ""
    Write-Host "ЧТО ДЕЛАТЬ: проверь список wheels ниже. На рабочем ПК Python 3.12 -" -ForegroundColor Yellow
    Write-Host "нужны файлы с *cp312* в имени. Если есть *cp311* или *cp313* - не подойдут." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Скачай свежий бандл с GitHub: https://github.com/Jorden-maker/GigaChat/releases/latest" -ForegroundColor Cyan
    exit 1
}

# ---- КОПИРОВАНИЕ МОДЕЛЕЙ ----
$targetModelDir = "C:\models\easyocr"
Write-Host ""
Write-Host "==> Копирование моделей EasyOCR в $targetModelDir..."
if (Test-Path $targetModelDir) {
    $existingFiles = (Get-ChildItem $targetModelDir -Recurse -File).Count
    Write-Host "    Папка уже существует ($existingFiles файлов) - пропускаю."
    Write-Host "    Если нужно переустановить - удали $targetModelDir и запусти заново."
} else {
    New-Item -ItemType Directory -Force -Path $targetModelDir | Out-Null
    Copy-Item -Path "$modelsPath\*" -Destination $targetModelDir -Recurse -Force
    $copiedFiles = (Get-ChildItem $targetModelDir -Recurse -File).Count
    Write-Host "    Скопировано $copiedFiles файлов."
}

# ---- ФИНАЛЬНОЕ СООБЩЕНИЕ ----
Write-Host ""
Write-Host "=============================================================" -ForegroundColor Green
Write-Host " УСТАНОВКА УСПЕШНА" -ForegroundColor Green
Write-Host "=============================================================" -ForegroundColor Green
Write-Host ""
Write-Host " ЧТО ДАЛЬШЕ:"
Write-Host ""
Write-Host " 1. Запусти сервер двойным кликом по:"
Write-Host "      start.bat" -ForegroundColor Cyan
Write-Host ""
Write-Host " 2. В новом окне PowerShell проверь, что отвечает:"
Write-Host "      curl http://130.100.94.119:8055/status" -ForegroundColor Cyan
Write-Host ""
Write-Host " 3. Тест извлечения текста из PDF:"
Write-Host '      curl -X POST -F "file=@some.pdf" http://130.100.94.119:8055/extract' -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Green