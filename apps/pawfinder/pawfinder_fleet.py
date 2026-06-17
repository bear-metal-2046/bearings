#!/usr/bin/env python3
"""
pawfinder_fleet.py

Bulk ADB operations for Pawfinder scouting tablets.

Watches for newly-connected Android devices and applies the selected
operations — build/install, Hive data export, or data reset — to each
one automatically as it's plugged in.

Usage:
    python pawfinder_fleet.py          (requires adb + flutter in PATH)

Supported Python: 3.10+
"""

from __future__ import annotations

import base64
import binascii
import json
import re
import shutil
import struct
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable

# ── Project constants ──────────────────────────────────────────────────────────

SCRIPT_DIR  = Path(__file__).parent.resolve()
APK_PATH    = SCRIPT_DIR / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
PACKAGE_ID  = "org.tahomarobotics.pawfinder"
# Flutter's getApplicationDocumentsDirectory() on Android
APP_DATA    = f"/data/user/0/{PACKAGE_ID}/app_flutter"
POLL_SECS   = 2

# ── Operation registry ────────────────────────────────────────────────────────

@dataclass
class Operation:
    key:         str
    label:       str
    description: str
    fn:          Callable[[str], None]
    # Optional hook called once at "go" time (before watching starts).
    # Return True to include the op, False to drop it from this run.
    configure:   Callable[[], bool] | None = None

_REGISTRY: list[Operation] = []

def operation(
    key: str,
    label: str,
    description: str = "",
    configure: Callable[[], bool] | None = None,
) -> Callable:
    """
    Decorator that registers a device operation.

    To add a new operation, write a function that takes a single ``serial``
    argument (the ADB device serial) and decorate it:

        @operation("my_op", "My Operation", "What it does")
        def op_my_op(serial: str) -> None:
            ...

    For operations that need one-time configuration before the watcher starts
    (e.g. prompting for a provisioning payload), supply a ``configure`` callable.
    It is called once when the user hits "go".  Return True to keep the op in
    this run, False to drop it.
    """
    def decorator(fn: Callable[[str], None]) -> Callable:
        _REGISTRY.append(
            Operation(key=key, label=label, description=description, fn=fn, configure=configure)
        )
        return fn
    return decorator

# ── ADB / process helpers ─────────────────────────────────────────────────────

def _run(*args: str, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(list(args), capture_output=True, text=True, **kwargs)

def _run_bin(*args: str) -> subprocess.CompletedProcess:
    """Like _run but captures stdout as raw bytes (needed for binary pulls)."""
    return subprocess.run(list(args), capture_output=True)

def adb(serial: str, *args: str) -> subprocess.CompletedProcess:
    return _run("adb", "-s", serial, *args)

def adb_shell(serial: str, cmd: str) -> tuple[int, str]:
    r = adb(serial, "shell", cmd)
    return r.returncode, r.stdout.strip()

def adb_pull_binary(serial: str, remote_cmd: str) -> bytes:
    """
    Pull binary data from a device via ``exec-out``.
    ``remote_cmd`` is the shell command whose stdout is the binary stream.
    """
    r = _run_bin("adb", "-s", serial, "exec-out", remote_cmd)
    return r.stdout

def get_connected_devices() -> list[str]:
    r = _run("adb", "devices")
    result = []
    for line in r.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) == 2 and parts[1] == "device":
            result.append(parts[0])
    return result

def device_label(serial: str) -> str:
    """Return ``Model (serial)`` for display."""
    _, model = adb_shell(serial, "getprop ro.product.model")
    return f"{model.strip() or 'Unknown'} ({serial})"

# ── Hive CE binary parser ─────────────────────────────────────────────────────
#
# Format (hive_ce 2.x):
#
#   Frame = [frameLen: u32le]          — total frame size including this field
#           [key_type: u8]             + key data
#           [value_type: u8]           + value data
#           [crc: u32le]               — last 4 bytes of frame
#
#   Frame-level key encoding:
#     key_type 0 (uint)   → [uint32: u32le]
#     key_type 1 (string) → [byteCount: u8] [UTF-8 bytes]   ← u8, NOT u32
#
#   Value type codes (BinaryReader.read):
#     0   null
#     1   int    → float64 LE (stored as double, then .toInt())
#     2   double → float64 LE
#     3   bool   → u8 (0 = false, 1 = true)
#     4   string → [len: u32le] [UTF-8 bytes]
#     5   byte list   → [count: u32le] [u8 * count]
#     6   int list    → [count: u32le] [f64 * count]
#     7   double list → [count: u32le] [f64 * count]
#     8   bool list   → [count: u32le] [u8 * count]
#     9   string list → [count: u32le] ([len: u32le] [UTF-8])* count
#    10   list (generic) → [count: u32le] ([type: u8] [data])* count
#    11   map  → [count: u32le] ([key_type: u8] [key_data] [val_type: u8] [val_data])* count
#
# Note: inside maps/lists, keys are encoded as typed VALUES (using u32le for
# string lengths), NOT as frame-level keys (which use u8 lengths).

def _ru32(data: bytes, pos: int) -> tuple[int, int]:
    (v,) = struct.unpack_from("<I", data, pos)
    return v, pos + 4

def _rf64(data: bytes, pos: int) -> tuple[float, int]:
    (v,) = struct.unpack_from("<d", data, pos)
    return v, pos + 8


def _read_value(data: bytes, pos: int) -> tuple[object, int]:
    """
    Decode a typed value at ``pos``.  Returns ``(value, new_pos)``.

    Handles all scalar and container types recursively.  Unknown types raise
    ``ValueError`` so callers can decide whether to skip the enclosing frame.
    """
    t = data[pos]; pos += 1

    if t == 0:    # null
        return None, pos

    elif t == 1:  # int (stored as float64)
        v, pos = _rf64(data, pos)
        return int(v), pos

    elif t == 2:  # double
        return _rf64(data, pos)

    elif t == 3:  # bool
        return bool(data[pos]), pos + 1

    elif t == 4:  # string
        slen, pos = _ru32(data, pos)
        s = data[pos:pos + slen].decode("utf-8")
        return s, pos + slen

    elif t == 5:  # byte list
        count, pos = _ru32(data, pos)
        return list(data[pos:pos + count]), pos + count

    elif t == 6:  # int list
        count, pos = _ru32(data, pos)
        lst = []
        for _ in range(count):
            v, pos = _rf64(data, pos)
            lst.append(int(v))
        return lst, pos

    elif t == 7:  # double list
        count, pos = _ru32(data, pos)
        lst = []
        for _ in range(count):
            v, pos = _rf64(data, pos)
            lst.append(v)
        return lst, pos

    elif t == 8:  # bool list
        count, pos = _ru32(data, pos)
        lst = [bool(data[pos + i]) for i in range(count)]
        return lst, pos + count

    elif t == 9:  # string list
        count, pos = _ru32(data, pos)
        lst = []
        for _ in range(count):
            slen, pos = _ru32(data, pos)
            lst.append(data[pos:pos + slen].decode("utf-8"))
            pos += slen
        return lst, pos

    elif t == 10:  # generic list
        count, pos = _ru32(data, pos)
        lst = []
        for _ in range(count):
            v, pos = _read_value(data, pos)
            lst.append(v)
        return lst, pos

    elif t == 11:  # map
        count, pos = _ru32(data, pos)
        d: dict = {}
        for _ in range(count):
            k, pos = _read_value(data, pos)   # key is a typed value
            v, pos = _read_value(data, pos)
            d[k] = v
        return d, pos

    else:
        raise ValueError(f"Unknown Hive value type {t} at offset {pos - 1:#x}")


def parse_hive_box(raw: bytes) -> dict[str | int, object]:
    """
    Parse a Hive CE .hive file and return a ``{key: value}`` dict.

    Keys are ``str`` (type 1) or ``int`` (type 0) depending on the box.
    Values are fully decoded Python objects (dicts, lists, scalars, None).
    Frames that fail to parse are silently skipped.
    """
    entries: dict[str | int, object] = {}
    pos = 0

    while pos + 4 <= len(raw):
        frame_start = pos
        frame_len, pos = _ru32(raw, pos)

        # Minimum valid frame: frameLen(4) + key_type(1) + val_type(1) + crc(4) = 10
        if frame_len < 10:
            pos = frame_start + 1
            continue

        frame_end = frame_start + frame_len
        if frame_end > len(raw):
            break  # truncated file

        try:
            # ── Read frame-level key ──────────────────────────────────────────
            # Frame keys use a DIFFERENT encoding from value strings:
            # string length is u8 here, not u32.
            key_type = raw[pos]; pos += 1

            if key_type == 0:    # uint key
                key, pos = _ru32(raw, pos)
            elif key_type == 1:  # string key (u8 length)
                klen = raw[pos]; pos += 1
                key = raw[pos:pos + klen].decode("utf-8")
                pos += klen
            else:
                pos = frame_end
                continue  # unknown key type — skip frame

            # ── Read value ────────────────────────────────────────────────────
            data_end = frame_end - 4  # CRC occupies the last 4 bytes
            if pos >= data_end:
                entries[key] = None   # deleted/tombstone frame
            else:
                val, _ = _read_value(raw, pos)
                entries[key] = val

        except (struct.error, IndexError, UnicodeDecodeError, ValueError):
            pass  # corrupted or unknown frame — skip

        pos = frame_end  # always advance to the next frame boundary

    return entries

# ── Registered operations ─────────────────────────────────────────────────────

# Shared state: build the APK once per run even if multiple devices connect.
_apk_built: bool = False


@operation(
    "install",
    "Build & Install APK",
    "Build the release APK (once per run) then sideload it onto the device",
)
def op_install(serial: str) -> None:
    global _apk_built

    if not _apk_built:
        log("Building release APK…")
        r = subprocess.run(
            ["flutter", "build", "apk", "--release"],
            cwd=SCRIPT_DIR,
        )
        if r.returncode != 0:
            log("ERROR: flutter build failed — skipping install")
            return
        if not APK_PATH.exists():
            log(f"ERROR: APK not found at {APK_PATH}")
            return
        _apk_built = True
        log("Build complete.")

    log(f"  Installing APK on {device_label(serial)}…")
    r = adb(serial, "install", "-r", str(APK_PATH))
    if r.returncode == 0:
        log("  ✓ Install succeeded")
    else:
        err = (r.stderr or r.stdout).strip()
        log(f"  ✗ Install failed: {err}")


def _list_hive_files(serial: str) -> list[str]:
    """
    Return the basenames of every .hive file in the app's data directory
    on the given device (e.g. ["localData.hive", "api_cache.hive"]).
    """
    rc, out = adb_shell(
        serial,
        f"run-as {PACKAGE_ID} ls {APP_DATA}",
    )
    if rc != 0 or not out:
        return []
    return [f for f in out.splitlines() if f.endswith(".hive")]


@operation(
    "export",
    "Export Hive Data",
    "Pull all Hive boxes from the device and save as a ZIP of JSON documents",
)
def op_export(serial: str) -> None:
    label     = device_label(serial)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_ser  = re.sub(r"[^\w\-]", "_", serial)
    zip_name  = f"pawfinder_export_{safe_ser}_{timestamp}.zip"
    zip_path  = SCRIPT_DIR / zip_name

    log(f"  Exporting Hive data from {label}…")

    hive_files = _list_hive_files(serial)
    if not hive_files:
        log(f"  ✗  Could not list Hive files (run-as failed — "
            f"is the fleet-built APK installed? build with 'Build & Install APK')")
        return

    log(f"  Found {len(hive_files)} .hive file(s): {', '.join(hive_files)}")
    exported_any = False

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:

        for hive_filename in hive_files:
            box = hive_filename.removesuffix(".hive")
            hive_path = f"{APP_DATA}/{hive_filename}"
            raw = adb_pull_binary(
                serial,
                f"run-as {PACKAGE_ID} cat {hive_path}",
            )

            if not raw:
                log(f"  ⚠  Could not read {hive_filename} — skipping")
                continue

            exported_any = True

            # Always save the raw binary — can be restored to another device
            zf.writestr(f"raw/{hive_filename}", raw)

            # Parse and write individual JSON documents
            entries = parse_hive_box(raw)
            for key, value in entries.items():
                safe_key = re.sub(r"[^\w\-]", "_", str(key))
                zf.writestr(
                    f"{box}/{safe_key}.json",
                    json.dumps(
                        {"_key": key, "value": value},
                        indent=2,
                        ensure_ascii=False,
                        default=str,  # fallback for any non-serializable types
                    ),
                )

            log(f"  ✓ {hive_filename}: {len(entries)} entries → {box}/*.json")

        # Manifest so you know where the export came from
        zf.writestr(
            "manifest.json",
            json.dumps(
                {
                    "device":      label,
                    "serial":      serial,
                    "exported_at": datetime.now().isoformat(),
                    "package":     PACKAGE_ID,
                    "hive_files":  hive_files,
                },
                indent=2,
            ),
        )

    if exported_any:
        log(f"  ✓ Export saved → {zip_name}")
    else:
        zip_path.unlink(missing_ok=True)
        log("  ✗ No data could be exported")


@operation(
    "reset",
    "Reset App Data",
    "Clear ALL Pawfinder app data on the device (cache, prefs, Hive boxes — irreversible)",
)
def op_reset(serial: str) -> None:
    label = device_label(serial)
    log(f"  Resetting app data on {label}…")

    # pm clear wipes data + cache, returning "Success" on success
    rc, out = adb_shell(serial, f"pm clear {PACKAGE_ID}")
    if rc == 0 and "Success" in out:
        log("  ✓ App data cleared")
    else:
        log(f"  ✗ Reset failed (rc={rc}): {out or '(no output)'}")


# ── Provision credentials ─────────────────────────────────────────────────────
#
# How it works:
#   1. The user pastes the provisioning payload at "go" time.
#   2. When a device connects, the base64 payload is written via `run-as` to
#      pending_credentials.json inside the app's documents directory.
#   3. On next launch, device_auth_service.initialize() detects the file,
#      decodes it, calls provision(), deletes the file, and the app boots
#      authenticated.

_provision_payload_b64: str | None = None


def _configure_provision() -> bool:
    """Prompt for the credential payload once, before watching."""
    global _provision_payload_b64
    print()
    print("  Paste the Pawfinder provisioning payload (from Beariscope).")
    print("  Press Enter on a blank line when done:")
    lines: list[str] = []
    try:
        while True:
            line = input()
            if not line.strip() and lines:
                break
            if line.strip():
                lines.append(line.strip())
    except EOFError:
        pass

    raw = "".join(lines).strip()
    if not raw:
        print("  ✗ No payload provided — provision step will not run.")
        return False
    try:
        _provision_payload_b64 = _normalize_provision_payload(raw)
        print("  ✓ Provisioning payload accepted")
        return True
    except (json.JSONDecodeError, ValueError, binascii.Error, UnicodeDecodeError) as exc:
        print(f"  ✗ Invalid provisioning payload: {exc}")
        return False


def _normalize_provision_payload(raw: str) -> str:
    stripped = raw.strip()

    try:
        json.loads(stripped)
    except json.JSONDecodeError:
        try:
            decoded = base64.b64decode(stripped, validate=True).decode()
            json.loads(decoded)
            return stripped
        except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("payload must be valid base64 or JSON") from exc
    else:
        return base64.b64encode(stripped.encode()).decode()


@operation(
    "provision",
    "Preload Credentials",
    "Push Auth0 credentials to the device so the app self-provisions on next launch",
    configure=_configure_provision,
)
def op_provision(serial: str) -> None:
    if _provision_payload_b64 is None:
        log("  ✗ No provisioning payload configured — skipping")
        return

    label  = device_label(serial)
    target = f"{APP_DATA}/pending_credentials.json"
    log(f"  Staging credentials on {label}…")

    proc = subprocess.run(
        ["adb", "-s", serial, "shell",
         f"run-as {PACKAGE_ID} sh -c 'mkdir -p {APP_DATA} && cat > {target}'"],
        input=_provision_payload_b64,
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        log("  ✓ pending_credentials.json written with base64 payload — will apply on next app launch")
    else:
        err = (proc.stderr or proc.stdout).strip()
        log(f"  ✗ Failed to stage credentials: {err}")


# ── Menu ──────────────────────────────────────────────────────────────────────

_CHECK   = "✓"
_UNCHECK = "○"


def _parse_selection(raw: str) -> list[int] | None:
    """
    Parse a space- or comma-separated list of 1-based indices.
    Returns ``None`` on invalid input.
    """
    try:
        indices = [int(x) - 1 for x in re.split(r"[\s,]+", raw.strip()) if x]
        if any(i < 0 or i >= len(_REGISTRY) for i in indices):
            return None
        return sorted(set(indices))
    except ValueError:
        return None


def show_menu() -> list[Operation]:
    """
    Display an interactive multi-select menu and return the chosen operations.
    """
    selected: set[int] = set()

    while True:
        print("\n" + "─" * 50)
        print("  Pawfinder Fleet Manager")
        print("─" * 50)
        print("  Operations:")
        for i, op in enumerate(_REGISTRY, 1):
            mark = _CHECK if (i - 1) in selected else _UNCHECK
            print(f"    [{mark}] {i}. {op.label}")
            print(f"          {op.description}")
        print()
        print("  Enter number(s) to toggle (e.g. 1 3), or:")
        print("    a  → select all       c → clear all")
        print("    go → start watching   q → quit")
        print()

        raw = input("  > ").strip().lower()

        if raw == "q":
            print("Bye.")
            sys.exit(0)
        elif raw == "a":
            selected = set(range(len(_REGISTRY)))
        elif raw == "c":
            selected.clear()
        elif raw == "go":
            if not selected:
                print("  Please select at least one operation first.")
                continue
            ops = [_REGISTRY[i] for i in sorted(selected)]
            # Run configure hooks for ops that need them
            ready: list[Operation] = []
            for op in ops:
                if op.configure is None:
                    ready.append(op)
                else:
                    print()
                    if op.configure():
                        ready.append(op)
                    else:
                        print(f"  ✗ '{op.label}' will be skipped this run.")
            if not ready:
                print("  No operations ready — please select again.")
                continue
            print("\n  Will apply to each new device:")
            for op in ready:
                print(f"    {_CHECK} {op.label}")
            return ready
        else:
            indices = _parse_selection(raw)
            if indices is None:
                print(f"  Invalid — enter number(s) between 1-{len(_REGISTRY)}, 'a', 'c', 'go', or 'q'.")
                continue
            for i in indices:
                if i in selected:
                    selected.discard(i)
                else:
                    selected.add(i)

# ── Device watcher ────────────────────────────────────────────────────────────

def log(msg: str) -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")


def watch_and_apply(ops: list[Operation]) -> None:
    """
    Poll ADB for new device connections and apply ``ops`` to each one.
    Devices that disconnect are removed from the known set so a reconnect
    will trigger them again.
    """
    known: set[str] = set()
    if known:
        log(f"Already connected ({len(known)}): {', '.join(known)}")
    else:
        log("No devices currently connected — waiting…")

    op_names = ", ".join(op.label for op in ops)
    log(f"Watching for new devices. Will run: {op_names}")
    log("Press Ctrl+C to stop.\n")

    try:
        while True:
            time.sleep(POLL_SECS)
            current = set(get_connected_devices())

            for serial in current - known:
                label = device_label(serial)
                log(f"New device: {label}")
                # Wait until ADB handshake is complete
                _run("adb", "-s", serial, "wait-for-device")

                for op in ops:
                    log(f"  → {op.label}")
                    op.fn(serial)

                known.add(serial)
                log(f"Done with {label}. Watching for next device…\n")

            # Prune disconnected devices so reconnect triggers again
            known &= current

    except KeyboardInterrupt:
        print("\nStopped.")

# ── Pre-flight checks ─────────────────────────────────────────────────────────

def check_prerequisites() -> bool:
    ok = True
    for cmd in ("adb", "flutter"):
        if shutil.which(cmd) is None:
            print(f"ERROR: '{cmd}' not found in PATH")
            ok = False
    return ok

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if not check_prerequisites():
        sys.exit(1)

    selected = show_menu()
    watch_and_apply(selected)


if __name__ == "__main__":
    main()
