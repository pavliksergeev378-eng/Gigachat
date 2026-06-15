# Инструкция: развернуть GigaChat на рабочем ПК (ПО ШАГАМ)

> **Важно:** всю папку `GigaChat-main` можно не тащить на работу.
> Хватит только `ocr-server\` + `wheels\` (общие) + `easyocr_models\`.

---

## Этап 1. Подготовка на ДОМАШНЕМ ПК (с интернетом)

### 1.1 Скачать недостающие wheels

Открой эти две ссылки в браузере — скачаются `.whl` файлы:

| Файл | Ссылка |
|------|--------|
| **scipy-1.14.1** (39 MB) | https://files.pythonhosted.org/packages/a9/09/49269c48a0e5b6cc054ae33ecc81b92b23dcc6a32d57c963dc9a9f75c660/scipy-1.14.1-cp312-cp312-win_amd64.whl |
| **fsspec-2024.9.0** (180 KB) | https://files.pythonhosted.org/packages/df/62/eb2d28749cc08958578e657fb656862c507fc081cec5f510f6ea9e66e641/fsspec-2024.9.0-py3-none-any.whl |

### 1.2 Удалить старые несовместимые версии

В папке `C:\Users\<имя>\Downloads\GigaChat-main\GigaChat-main\wheels\` удали:

- `scipy-1.17.1-cp312-cp312-win_amd64.whl` — уже удалён скриптом, проверь
- `fsspec-2026.4.0-py3-none-any.whl` — уже удалён, проверь

### 1.3 Положить новые файлы

Перемести скачанные `scipy-1.14.1...whl` и `fsspec-2024.9.0...whl`
в папку `GigaChat-main\GigaChat-main\wheels\`.

### 1.4 Скопировать на флешку

Перенеси на флешку **только нужное** (весь проект ~500 MB):

```
ФЛЕШКА:
├── GigaChat-main\              ← можно всю папку (запасной вариант)
│   ├── wheels\                 ← 46 .whl файлов (обязательно)
│   ├── ocr-server\             ← копируем на C:\ (обязательно)
│   │   ├── server.py
│   │   ├── requirements.txt
│   │   ├── start.bat
│   │   ├── install-offline.ps1
│   │   └── easyocr_models\     ← (обязательно)
│   ├── Agents\                 ← HTML-агенты для портала
│   ├── Workflow\               ← JSON для n8n
│   ├── GigaChat-Start.bat
│   ├── Caddyfile
│   └── caddy.exe
```

> **Если на флешке мало места:** можно взять только `ocr-server\` + `wheels\`
> (без Agents, Workflow, Plane, Linux и т.д.) — ~300 MB.

---

## Этап 2. На РАБОЧЕМ ПК

### 2.1 Почистить мусор

Проверь и удали (если есть):

```powershell
# Удалить мусор в корне C:\
Remove-Item "C:\ocr-server.py" -ErrorAction SilentlyContinue
Remove-Item "C:\ocr-server" -Recurse -Force -ErrorAction SilentlyContinue
```

> **Важно:** если это ПЕРВАЯ установка — этих файлов нет, и команды просто
> ничего не сделают (ошибки не будет). Если ПЕРЕУСТАНОВКА — удаляем старую
> версию, чтобы не было конфликтов.

### 2.2 Скопировать файлы с флешки

Скопируй папку `ocr-server` с флешки на диск C:\:

```powershell
# Путь может отличаться — проверь букву диска флешки (D:, E:, F:)
Copy-Item "E:\GigaChat-main\ocr-server" "C:\ocr-server" -Recurse -Force
```

**ИЛИ** вручную перетащи папку `ocr-server` из `GigaChat-main` в `C:\`.

Итог — должна получиться структура:
```
C:\ocr-server\
├── server.py
├── requirements.txt
├── start.bat
├── install-offline.ps1
├── wheels\              ← 46 .whl файлов (скопировать отдельно, см. ниже)
└── easyocr_models\      ← .pth файлы (~150 MB)
```

### 2.3 Скопировать wheels (если их нет внутри ocr-server)

```powershell
# Если wheels нет внутри C:\ocr-server\wheels\ — копируем из общей папки
Copy-Item "E:\GigaChat-main\wheels" "C:\ocr-server\wheels" -Recurse -Force
```

> Если скопировал всю папку `GigaChat-main` на C: — wheels уже внутри ocr-server,
> этот шаг пропускаешь. Установщик сам найдёт wheels где угодно.

### 2.4 Проверить Python

```powershell
python --version
```

Должно быть: `Python 3.12.x`. Если нет — сначала установи Python 3.12.

### 2.5 Разрешить запуск скриптов (один раз)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Нажать `Y` → Enter.

### 2.6 Запустить установку

```powershell
cd C:\ocr-server
.\install-offline.ps1
```

Установщик сам:
1. Найдёт wheels (рядом, уровнем выше или в zip)
2. Найдёт модели EasyOCR
3. Удалит старый venv (если был)
4. Создаст новое виртуальное окружение
5. Установит numpy → torch → все зависимости
6. Скопирует модели в `C:\models\easyocr`

**Жди 2–5 минут.** Должна появиться зелёная надпись **«УСТАНОВКА УСПЕШНА»**.

### 2.7 Запустить сервер

**Через start.bat** (двойной клик в проводнике по `C:\ocr-server\start.bat`)

**ИЛИ** вручную:
```powershell
cd C:\ocr-server
.\venv\Scripts\activate
python server.py
```

### 2.8 Проверить

Открой **новое** окно PowerShell и выполни:

```powershell
curl http://130.100.94.119:8055/status
```

Должен вернуться JSON с `"status":"ok"`.

---

## Если что-то пошло не так

| Ошибка | Что делать |
|--------|-----------|
| `No module named 'unicorn'` | Файл лежит не в той папке. Проверь `C:\ocr-server\server.py`, а не `C:\ocr-server.py` |
| `running scripts is disabled` | Выполни шаг 2.5 |
| `python не найден` | Установи Python 3.12 |
| `не хватает wheels/` | Скопируй папку wheels рядом с install-offline.ps1 |
| `503 EasyOCR недоступен` | Модели не скопировались в `C:\models\easyocr` |
| `Address already in use` | Порт 8055 занят. Поменяй `set OCR_PORT=8056` в start.bat |
| `ОШИБКА УСТАНОВКИ` | Скорее всего wheels несовместимы. Проверь что в папке wheels есть `scipy-1.14.1` (не 1.17), `fsspec-2024.9.0` (не 2026), и у всех файлов в имени `cp312` |
