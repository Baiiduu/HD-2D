"""Run the shipped Meowa CLI after its request has been registered on the log Page."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.stdout.reconfigure(encoding="utf-8")
request_path = Path(sys.argv[1]).resolve()
request = json.loads(request_path.read_text(encoding="utf-8"))
folder = request_path.parent
prefix = request_path.name.removesuffix('-request.json')
result_name = prefix + '-result.json' if request_path.name.endswith('-request.json') else 'response.json'
output_name = prefix + '-output.txt' if request_path.name.endswith('-request.json') else 'output.txt'

def now():
    return datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")

def redact(text):
    text = re.sub(r"ma_live_[A-Za-z0-9_-]+", "[REDACTED_API_KEY]", text)
    return re.sub(r"(?i)([?&](?:token|signature|sig|key|x-amz-[^=\s]+)=)[^&\s\"']+", r"\1[REDACTED]", text)

state = {"status": "running", "startedAt": now(), "model": "未返回", "seed": "未返回", "cost": "未返回"}
(folder / result_name).write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"}
process = subprocess.Popen([sys.executable, request["runner"], *request["arguments"]],
                           cwd=request["workingDirectory"], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
lines = []
for line in process.stdout:
    clean = redact(line)
    lines.append(clean)
    print(clean, end="", flush=True)
    (folder / output_name).write_text("".join(lines), encoding="utf-8")
state.update(status="success" if process.wait() == 0 else "failed", endedAt=now(),
             exitCode=process.returncode, output="".join(lines))
try:
    output = state["output"].strip()
    start = output.rfind("\n{\n")
    returned = json.loads(output[start + 1:] if start >= 0 else output)
    state["returnedData"] = returned
    data = returned.get("result", returned)
    if "credit_cost" in data:
        state["cost"] = data["credit_cost"]
    if "seed" in data:
        state["seed"] = data["seed"]
    if "generation_model" in data:
        state["model"] = data["generation_model"]
except (ValueError, AttributeError):
    pass
(folder / result_name).write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"\nCall record: {folder}")
sys.exit(process.returncode)
