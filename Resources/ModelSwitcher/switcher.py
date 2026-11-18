#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys

import tomlkit


PROVIDER = "model_switcher_deepseek"
KEYCHAIN_SERVICE = "local.neil.codexbattery.deepseek"
KEYCHAIN_ACCOUNT = str(os.getuid())
SECURITY = "/usr/bin/security"
FIND_KEY = ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT]
MODELS = {"flash": "deepseek-flash", "pro": "deepseek-v4-pro"}
OVERRIDES = {
    "model_provider": PROVIDER,
    "model_reasoning_effort": "high",
    "model_reasoning_summary": "none",
    "web_search": "disabled",
}
MANAGED_KEYS = (*OVERRIDES, "model", "model_catalog_json")
BUNDLED_CODEX = Path(
    "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/"
    "Contents/MacOS/codex"
)


def atomic_write(path, content):
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def model_catalog():
    models = []
    for priority, (variant, slug) in enumerate(MODELS.items(), start=1):
        flash = variant == "flash"
        models.append({
            "slug": slug,
            "display_name": "DeepSeek Flash" if flash else "DeepSeek V4 Pro",
            "description": "DeepSeek V4.1 Flash" if flash else "DeepSeek V4 Pro",
            "context_window": 1048576,
            "max_context_window": 1048576,
            "effective_context_window_percent": 95,
            "max_output_tokens": 393216,
            "input_modalities": ["text", "image"] if flash else ["text"],
            "supports_image_detail_original": flash,
            "prefer_websockets": False,
            "supported_in_api": True,
            "visibility": "list",
            "priority": priority,
            "shell_type": "shell_command",
            "apply_patch_tool_type": "freeform",
            "supports_parallel_tool_calls": True,
            "truncation_policy": {"mode": "tokens", "limit": 10000},
            "supports_search_tool": False,
            "support_verbosity": True,
            "default_verbosity": "low",
            "web_search_tool_type": "text",
            "experimental_supported_tools": [],
            "include_skills_usage_instructions": False,
            "use_responses_lite": False,
            "comp_hash": "3000",
            "default_reasoning_summary": "none",
            "default_reasoning_level": "high",
            "supported_reasoning_levels": [
                {"effort": effort, "description": label}
                for effort, label in [("low", "Low"), ("high", "High"), ("max", "Max")]
            ],
            "base_instructions": (
                "You are Codex, a coding assistant. Follow the user's instructions, "
                "inspect the workspace before editing, preserve unrelated changes, "
                "and verify your work using the available tools."
            ),
        })
    return json.dumps({"models": models}, indent=2).encode()


def check_codex(executable):
    codex = executable or shutil.which("codex") or (BUNDLED_CODEX if BUNDLED_CODEX.is_file() else None)
    if not codex:
        raise ValueError("未找到 Codex CLI，请先安装 ChatGPT 桌面端或 Codex CLI。")
    version = subprocess.check_output([codex, "--version"], text=True)
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", version)
    if not match or tuple(map(int, match.groups())) < (0, 164, 0):
        raise ValueError("请先将 Codex 更新至 0.164.0 或更高版本。")


def save_key():
    key = sys.stdin.readline().strip()
    if not re.fullmatch(r"sk-[A-Za-z0-9_-]+", key):
        raise ValueError("API Key 格式无效，应以 sk- 开头。")
    command = (
        f"add-generic-password -U -a {KEYCHAIN_ACCOUNT} -s {KEYCHAIN_SERVICE} "
        f"-T {SECURITY} -w {key}\n"
    )
    subprocess.run([SECURITY, "-i"], input=command.encode(), capture_output=True, check=True)
    saved = subprocess.run([SECURITY, *FIND_KEY, "-w"], capture_output=True)
    if saved.returncode or saved.stdout.strip() != key.encode():
        raise ValueError("无法把 DeepSeek API Key 保存到 macOS 钥匙串。")


def use_model(action, config, state, original, document, executable):
    providers = document.get("model_providers", {})
    active = document.get("model_provider") == PROVIDER
    baseline = state / "original.toml"
    catalog_path = state / "models.json"

    if action == "key":
        save_key()
        print("已保存 DeepSeek API Key。")
        return

    if active and not baseline.is_file():
        raise ValueError(f"找不到原配置备份 {baseline}，无法安全切换。")

    if action == "chatgpt":
        if not active:
            print("目前使用原有 Codex 配置。")
            return
        previous = tomlkit.parse(baseline.read_text(encoding="utf-8"))
        for name in MANAGED_KEYS:
            if name in document:
                del document[name]
            if name in previous:
                document[name] = previous.item(name)
        del providers[PROVIDER]
        if not providers and "model_providers" not in previous:
            del document["model_providers"]
    else:
        check_codex(executable)
        if not active:
            if PROVIDER in providers:
                raise ValueError(f"配置中已存在同名提供方 {PROVIDER}。")
            if document.get("model_provider", "openai") != "openai":
                raise ValueError("当前已启用其他自定义提供方，请先恢复 OpenAI 配置。")
        if subprocess.run([SECURITY, *FIND_KEY], capture_output=True).returncode:
            raise SystemExit(3)
        atomic_write(catalog_path, model_catalog())
        if not active:
            atomic_write(baseline, original)
        for name, value in {
            **OVERRIDES, "model": MODELS[action], "model_catalog_json": str(catalog_path),
        }.items():
            document[name] = value
        if "model_providers" not in document:
            document["model_providers"] = tomlkit.table()
        document["model_providers"][PROVIDER] = {
            "name": "DeepSeek",
            "base_url": "https://api.deepseek.com/",
            "wire_api": "responses",
            "auth": {"command": SECURITY, "args": [*FIND_KEY, "-w"]},
        }

    updated = tomlkit.dumps(document)
    parsed = tomlkit.parse(updated)
    if parsed.unwrap() != document.unwrap():
        raise ValueError("生成的 Codex 配置校验失败。")
    if config.exists() and config.read_bytes() != original:
        raise ValueError("Codex 配置在切换期间发生了变化，请重试。")
    atomic_write(config, updated.encode())
    print(f"已切换至 {document.get('model', 'ChatGPT 默认模型')}。")
    print("请退出并重新打开 ChatGPT 桌面端，或启动新的 Codex CLI 会话。")


def main():
    parser = argparse.ArgumentParser(description="切换 Codex 使用的模型")
    parser.add_argument("action", choices=["status", "chatgpt", *MODELS, "key"])
    parser.add_argument("--codex")
    args = parser.parse_args()
    home = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser().resolve()
    config = (home / "config.toml").resolve()
    state = home / "model-switcher"
    if args.action == "status":
        document = tomlkit.parse(config.read_text(encoding="utf-8")) if config.exists() else {}
        print(json.dumps({
            "model": document.get("model", ""),
            "provider": document.get("model_provider", "openai"),
        }))
        return
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / "switch.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        original = config.read_bytes() if config.exists() else b""
        use_model(args.action, config, state, original, tomlkit.parse(original.decode()), args.codex)


if __name__ == "__main__":
    try:
        main()
    except subprocess.SubprocessError:
        raise SystemExit("无法执行 Codex 或 macOS 钥匙串命令。") from None
    except (ValueError, OSError, EOFError) as error:
        raise SystemExit(f"操作失败：{error}") from None
    except KeyboardInterrupt:
        raise SystemExit("\n已取消。") from None
