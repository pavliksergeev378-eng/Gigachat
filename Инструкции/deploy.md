# 📋 Развёртывание GigaChat на рабочем ПК

**Дата:** 15.06.2026  
**Версия:** 1.0

---

## 1. OCR-сервер (если не установлен)

Скопируй папку `ocr-server` с флешки в `C:\ocr-server`.

```powershell
# Удали старую версию (если была)
Remove-Item "C:\ocr-server" -Recurse -Force -ErrorAction SilentlyContinue

# Скопируй с флешки (буква диска может отличаться)
Copy-Item "E:\GigaChat-main\ocr-server" "C:\ocr-server" -Recurse -Force

# Разреши скрипты (один раз)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Запусти установку
cd C:\ocr-server
.\install-offline.ps1
```

Дождись зелёной надписи **«УСТАНОВКА УСПЕШНА»**.

---

## 2. Запуск портала

Запусти `GigaChat-Start.bat` двойным кликом.  
Откроется браузер с URL: http://130.100.94.119:8765/

---

## 3. Запуск OCR-сервера (если нужен)

Двойным кликом по `C:\ocr-server\start.bat`

Или вручную:
```powershell
cd C:\ocr-server
.\venv\Scripts\activate
python server.py
```

Проверить:
```powershell
curl http://130.100.94.119:8055/status
```

---

## 4. Конструктор агентов (Node Editor)

**URL:** http://130.100.94.119:8765/node-editor

### Возможности
- ✅ Drag-and-drop сборка цепочек агентов
- ✅ Соединения выход→вход (последовательные цепочки)
- ✅ Светлая/тёмная тема
- ✅ Сохранение/загрузка схем (localStorage + файл)
- ✅ **Экспорт в n8n** (⚡ Import в n8n)

### Как экспортировать workflow в n8n
1. Собери схему на холсте (соедини ноды последовательно)
2. Нажми **⚡ Import в n8n**
3. Скачается `gigachat-workflow.n8n.json`
4. Открой n8n: http://130.100.92.170:5678
5. **Workflows → Add Workflow → ··· → Import from File**
6. Выбери скачанный файл

> **Важно:** Цепочка в n8n строится по реальным соединениям с холста.  
> Если ноды не соединены — они подключатся параллельно к Code-узлу.

---

## 5. Работа с n8n

**URL:** http://130.100.92.170:5678

### Готовые workflow (папка `Workflow/`)
- `document-loader.json` — загрузка документов
- `text-extractor.json` — извлечение текста из PDF
- `OCR+ПоискФИО.json` — поиск ФИО в сканах
- `organization-appeal.json` — жалобы в организации

Импорт: **Workflows → Add Workflow → ··· → Import from File**

---

## 6. Адреса компонентов

| Компонент | Адрес |
|-----------|-------|
| Платформа (Caddy) | http://130.100.94.119:8765 |
| OCR-сервер | http://130.100.94.119:8055 |
| n8n | http://130.100.92.170:5678 |

---

## ⚠️ Если что-то пошло не так

### OCR не отвечает (503)
- Запущен ли `C:\ocr-server\start.bat`?
- Проверь: `curl http://130.100.94.119:8055/status`
- Если нет — переустанови: `cd C:\ocr-server && .\install-offline.ps1`

### Конструктор не открывается
- Запущен ли `GigaChat-Start.bat`?
- Открывай через http://130.100.94.119:8765/node-editor (не напрямую)

### Порты заняты
- 8055 занят → поменяй в `start.bat`: `set OCR_PORT=8056`
- 5678 занят → поменяй в n8n конфиге
