"""拉取最近一次构建的日志，打印失败步骤与错误行。

用法：
    python tools/logs.py           # 最近一次运行
    python tools/logs.py <run_id>  # 指定运行
"""

from __future__ import annotations

import io
import json
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

OWNER, REPO = "4gnyfgz2p7-ui", "DeepSeek-App"
ROOT = Path(__file__).resolve().parents[1]


def token() -> str:
    if os.environ.get("GITHUB_TOKEN"):
        return os.environ["GITHUB_TOKEN"]
    path = ROOT / ".token"
    return path.read_text(encoding="ascii").strip() if path.exists() else ""


def api(path: str) -> dict:
    request = urllib.request.Request(
        f"https://api.github.com{path}",
        headers={"Authorization": f"Bearer {token()}", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode() or "{}")


def main() -> None:
    run_id = sys.argv[1] if len(sys.argv) > 1 else api(f"/repos/{OWNER}/{REPO}/actions/runs?per_page=1")["workflow_runs"][0]["id"]
    print(f"运行 {run_id}")

    jobs = api(f"/repos/{OWNER}/{REPO}/actions/runs/{run_id}/jobs")["jobs"]
    for job in jobs:
        print(f"job {job['name']} → {job['conclusion']}")
        for step in job["steps"]:
            mark = "✗" if step["conclusion"] == "failure" else " "
            print(f" {mark} {step['number']:>2} {step['name']} ({step['conclusion']})")

    request = urllib.request.Request(
        f"https://api.github.com/repos/{OWNER}/{REPO}/actions/runs/{run_id}/logs",
        headers={"Authorization": f"Bearer {token()}", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = response.read()

    archive = zipfile.ZipFile(io.BytesIO(payload))
    print("\n=== 错误与告警 ===")
    hits = 0
    for name in archive.namelist():
        if not name.endswith(".txt"):
            continue
        text = archive.read(name).decode("utf-8", "replace")
        for line in text.splitlines():
            stripped = line.split("Z ", 1)[-1]
            if "error:" in stripped or "error " in stripped.lower() or "fatal error" in stripped:
                print(f"[{name}] {stripped[:300]}")
                hits += 1
                if hits >= 60:
                    break
        if hits >= 60:
            break
    if hits == 0:
        print("未在日志里匹配到 error 行；构建可能只是被取消或超时")


if __name__ == "__main__":
    main()
