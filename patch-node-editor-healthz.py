# patch-node-editor-healthz.py
# Автоматически правит node-editor.html:
# заменяет прямой health-check n8n на прокси-версию.
#
# Запуск из корня проекта:
#   python patch-node-editor-healthz.py
#
# Ищет node-editor.html в корне и в Agents/.
# Перед правкой создаёт backup (.bak-healthz).
#
# Паттерны покрывают старые и текущие версии:
#   - n8nCtrl / ctrl (разные имена AbortController)
#   - одинарные и двойные кавычки

import re
from pathlib import Path

candidates = [Path("node-editor.html"), Path("Agents/node-editor.html")]
p = None
for c in candidates:
    if c.exists():
        p = c
        break

if p is None:
    raise SystemExit("node-editor.html не найден ни в корне проекта, ни в Agents/.")

txt = p.read_text(encoding="utf-8")

# Проверяем, не пропатчен ли уже
if "N8N_PROXY_BASE" in txt and "/n8n-healthz" in txt:
    print("node-editor.html уже использует прокси-версию healthz. Патч не нужен.")
    raise SystemExit(0)

# Ищем прямой health-check: fetch(n8nBase + '/healthz', ...)
# Варианты: n8nCtrl / ctrl, ' / "
pattern = re.compile(
    r"""fetch\(\s*n8nBase\s*\+\s*(['"])/healthz\1\s*,\s*\{[^}]*signal:\s*(n8nCtrl|ctrl)\.signal[^}]*\}\)"""
)

match = pattern.search(txt)
if not match:
    raise SystemExit(
        "Не нашёл прямой fetch(n8nBase + '/healthz'...) в node-editor.html.\n"
        "Файл может быть уже пропатчен или иметь нестандартную структуру."
    )

quote = match.group(1)
ctrl_var = match.group(2)

replacement = (
    "fetch(((window.GIGACHAT_CONFIG || {}).N8N_PROXY_BASE || "
    + quote + "http://localhost:8777" + quote
    + ").replace(/\\/$/, '') + '/n8n-healthz', { method: 'HEAD', signal: "
    + ctrl_var + ".signal })"
)

# Используем оригинальный кусок как old — уникальный матч для замены
old_str = match.group(0)
txt2 = txt.replace(old_str, replacement, 1)

bak = Path(str(p) + ".bak-healthz")
if not bak.exists():
    bak.write_text(txt, encoding="utf-8")

p.write_text(txt2, encoding="utf-8")
print("Готово:", str(p), "исправлен.")
print("Backup:", str(bak))
