$workflows = Get-ChildItem "C:\GigaChat\Workflow\*.json"
foreach ($wf in $workflows) {
    Write-Host "--- $($wf.Name)"
    $content = Get-Content $wf.FullName -Raw
    $content | docker exec -i gigachat-n8n sh -c 'cat > /tmp/wf.json && n8n import:workflow --input=/tmp/wf.json 2>&1' | Select-String 'Success|Error'
}
Write-Host "=== Done ==="
