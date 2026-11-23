"""推送 → 等构建 → 拉产物到 _local，全程自动重试。

沿用 OpenGate 项目的安装链路约定：构建产物不进 GitHub 下载页手动取，
而是直接落到仓库本地的 _local/ 目录，交给后续签名工具消费。

GitHub 在这边经常 502 / 超时，所以每一步都带退避重试：
- 推送  最多 5 次
- 轮询  网络错误不算失败，继续等
- 下载  先走 API 资产的 302 直链，失败换 releases/download 直链，都带断点续传

用法：
    python tools/build.py                # 提交并推送 → 等构建 → 下载
    python tools/build.py --skip-push    # 只等构建并下载（CI 已在跑）
    python tools/build.py --commit "说明"  # 指定提交信息
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

OWNER, REPO = "4gnyfgz2p7-ui", "DeepSeek-App"
ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / "_local"
MARKER = LOCAL / ".last_asset"


def _token() -> str:
    if os.environ.get("GITHUB_TOKEN"):
        return os.environ["GITHUB_TOKEN"].strip()
    path = ROOT / ".token"
    return path.read_text(encoding="ascii").strip() if path.exists() else ""


TOKEN = _token()
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Accept": "application/vnd.github+json",
    "User-Agent": "dsclient-build",
}


def api(path: str) -> dict:
    request = urllib.request.Request(f"https://api.github.com{path}", headers=HEADERS)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode() or "{}")


def retry(fn, attempts: int = 5, delay: int = 6, label: str = ""):
    last = None
    for index in range(attempts):
        try:
            return fn()
        except Exception as error:  # noqa: BLE001
            last = error
            print(f"  [{label}] 第 {index + 1} 次失败：{error}")
            time.sleep(delay * (index + 1))
    raise last


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def push(message: str) -> float:
    status = git("status", "--porcelain")
    if status.stdout.strip():
        git("add", "-A")
        commit = git("commit", "-m", message)
        if commit.returncode != 0:
            print(f"  提交失败：{commit.stderr.strip()[:200]}")
    else:
        print("  工作区无改动，直接推送当前提交")

    url = f"https://x-access-token:{TOKEN}@github.com/{OWNER}/{REPO}.git"
    for index in range(5):
        result = git("push", url, "main")
        if result.returncode == 0:
            print("  推送成功")
            return time.time()
        tail = (result.stderr.strip() or result.stdout.strip()).splitlines()[-1:]
        print(f"  推送失败（第 {index + 1} 次）：{tail}")
        time.sleep(8 * (index + 1))
    raise SystemExit("推送重试 5 次仍失败，检查网络或 .token")


def wait_for_build(timeout: int = 1800, since: float | None = None) -> dict:
    """等最新一次运行。since 是推送时间，用来排除推送前已完成的旧运行。"""
    deadline = time.time() + timeout
    seen = None
    while time.time() < deadline:
        try:
            run = api(f"/repos/{OWNER}/{REPO}/actions/runs?per_page=1")["workflow_runs"][0]
        except Exception as error:  # noqa: BLE001
            print(f"  查询失败（{error}），10 秒后重试")
            time.sleep(10)
            continue

        if since is not None:
            created = datetime.fromisoformat(run["created_at"].replace("Z", "+00:00")).timestamp()
            if created < since - 30:
                time.sleep(8)
                continue

        if run["head_sha"][:7] != seen:
            seen = run["head_sha"][:7]
            print(f"  运行 {seen} 状态 {run['status']}")
        if run["status"] == "completed":
            print(f"  结论：{run['conclusion']}")
            return run
        time.sleep(12)
    raise SystemExit("等待构建超时")


def version() -> str:
    for line in (ROOT / "project.yml").read_text(encoding="utf-8").splitlines():
        if "MARKETING_VERSION" in line:
            return line.split('"')[1]
    return "0.0.0"


def asset_of_latest_release() -> dict:
    release = retry(lambda: api(f"/repos/{OWNER}/{REPO}/releases/tags/latest"), label="release")
    return release["assets"][0]


def download(asset: dict, target: Path) -> Path:
    LOCAL.mkdir(exist_ok=True)
    last = MARKER.read_text(encoding="ascii").strip() if MARKER.exists() else ""
    if str(asset["id"]) == last and target.exists() and target.stat().st_size == asset["size"]:
        print("  产物未变化，跳过下载")
        return target

    # 先下到 .part 再整体替换：直接用 -C - 续传到旧文件上时，
    # 若新旧包尺寸恰好相同，curl 会认为已下完、静默留下旧内容。
    part = target.with_name(target.name + ".part")
    if part.exists() and part.stat().st_size > asset["size"]:
        part.unlink()

    api_url = f"https://api.github.com/repos/{OWNER}/{REPO}/releases/assets/{asset['id']}"
    direct = f"https://github.com/{OWNER}/{REPO}/releases/download/latest/{asset['name']}"

    try:
        request = urllib.request.Request(api_url, headers={**HEADERS, "Accept": "application/octet-stream"})
        opener = urllib.request.build_opener(
            type("NoRedirect", (urllib.request.HTTPRedirectHandler,), {"redirect_request": lambda *a, **k: None})
        )
        try:
            opener.open(request, timeout=30)
            location = api_url
        except urllib.error.HTTPError as error:
            location = error.headers.get("Location", api_url)
        if location and location != api_url:
            _curl(location, part, asset["size"])
            part.replace(target)
            MARKER.write_text(str(asset["id"]), encoding="ascii")
            return target
    except Exception as error:  # noqa: BLE001
        print(f"  API 通道失败：{error}")

    print("  改用 releases/download 直链")
    _curl(direct, part, asset["size"])
    part.replace(target)
    MARKER.write_text(str(asset["id"]), encoding="ascii")
    return target


def _curl(url: str, target: Path, size: int) -> None:
    for index in range(4):
        result = subprocess.run(
            ["curl", "-sS", "-L", "--retry", "5", "--retry-all-errors", "--retry-delay", "4",
             "-C", "-", "--max-time", "600", "-o", str(target), url],
            capture_output=True, text=True,
        )
        if result.returncode == 0 and target.exists() and target.stat().st_size == size:
            print(f"  下载完成：{size} 字节")
            return
        print(f"  下载失败（第 {index + 1} 次）：{result.stderr.strip()[-120:]}")
        time.sleep(5 * (index + 1))
    raise SystemExit("下载重试 4 次仍失败")


def describe(ipa: Path) -> str:
    """读出包内的版本号，确认下载到的确实是这一次的产物"""
    try:
        import plistlib
        import zipfile

        with zipfile.ZipFile(ipa) as archive:
            with archive.open("Payload/DSClient.app/Info.plist") as handle:
                info = plistlib.load(handle)
        return f"{info.get('CFBundleShortVersionString')} (build {info.get('CFBundleVersion')})"
    except Exception:  # noqa: BLE001
        return "版本未知"


def main() -> None:
    message = "chore: 自动构建"
    if "--commit" in sys.argv:
        message = sys.argv[sys.argv.index("--commit") + 1]

    started = None
    if "--skip-push" not in sys.argv:
        print("1) 推送")
        started = push(message)
        time.sleep(15)
    else:
        print("1) 跳过推送")

    print("2) 等待构建")
    run = wait_for_build(since=started)
    if run["conclusion"] != "success":
        raise SystemExit("构建失败，运行 python tools/logs.py 查看错误")

    print("3) 取产物")
    asset = asset_of_latest_release()
    target = LOCAL / f"DSClient-{version()}.ipa"
    download(asset, target)

    info = describe(target)
    expected = run.get("run_number")
    if expected and f"build {expected}" not in info:
        raise SystemExit(
            f"产物版本异常：本地为 {info}，但本次运行是 #{expected}。"
            f"删除 {target} 与 {MARKER} 后重试"
        )

    print(f"4) 就绪：{target}（{target.stat().st_size} 字节，{info}）")


if __name__ == "__main__":
    main()
