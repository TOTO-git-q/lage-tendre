"""Offline charter demo preparation, recording and encoding (no external packages)."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/demo"
from godot_path import default_godot
GODOT = Path(default_godot())


def hashes():
    return {p.relative_to(ROOT / "songs").as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / "songs").rglob("*")) if p.is_file()}


def log(text):
    with (ROOT / "VIDEO_WORKLOG.md").open("a", encoding="utf-8") as f:
        f.write("\n" + text.strip() + "\n")


def environment():
    env = os.environ.copy()
    for key, folder in {"APPDATA": "userdata", "LOCALAPPDATA": "localdata", "HOME": "home",
                        "USERPROFILE": "home", "XDG_DATA_HOME": "xdg-data", "XDG_CONFIG_HOME": "xdg-config",
                        "CLAUDE_CONFIG_DIR": "claude", "CODEX_HOME": "codex"}.items():
        path = OUT / "isolated" / folder
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    return env


def check_sources():
    baseline = json.loads((OUT / "songs-before.json").read_text(encoding="utf-8"))
    current = hashes()
    assert baseline == current, "Original songs changed!"
    (OUT / "songs-after.json").write_text(json.dumps(current, indent=2), encoding="utf-8")
    return len(current)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "rehearse", "record", "encode", "verify", "verify-songs"])
    parser.add_argument("--allow-temp-commits", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    env = environment()
    if args.action == "prepare":
        before = hashes()
        manifest = OUT / "songs-before.json"
        if manifest.exists():
            assert json.loads(manifest.read_text(encoding="utf-8")) == before
        else:
            manifest.write_text(json.dumps(before, indent=2), encoding="utf-8")
        # Always start a fresh tour from the original songs. No deletion outside this exact copy.
        target = (OUT / "songs").resolve()
        assert target == ROOT.resolve() / "dist" / "demo" / "songs"
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(ROOT / "songs", target)
        chart_path = target / "_demo/chart.json"
        chart = json.loads(chart_path.read_text(encoding="utf-8"))
        negative = [e for e in chart.get("fx", []) if e.get("t", 0) < 0]
        assert len(negative) == 1 and negative[0]["ch"] == "exposure" and negative[0]["t"] == -1.0
        negative[0]["t"] = 0.0
        chart_path.write_text(json.dumps(chart, ensure_ascii=False), encoding="utf-8")
        subprocess.run([sys.executable, str(ROOT / "tools/sync_core.py")], check=True, cwd=ROOT)
        project = OUT / "recording-charter"
        if project.exists():
            assert project.resolve() == ROOT.resolve() / "dist" / "demo" / "recording-charter"
            shutil.rmtree(project)
        shutil.copytree(ROOT / "charter", project,
                        ignore=shutil.ignore_patterns(".godot", "shots", "evidence", "out"))
        settings = project / "project.godot"
        source = settings.read_text(encoding="utf-8")
        assert "window_width_override=1600" in source and "window_height_override=900" in source
        settings.write_text(source.replace("window_width_override=1600", "window_width_override=1920")
                            .replace("window_height_override=900", "window_height_override=1080"), encoding="utf-8")
        with (OUT / "import.log").open("w", encoding="utf-8") as stream:
            subprocess.run([str(GODOT), "--headless", "--audio-driver", "Dummy", "--path", str(project),
                            "--import"], env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
        assert check_sources() == len(before)
        log(f"## Preparation verified\n- SHA-256 baseline covers all {len(before)} original song files; copied songs into `dist/demo/songs/` and verified originals unchanged.\n- In the disposable hard chart only, moved the existing exposure event from t=-1 to t=0: the editor rejects all edits while any event has negative time. No original content or editor validation changed.\n- Ran `python tools/sync_core.py`; isolated, headless, muted charter import completed successfully.\n- Recording environment isolates APPDATA, LOCALAPPDATA, HOME, USERPROFILE, XDG, Claude and Codex configuration. Demo bridge disables authentication probes.")
    elif args.action in ("rehearse", "record"):
        recording = args.action == "record"
        command = [str(GODOT), "--path", str(OUT / "recording-charter"), "--position", "-5000,-5000",
                   "--resolution", "1920x1080", "--rendering-driver", "opengl3", "--fixed-fps", "60"]
        if recording:
            command += ["--write-movie", str(OUT / "charter_raw.avi")]
        else:
            command += ["--audio-driver", "Dummy"]
        command += ["-s", "res://tests/demo_tour.gd", "--", "--songs-root=" + str(OUT / "songs"),
                    "--song=_demo", "--shots-scaled"]
        if not recording:
            command.append("--rehearsal")
        if args.allow_temp_commits:
            command.append("--allow-temp-commits")
        with (OUT / (args.action + ".log")).open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
            (OUT / "owned-process.json").write_text(json.dumps({"pid": process.pid, "command": command}, indent=2), encoding="utf-8")
            try:
                code = process.wait(timeout=3600 if recording else 600)
            except subprocess.TimeoutExpired:
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                raise
        count = check_sources()
        print(f"{args.action} exit={code}; {count} original song files unchanged", flush=True)
        raise SystemExit(code)
    elif args.action == "encode":
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        receipt = json.loads((OUT / "tour-receipt.json").read_text(encoding="utf-8"))
        assert receipt["passed"] and receipt["markers"][-1]["name"] == "10-end"
        raw_end = receipt["markers"][-1]["seconds"]
        # Godot 4.7 muxes Movie Maker's PCM mix into AVI; extract it losslessly for analysis.
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(OUT / "charter_raw.avi"), "-map", "0:a:0",
                        "-c:a", "pcm_s16le", str(OUT / "charter_raw.wav")], check=True)
        common = [ffmpeg, "-y", "-i", str(OUT / "charter_raw.avi"), "-i", str(OUT / "charter_raw.wav"),
                  "-map", "0:v:0", "-map", "1:a:0", "-af", f"atrim=end={raw_end},atempo=1.25", "-c:v", "libx264", "-preset", "medium",
                  "-pix_fmt", "yuv420p", "-r", "60", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        common += ["-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
        for small in (False, True):
            name = "charter_demo_small.mp4" if small else "charter_demo.mp4"
            dimensions = "1280:720" if small else "1920:1080"
            filters = (f"trim=end={raw_end},setpts=PTS/1.25,scale={dimensions}:flags=lanczos:"
                       "in_range=pc:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709,format=yuv420p")
            with (OUT / (name + ".log")).open("w", encoding="utf-8") as stream:
                subprocess.run(common + ["-vf", filters, "-crf", "24" if small else "18", str(OUT / name)],
                               stdout=stream, stderr=subprocess.STDOUT, check=True)
        check_sources()
        log("## Encoding verified\n- FFmpeg completed both H.264/yuv420p 60 fps, AAC 192k, faststart encodes. Video uses `setpts=PTS/1.25`; audio uses `atempo=1.25`. Main output CRF 18 at 1920×1080; chat output CRF 24 at 1280×720. Both stop at the verified clean-ending marker, excluding shutdown frames. Original song hashes still match.")
    elif args.action == "verify":
        import array
        import math
        import wave
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        receipt = json.loads((OUT / "tour-receipt.json").read_text(encoding="utf-8"))
        assert receipt["passed"] and all(c["ok"] for c in receipt["checks"])
        times = {m["name"]: m["seconds"] for m in receipt["markers"]}
        selected = ["01-playback", "03-vector-curve", "04-notes", "06-camera", "07-versions", "08-plugin-fields"]
        stills = OUT / "stills"
        stills.mkdir(exist_ok=True)
        summary = {"checks": len(receipt["checks"]), "original_songs_unchanged": check_sources(), "files": {}, "stills": {}}
        for name in selected:
            timestamp = (times[name] + 0.16) / 1.25
            filename = stills / (name + ".png")
            subprocess.run([ffmpeg, "-v", "error", "-y", "-ss", str(timestamp), "-i", str(OUT / "charter_demo.mp4"),
                            "-frames:v", "1", str(filename)], check=True)
            assert filename.exists() and filename.stat().st_size > 10000
            summary["stills"][filename.name] = timestamp
        for filename, resolution in [("charter_demo.mp4", "1920x1080"), ("charter_demo_small.mp4", "1280x720")]:
            path = OUT / filename
            metadata = subprocess.run([ffmpeg, "-hide_banner", "-i", str(path)], capture_output=True).stderr.decode("utf-8", errors="replace")
            assert resolution in metadata and "60 fps" in metadata and "yuv420p" in metadata and "aac" in metadata
            match = re.search(r"Duration: (\d+):(\d+):([\d.]+)", metadata)
            duration = int(match[1])*3600 + int(match[2])*60 + float(match[3])
            decoded = subprocess.run([ffmpeg, "-v", "error", "-i", str(path), "-f", "null", "-"], capture_output=True, timeout=600)
            assert decoded.returncode == 0 and not decoded.stderr, decoded.stderr.decode(errors="replace")
            blob = path.read_bytes()
            assert blob.find(b"moov") < blob.find(b"mdat"), "faststart moov must precede media data"
            summary["files"][filename] = {"duration_seconds": duration, "bytes": len(blob), "resolution": resolution,
                                          "sha256": hashlib.sha256(blob).hexdigest(), "full_decode": "pass", "faststart": True}
        with wave.open(str(OUT / "charter_raw.wav"), "rb") as audio:
            summary["raw_duration_seconds"] = audio.getnframes() / audio.getframerate()
            assert audio.getsampwidth() == 2
            levels = {}
            for name, start in {"opening_music": times["01-playback"]-3, "editing_silence": times["03-vector-curve"]+0.2,
                                "final_music": times["09-finale"]-3}.items():
                audio.setpos(int(start * audio.getframerate()))
                data = array.array("h", audio.readframes(audio.getframerate()))
                rms = math.sqrt(sum(float(v)*v for v in data) / len(data)) / 32768
                levels[name] = {"rms": rms, "peak": max(abs(v) for v in data)/32768}
            assert levels["opening_music"]["rms"] > 0.005 and levels["final_music"]["rms"] > 0.005
            assert levels["editing_silence"]["rms"] < 0.001
            summary["audio"] = levels
        (OUT / "verification.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        log("## Artifact checks verified\n- Extracted six representative stills from the final main MP4. Both MP4s fully decode without errors; verified H.264/yuv420p, 60 fps, AAC, target dimensions and faststart atom order.\n- Raw Movie Maker WAV contains music in both playback segments and silence in the sampled editing interval. All original song hashes match.\n- Sizes, durations, SHA-256 values, still timestamps and audio measurements are in `dist/demo/verification.json`. Visual still review remains to be completed.")
        print(json.dumps(summary, indent=2))
    else:
        print(f"SHA-256 verified: {check_sources()} original song files unchanged")


if __name__ == "__main__":
    main()
