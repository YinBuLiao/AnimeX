#!/usr/bin/env python3
"""
AnimeX mobile M1 smoke test driven via uiautomator2.

Cold-start the app → enter server URL → test connection → login → land on home
→ logout. Screenshots and UI hierarchy dumps go to ./u2_screenshots/.

Flutter renders to a canvas, so uiautomator2 cannot select widgets by text the
way it would for native Android views. We rely on:
  - app lifecycle commands (adb-level): app_start, app_clear, screen_on
  - IME-level text input via send_keys (works on any focused field)
  - coordinate taps computed from screen size
  - screenshots + hierarchy dumps for visual inspection

Run:
  source ~/development/flutter-env.sh    # only needed if you need flutter on PATH
  export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
  python3 mobile/scripts/u2_smoke.py \
      --server-url http://10.0.2.2:8080 \
      --username admin \
      --password admin
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import uiautomator2 as u2

PKG = "com.animex.animex_mobile"
ACTIVITY = ".MainActivity"

SCREENSHOTS_DIR = Path(__file__).resolve().parent / "u2_screenshots"


def stamped(name: str) -> str:
    ts = datetime.now().strftime("%H%M%S")
    return f"{ts}_{name}"


def snap(d: u2.Device, name: str) -> None:
    SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    base = SCREENSHOTS_DIR / stamped(name)
    png = base.with_suffix(".png")
    d.screenshot(str(png))
    try:
        xml = d.dump_hierarchy(compressed=False)
        base.with_suffix(".xml").write_text(xml)
    except Exception as e:
        print(f"[warn] hierarchy dump failed for {name}: {e}")
    print(f"  saved {png.name}")


def wait_idle(d: u2.Device, seconds: float = 1.5) -> None:
    """Flutter has its own frame scheduler; a small sleep is enough."""
    time.sleep(seconds)


def fraction_tap(d: u2.Device, fx: float, fy: float) -> None:
    """Tap at fraction (fx,fy) of the screen. Coordinates 0..1."""
    w, h = d.window_size()
    x, y = int(w * fx), int(h * fy)
    print(f"  tap ({x},{y})  [fraction {fx:.2f},{fy:.2f}]  size={w}x{h}")
    d.click(x, y)


def type_text(d: u2.Device, text: str) -> None:
    """Type into the focused field via `adb shell input text`.

    Flutter on Android does not implement Android's ExtractedText IPC, which
    breaks u2's AdbKeyboard input. `input text` injects key events directly
    and works reliably with any focused TextField.
    """
    # `input text` does not accept `:` and `/` directly on all Android
    # builds; escape characters that the shell would re-interpret.
    escaped = (
        text.replace("\\", "\\\\")
        .replace(" ", "%s")
        .replace("'", "\\'")
        .replace('"', '\\"')
    )
    d.shell(f"input text '{escaped}'")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--server-url",
        default="http://10.0.2.2:8080",
        help="AnimeX backend URL the emulator can reach. "
        "10.0.2.2 is the emulator's loopback alias for the host machine.",
    )
    parser.add_argument("--username", default="admin")
    parser.add_argument("--password", default="admin")
    parser.add_argument(
        "--device",
        default=None,
        help="adb device serial; default = first online device.",
    )
    parser.add_argument(
        "--keep-state",
        action="store_true",
        help="Skip 'app_clear' so existing login state is preserved.",
    )
    args = parser.parse_args()

    print(f"[1/8] connect to device ({args.device or 'auto'})")
    d = u2.connect(args.device) if args.device else u2.connect()
    print(f"  serial={d.serial}  info={d.info.get('productName', '?')}")

    print(f"[2/8] reset {PKG}")
    if not args.keep_state:
        d.app_stop(PKG)
        d.app_clear(PKG)

    print(f"[3/8] launch {PKG}")
    # Use `am start` directly; u2.app_start sometimes returns before the
    # Flutter Activity is actually rendered.
    d.shell(f"am start -W -n {PKG}/{ACTIVITY}")
    wait_idle(d, 5)
    snap(d, "01_after_launch")

    print(f"[4/8] type server URL ({args.server_url})")
    # ServerSetupPage layout (Flutter): label "服务器地址" then the TextField
    # then a checkbox then the "测试连接" button. On a 1080x2340 screen the
    # field interior is ~y=440-490 (fraction 0.19) and the button center is
    # ~y=662 (fraction 0.28).
    fraction_tap(d, 0.5, 0.19)
    wait_idle(d)
    d.send_keys(args.server_url)
    wait_idle(d)
    snap(d, "02_url_typed")

    print("[5/8] tap 测试连接")
    fraction_tap(d, 0.5, 0.33)
    wait_idle(d, 4)  # health probe + state update
    snap(d, "03_health_probe")

    print("[6/8] tap 下一步：登录 (only present if installed=true)")
    # When installed=true a tonal "下一步：登录" button appears below the result
    # banner — about fraction 0.46. If installed=false this tap is a no-op.
    fraction_tap(d, 0.5, 0.46)
    wait_idle(d, 2)
    snap(d, "04_login_screen")

    print("[7/8] fill credentials")
    # Username field is the first text field on /login; approx (0.5, 0.20)
    fraction_tap(d, 0.5, 0.20)
    wait_idle(d)
    d.send_keys(args.username)
    wait_idle(d, 0.5)
    # Password field is right below; approx (0.5, 0.30)
    fraction_tap(d, 0.5, 0.30)
    wait_idle(d)
    d.send_keys(args.password)
    wait_idle(d, 0.5)
    snap(d, "05_credentials_filled")

    # Hide keyboard, tap 登录 button (~0.5, 0.42)
    d.press("back")
    wait_idle(d, 0.5)
    fraction_tap(d, 0.5, 0.42)
    wait_idle(d, 3)
    snap(d, "06_after_login")

    print("[8/8] tap 退出登录 on home")
    # Logout button is centered-ish below the M1 placeholder text;
    # approx (0.5, 0.62)
    fraction_tap(d, 0.5, 0.62)
    wait_idle(d, 2)
    snap(d, "07_after_logout")

    print(f"\nDONE. Screenshots & hierarchy dumps in {SCREENSHOTS_DIR}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"\nfailure: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
