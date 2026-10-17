"""Audit the publishable Git file set, excluding ignored caches and build outputs."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def audit():
    result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                            cwd=ROOT, capture_output=True, check=True)
    names = sorted(set(n.decode("utf-8") for n in result.stdout.split(b"\0") if n))
    banned = ["734" + "357", "lumi" + "ere", "RE:" + "UNION", "Mori" + "mori",
              "Ice" + " vs", "sis" + "os", "ic" + "loud", "claude" + " workspace"]
    secrets = re.compile(r"sk" + r"-|ghp" + r"_|AK" + r"IA|-----" + r"BEGIN", re.I)
    email = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    personal_path = re.compile(r"[A-Za-z]:[\\/](?:Users|home)[\\/](?!Test[\\/])", re.I)
    failures = []
    audio = []
    demo_hash = hashlib.sha256((ROOT / "songs/_demo/audio.wav").read_bytes()).hexdigest()
    for name in names:
        p = ROOT / name
        if not p.is_file():
            failures.append({"file": name, "reason": "missing or non-file Git entry"})
            continue
        data = p.read_bytes()
        lower = data.lower()
        for index, term in enumerate(banned):
            if term.lower() in name.lower() or term.lower().encode() in lower or term.lower().encode("utf-16-le") in lower:
                failures.append({"file": name, "reason": "removed identity/personal string", "pattern_index": index})
        if p.suffix.lower() in (".wav", ".mp3", ".ogg", ".flac", ".m4a", ".aac", ".opus", ".aiff", ".mid", ".midi"):
            digest = hashlib.sha256(data).hexdigest()
            audio.append({"file": name, "bytes": len(data), "sha256": digest})
            allowed = name == "songs/_demo/audio.wav" or (name.startswith("songs/_plugin_demos/") and name.endswith("/audio.wav"))
            if not allowed or digest != demo_hash:
                failures.append({"file": name, "reason": "unexpected audio or unequal plugin copy"})
        if len(data) > 5_000_000 and not (p.suffix.lower() == ".wav" and name.startswith("songs/")):
            failures.append({"file": name, "reason": "non-demo file exceeds 5 MB", "bytes": len(data)})
        # Byte scanning catches credentials even in non-UTF8 files; report no matched credential bytes.
        if secrets.search(data.decode("utf-8", errors="ignore")) and p.suffix.lower() not in (".png", ".jpg", ".wav") :
            failures.append({"file": name, "reason": "credential-like bytes"})
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if email.search(text) or personal_path.search(text):
            failures.append({"file": name, "reason": "email or personal absolute path"})
    return {"scope": "git ls-files --cached --others --exclude-standard -z", "files": len(names),
            "audio": audio, "failures": failures, "passed": not failures}


if __name__ == "__main__":
    report = audit()
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["passed"] else 1)
