"""Reject monitor calls known to crash ART when emitted as invoke-interface."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


UNSAFE_MONITOR_CALL = re.compile(
    r"invoke-interface(?:/range)?\s+\{[^}]*\},\s+L[^;]+;\.(?:wait|notify|notifyAll):"
)


def find_dexdump():
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if not sdk:
        raise SystemExit("Set ANDROID_SDK_ROOT or pass --dexdump.")
    name = "dexdump.exe" if os.name == "nt" else "dexdump"
    candidates = list((Path(sdk) / "build-tools").glob(f"*/{name}"))
    if not candidates:
        raise SystemExit("No SDK dexdump found; pass --dexdump.")
    return max(candidates, key=lambda p: p.parent.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--dexdump", type=Path)
    args = parser.parse_args()
    dexdump = args.dexdump or find_dexdump()
    failures = []
    with zipfile.ZipFile(args.apk) as apk, tempfile.TemporaryDirectory(
        prefix="apk-bytecode-", dir=args.apk.resolve().parent
    ) as folder:
        dex_names = [n for n in apk.namelist() if re.fullmatch(r"classes\d*\.dex", n)]
        if not dex_names:
            raise SystemExit("APK contains no dex files.")
        for name in dex_names:
            dex = Path(folder) / name
            dex.write_bytes(apk.read(name))
            result = subprocess.run(
                [str(dexdump), "-d", str(dex)],
                # Dex strings use modified UTF-8; only instruction text matters here.
                check=True, capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            failures.extend(f"{name}: {line.strip()}" for line in result.stdout.splitlines()
                            if UNSAFE_MONITOR_CALL.search(line))
    if failures:
        raise SystemExit("Unsafe ART monitor calls:\n" + "\n".join(failures))
    print(f"APK bytecode passed: {len(dex_names)} dex files, no unsafe monitor calls.")


if __name__ == "__main__":
    main()
