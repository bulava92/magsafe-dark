#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 <<'PY'
from pathlib import Path

scheduler = Path('Sources/MagSafeScheduler/main.swift')
text = scheduler.read_text()
text = text.replace(
    'if status.deferredByTemporaryState && !force { return 0 }',
    'if status.deferredByTemporaryState { return 0 }'
)
text = text.replace(
    'if let boundary = status.nextBoundary {\n            delay = max(1, min(boundary.timeIntervalSinceNow + 0.5, 3600))',
    'if status.deferredByTemporaryState {\n            delay = 2\n        } else if let boundary = status.nextBoundary {\n            delay = max(1, min(boundary.timeIntervalSinceNow + 0.5, 3600))'
)
scheduler.write_text(text)

editor = Path('Sources/ScheduleEditor/main.swift')
text = editor.read_text()
if 'import Darwin' not in text:
    text = text.replace('import AppKit\n', 'import AppKit\nimport Darwin\n', 1)
text = text.replace('runScheduler(["apply", "--force"])', 'runScheduler(["apply"])')
text = text.replace(
    'saveEditorIntoSelectedRule(showErrors: true)\n        schedule.enabled = enabled.state == .on',
    'saveEditorIntoSelectedRule(showErrors: true)\n        let wasEnabled = schedule.enabled\n        schedule.enabled = enabled.state == .on'
)
text = text.replace(
    'try saveSchedule(schedule)\n            runScheduler(["apply"])',
    'try saveSchedule(schedule)\n            if !wasEnabled && schedule.enabled {\n                runScheduler(["clear-manual"])\n            } else {\n                runScheduler(["apply"])\n            }'
)
editor.write_text(text)
print('Prepared adaptive schedule editor and immediate schedule activation')
PY
