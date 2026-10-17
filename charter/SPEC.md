# L'âge tendre Charter — desktop chart editor with built-in MCP and a Claude panel (SPEC, 2026-10-16)

> Original functional specification. Current project layout, build and verification commands are in `README.md`
> and `../README.md`. The legacy web/Python tools referenced as design context below are not dependencies of
> this independent project.

The owner wants the chart editor rebuilt from scratch as an **independent desktop application** (not a web page),
with a **built-in MCP server** that exposes *everything* about a chart (so an AI never has to judge from screenshots),
and a **Claude side panel** inside the app: select a range of the chart, describe the change, Claude edits it through
the MCP. The old web editor (`spotlight-rhythm/editor.html`, screenshot `spotlight-rhythm/research/charter_app_ref/old_web_editor.png`)
is obsolete: wrong syntax, validates against a dead web build, cluttered. Do not reuse its code; you may read it for ideas.

## 0. Technology (decided)
- **Godot 4.7.2, independent `charter/` project** (restructured 2026-10-17): scenes/scripts under `res://`
  (this folder), main scene `res://charter_main.tscn`. Run `python tools/sync_core.py` from the repository root
  before launching with `Godot_v4.7.2-stable_win64_console.exe --path charter`. Its own "Charter" preset
  exports `dist/LAgeTendreCharter/LAgeTendreCharter.exe`; `game/` has a separate game preset. See the root README
  for packaging and shared runtime ownership. References below to removed web/offline tools are historical context.
- Reason: the editor reuses the game's own code — `ChartLib` (validate / build_timelines / light_at), `GameCore`
  (judgement, autoplay, ticks, cut windows), `Renderer` + `StageFx` (the exact play field and camera), `AudioEngine`, `KB`, `SU`.
  The preview is the real game renderer, so what the charter sees is what the player sees.
- Godot binary: `$env:GODOT`. Renderer: GL Compatibility (as the game).
- Python 3 for repository tooling; optional offline analysis is not bundled.

## 1. Read first (do not skip)
- Chart syntax v3 (authoritative): `docs/CHART_SYNTAX.md` sections "Chart syntax v2" and "Syntax v3".
  Lights `{t,id,type:on|sweep|pulse|off,x,w,a,dur,ease,tint,auto}` (+`from` only on pedal cues = non-auto events);
  notes `{t,light,u,kind:tap|hold,dur,k,nw,path,big,ex,grow}`; `fx` = camera/stage events; `meta` (kiai, breath energy curve, mod legacy).
- Game code: `game/scripts/{su,chart_lib,game_core,renderer,stage_fx,kb,audio_engine,main}.gd`.
  Judgement facts the editor must show/expose come from `game_core.gd` (cut windows `w_e/w_l`, hold `ticks`, chords,
  fingering `k`/`key_code`/`hint`, snap rules) and `su.gd` (windows, KEY_PAD, LIGHT_OVER, HOLD_GAP_*, hold_tick).
- The existing Python charting MCP `spotlight-rhythm/tools/charter/charter/*.py` (23 tools: read/edit/lint/staging/music/
  render/autoplay/playtest): reuse its *ideas and semantics* (bar.beat addressing, revisions, transactional edits,
  lint rules, music data) for the new built-in MCP. It stays in the repo; the new app does not depend on it at runtime.
- Design taste: `spotlight-rhythm/research/charter_app_ref/claude_storybook.html` (the "Claude Design System" storybook:
  tailwind tokens — clay `#d97757` / hover `#cc5a36` / light `#fbf3ef`, surfaces light0 `#f5f5f3` light1 `#fcfcfb`
  light2 `#ffffff`, dark0 `#0b0b0a` dark1 `#151515` dark2 `#1a1a19` dark3 `#20201e`, radii, shadows, motion tokens,
  Chat Composer, message bubbles, thinking accordion, segmented control, tool cards) and its screenshot `storybook.png`.
  The owner's second reference is the Figma community file "MCP Apps for Claude" (not downloadable; same family: calm
  cream/dark surfaces, one clay accent, generous spacing, soft 1px borders, rounded cards, serif display titles + sans UI).
  Read the HTML for exact tokens. Implement them as a Godot `Theme` (+ light and dark variants; default dark, because the
  play preview is dark). Fonts: Windows `SystemFont` with fallbacks ("Inter", "Segoe UI Variable", "Segoe UI",
  "Microsoft YaHei UI"; display serif "Newsreader"/"Georgia"/"Source Han Serif SC"; mono "JetBrains Mono"/"Cascadia Mono"/"Consolas").
  No new downloaded fonts or assets. UI language: Chinese labels (short English sub-labels allowed).

## 2. Core rule: tracks first, notes on tracks
- A note can only be placed where a **live track covers the note's fingering key at landing** (key centre (2.25+k)/15 inside
  [x−w/2, x+w/2] at t, padded like the game: `KEY_PAD`), and the track must be alive from **t−1.3 s** (notes ride their track
  while falling) until the note's end (hold end). Otherwise the placement is refused with a reason (GUI tooltip + MCP error).
- A track edit that would orphan notes is refused unless the same transaction also moves/deletes those notes, or the user
  chooses "notes follow the track" (re-seat `u` so each note keeps its landing key if still covered, else refuse).
- Transparent tracks (`a: 0`) are first-class: they carry/judge notes invisibly; a visible performer track can move over them.

## 3. Window layout (Claude-style, 1600×900 minimum, resizable)
- **Top bar**: song picker, transport (play/pause, from cursor, loop selection), playback rate 0.25–1, metronome / note-tick
  toggles, snap selector, undo/redo, save state, theme toggle, "试玩" (test play in the real game core from cursor; autoplay toggle).
- **Left sidebar**: tracks/layers list (id, role = carrier/performer/background/cue by notes & opacity, colour chip, lifetime,
  note count; show/hide/solo/lock; create track), sections/bars list (kiai, `meta` sections if present), search.
- **Centre — timeline**: vertical time (up = later), horizontal 0..15 key units (left Shift = 0, right Shift = 15).
  Draw tracks as bands (opacity ∝ `a`, tint colour, sweep shapes with their ease), notes (tap/hold/ex yellow/big), hold
  ticks, optional cut-window whiskers, chords, fingering letters. Calm by default: labels only on hover/selection
  (the old editor labelled every event — that clutter is a known failure).
- **Centre-right — live preview**: the real game `Renderer` in a SubViewport at the playhead (arch field, background,
  key guides, camera/`fx` applied), scrubbing in sync with the timeline. Toggle between "preview" and "timeline only".
- **Bottom**: waveform overview + energy curve + section/kiai bands; **camera & judgement-line lanes** (§5) as curves with
  their word scales; property lanes for the selected track (x, w, a, tint) as editable keyframe curves.
- **Right — inspector**: selected objects' properties as numbers *and* their readable forms (bar.beat, ms, key names, words).
- **Right — Claude panel** (collapsible, §7).

## 4. Rulers and scales ("表明详细的刻度")
- Time ruler: bar.beat labels (bar 0 = `timing[0].t`, pickup bar −1, `49.1+3/16` style as the Python charter), subdivision
  ticks for the current snap (1/1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16), seconds `m:ss.mmm` on the opposite edge, BPM changes,
  section names. Cursor readout: chart s, audio s, bar.beat, beat fraction.
- Key ruler: 0..15 units with 0.25-unit ticks, every key column of the home row labelled (A S D F G H J K L ; '), the other
  rows' keys available as a hover overlay, F/J/Shift guide lines, the G|H centre, LIGHT_OVER spill zones outside 0..15.
- Opacity scale 0 / .25 / .5 / .75 / 1; tint palette chips 0–9 with names; width in keys.
- Every number in the inspector/MCP has its unit.

## 5. Camera and judgement line — natural-language scales
The chart's `fx` list already drives the game camera (`stage_fx.gd`: channels exposure, zoom, roll, pitch, vpx, bow, rush,
flash, trauma, kick; events `tween {t,ch,to,dur,ease}`, `impulse {t,ch,amp,attack,decay}`, `ring {t}`; empty `fx` = the
engine plans its own). Build a **vocabulary** so a person (or Claude) can describe camera work in words and the editor
shows/edits it with labelled scales:
- One data file `res://camera_vocab.json` used by the GUI labels, the MCP (accepts words or numbers, always returns
  both), tests and docs. For each channel: unit, range (= engine clamp), named levels with values, and a one-line meaning
  in Chinese. Derive each meaning from what the renderer actually does (study `Renderer._geo()` and render offscreen
  screenshots at the extremes; put a contact sheet `charter/vocab_sheet.png` in the folder showing each level).
  Minimum vocabulary:
  - 远近 (zoom): 极远 / 远 / 中 / 近 / 极近; 高低 (pitch, horizon/camera height): e.g. 低机位 / 平视 / 稍高 / 高机位 / 俯瞰
    (name them after what you see); 方向 (vpx): 左转 大/中/小 · 正 · 右转 小/中/大; 倾斜 (roll): 左倾 / 正 / 右倾 with degrees;
    弯度 (bow): 平直 / 微弯 / 弯 / 大弯; 曝光 (exposure): 暗场 / 昏暗 / 正常 / 明亮; 抖动 (trauma impulse): 无 / 微 / 轻 / 中 / 强;
    闪光 (flash), 节拍冲击 (kick), 速度感 (rush).
  - 运动 (how a tween moves): 瞬切 (≤ 0.05 s) / 急 (1 beat) / 中 (2 beats) / 缓 (1 bar) / 极缓 (2+ bars) — durations in
    beats of the local BPM; easing words 匀速 / 渐快 / 渐慢 / 缓入缓出 / 回弹 mapped to the engine ease names.
  - Camera moves as phrases: 推 (zoom in) / 拉 (zoom out) / 摇 (vpx) / 升 / 降 (pitch) / 滚 (roll) / 震 (trauma) — the MCP
    tool `camera_move` takes e.g. `{at:"49.1", move:"推", to:"近", speed:"缓", ease:"缓入缓出"}` and writes the fx events.
- **Judgement line ("判定线整体的行为")**: add engine channels so the line's behaviour is chartable, with named scales:
  `line_y` (line height on screen: 下沉 / 原位 / 上浮, small range, e.g. ±0.04 of screen height), `line_tilt` (±2°,
  follows/ignores camera roll), `line_glow` (0.5–1.5: 隐 / 淡 / 常 / 亮 / 耀). Implement them in `stage_fx.gd` (CH table +
  clamps) and `renderer.gd` (applied to the judgement line and to everything that is drawn relative to it, so hit detection
  geometry and drawing stay consistent). Default values = today's look exactly (a chart without these events renders
  pixel-identical). Keep the clamps conservative: the line must stay readable and hittable. Also expose the static field
  parameters (renderer `hy0`, `gamma0`, `arc0`, `judge_y`, `line_l/line_r`) read-only with their meaning.
- The bottom lanes show each channel as a curve over time with the word levels as horizontal grid labels.

## 6. Built-in MCP server ("谱面的全部信息")
### 6.1 Transport
MCP over **Streamable HTTP** implemented in GDScript (`TCPServer` + minimal HTTP/1.1): `POST http://127.0.0.1:<port>/mcp`,
JSON-RPC 2.0, `initialize` / `notifications/initialized` / `tools/list` / `tools/call` (+ `ping`); respond with
`Content-Type: application/json` (no SSE needed); include `Mcp-Session-Id`. Default port 47800 (setting; if busy, next free).
Bind 127.0.0.1 only. The app writes `user://charter_mcp.json` = `{"mcpServers":{"charter":{"type":"http","url":"http://127.0.0.1:<port>/mcp"}}}`
and shows the URL in the settings. Tools must be fast (no blocking the UI > 50 ms; long jobs such as autoplay simulation run
deferred and report when done).
### 6.2 Read tools (each returns JSON with units; time given as chart s + bar.beat; keys as names + units)
- `song_info`: title, audio path/duration, offset, bpm, timing segments, bar count, sections/kiai, file revision.
- `time_map`: bar.beat ⇄ seconds conversion for given points/ranges; beat grid in a range.
- `selection`: what the user has selected in the GUI (time range, track ids, note ids, camera events) — the Claude panel relies on it.
- `tracks`: every track with id, role, lifetime, colour/opacity history, event list (keyframes), notes carried, motion stats.
- `track_state`: sampled x / w / a / tint / edges in keys / covered keys for a track (or all) at a time or over a range with step.
- `notes`: notes in a range with index, t, bar.beat, kind, dur, track, u, landing x (units) and key, fingering key + hint,
  big/ex/grow/path, chord group, hand, hold ticks (times), judgement windows after the midpoint cut (early/late ms) and the
  neighbour that cut them, distance to previous/next note on the same key.
- `camera`: fx events in a range + sampled channel values (numbers and vocabulary words), judgement-line channels.
- `music`: per-bar / per-beat analysis in a range (§6.4): onsets, accents, stems' levels, pitches/keysounds, energy, sections.
- `analysis`: density per bar and per hand, max chord size, jacks (same-key repeats) and trills, track motion per second,
  coverage/orphans, validator + lint warnings (game `ChartLib.validate` + editor rule checks), with locations.
- `simulate`: run `GameCore` headless on the current document: autoplay, home-key player, optional offset players
  (±30/60/100 ms) and fat-finger player (as `tests/home_keys_song.gd`, `tests/fat_finger_test.gd`); return score/grades/misses with locations.
- `history`: undo stack entries (labels, author: user or Claude).
- `render_frame` (optional, last resort): PNG of the live preview at t — exists, but the data tools above must make it unnecessary.
### 6.3 Edit tools (transactional)
- `edit`: a batch of operations (add/update/delete track events, add/move/update/delete notes, add/update/delete fx events,
  re-seat notes, set meta) applied atomically with `expected_revision`; the rule checks of §2 apply; on any failure nothing
  changes and the error names the operation and the reason. Returns the new revision and a diff summary.
- `camera_move` (vocabulary phrases → fx events, §5), `track_create` / `track_move` (with "notes follow" option),
  `set_selection`, `undo` / `redo` (one Claude turn = one labelled undo step), `save` (writes `songs/<dir>/chart.json` after
  a backup `chart.json.bak-<timestamp>`; the GUI asks when the user saves, the MCP `save` only works when the user has
  enabled "allow Claude to save" in the panel).
- All edits show up live in the GUI.
### 6.4 Music analysis data
Read optional `songs/<dir>/analysis.json` when present. No external music-analysis environment is bundled or required. Analysis provenance must distinguish measured audio data from synthetic test metadata. The editor exposes existing slots, bars, beats and energy through the music tool.

## 7. Claude panel
- A Claude-desktop-like side panel (CDS Chat Composer, message bubbles, collapsible tool-call cards, thinking dots).
- Context chip above the input: the current selection, e.g. "第 44.1–48.1 小节 · 轨道 200, 201 · 23 个 note · 镜头 2 个事件";
  the user can clear/replace it from the GUI selection.
- On send: spawn the Claude Code CLI headless (`CLAUDE_CLI` override, current-user npm install, or `claude` from PATH) with `-p`, `--output-format stream-json --verbose`,
  `--mcp-config user://charter_mcp.json` (globalized path), `--allowedTools "mcp__charter__*"`, built-in file/shell tools
  disallowed, a model picker (aliases accepted by the CLI), and a short system context (`--append-system-prompt`): what the
  app is, the chart rules (§2), the selection, "use the MCP tools; never guess from images". Use `OS.execute_with_pipe` (or a
  thread) to stream stdout lines; render assistant text and tool calls as they arrive; keep `session_id` for follow-ups
  (`--resume`); "停止" kills that child process by its PID only.
- Feel (owner, 2026-10-16): **like the Claude sidebar in Microsoft Edge** — a docked panel on the right edge of the window,
  resizable (320–560 px) and collapsible to a thin icon rail, always available next to the work. As Edge's sidebar knows
  the current page, this panel always knows the current chart and **follows the GUI selection automatically** (the context
  chip updates live; the user can pin it). One conversation per song, kept across app restarts (history + session_id in
  `user://`), with a "新对话" button.
- After a Claude turn: show the diff summary and buttons "保留" / "撤销这次修改" (one undo step), and highlight changed objects
  in the timeline.

## 8. Testing and verification (all silent, offscreen)
- Every Godot run: `--position -5000,-5000` (windowed runs) or `--headless`; never play sound (mute the audio bus in tests).
- Headless GDScript tests under `charter/tests/charter_*.gd`: document model & undo/redo, rule checks (§2) incl.
  refusals, MCP JSON-RPC (start the server, real HTTP requests: initialize, tools/list, a read tool, an edit with stale
  revision refused, an edit accepted), vocabulary round trip words⇄numbers, `edit`→save→reload equals, a saved chart loads in
- The existing game tests must still pass: `tests/one_chart.gd -- fixture_dense` (1010000), `tests/home_keys_song.gd`,
  `tests/fat_finger_test.gd`, `tests/hold_rules_test.gd`, `tests/extap_test.gd`, `tests/snap_test.gd`, `tests/autoplay_test.gd`
  (the `tests/human_keys_test.gd` −0.10 s row fails today by design — leave it).
- A real Claude round trip test: with the app running offscreen, run `claude -p` with the MCP config and a prompt that
  reads `song_info` and `notes` for bar 44 (read-only) — record the transcript in the worklog.
- Visual check: offscreen screenshots of the app (dark and light theme, timeline + preview + Claude panel, camera lanes)
  saved to `charter/shots/`; look at them yourself and iterate until it is clean and Claude-like.

## 9. Rules
- Do not change judgement or existing visuals of the game (except adding the line channels with identical defaults).
- Do not modify `game/tests/fixtures/dense/` except by the explicit test that writes to a temp copy; never delete user files.
- Never kill processes by image name (PID only). `.bat`/`.ps1` files ASCII only. Do not run `build.py` while a game is running.
- Commit nothing; no network installs; no new third-party assets.

## 11. Versions with git, and multi-version diff on one music axis (owner, 2026-10-16)
- **Every song's chart is under git**: one repository per song folder `songs/<dir>/` (created by the app on first save or
  via "启用版本管理"; `.gitignore` excludes `audio.*`, backups and caches; `build.py` already skips dot-folders). Use the
  `git` CLI (2.54 on PATH) through `OS.execute` with explicit `-C <dir>`; never touch any other repository; no remotes, no push.
- Save canonically for readable history: stable key order, one note / one light event / one fx event per line (the game
  reads it unchanged; JSON-equal round trip instead of byte-identical from now on).
- **Commit** = the user's "保存版本" (message editable; default = the undo labels since the last commit, Claude turns
  marked "Claude: …"). Autosave stays a separate working file and is never committed automatically.
- **Writings (写法) = branches**: create / switch / rename / delete (delete only with confirmation, never the current one);
  a version picker shows branches, commits (time, message, author user/Claude) and the working copy.
  Import an existing variant folder as a branch (e.g. a temporary alternate chart into an existing song repository)
  without deleting the source folders. Claude can be asked to "另写一版" = make a branch with an alternative writing.
- **Compare view**: pick 2–4 versions (any branch / commit / the working copy) and show them as **parallel lanes on one
  shared music axis** — one time ruler (bar.beat + seconds), one waveform / energy / section strip, synchronised scroll and
  zoom, each lane a full timeline (tracks, notes, camera curve). Semantic diff against a chosen base lane: added /
  removed / moved / changed notes, track events and fx events coloured consistently; a per-bar "difference heat" strip along
  the axis; hover shows the exact change (e.g. "note 512: 落点 D→F, 时间 +1/16 拍"). Overlay mode (two versions drawn on top
  of each other) as an alternative to side-by-side. Playing/preview follows the cursor for whichever lane is focused.
- **Take a passage from another version** ("这段用 B 的写法"): select a bar range in any lane → apply it to the working
  copy as one undo step (notes, track events and fx inside the range; rule checks of §2 still apply at the seams; report
  conflicts instead of guessing).
- **MCP**: `versions` (branches, commits, working copy), `diff` (semantic, between any two versions, optional range, same
  structure as the GUI), `compare_stats` (density, motion, simulate results side by side), every read tool accepts an
  optional `version` (branch/commit) to read without switching, `branch_create` / `branch_switch` / `commit` (commit only
  when the user enabled it in the panel) / `take_range` (copy a range from a version into the working copy).
- Tests: initialize a temporary repository, create branches and synthetic variants with identical notes and changed lights, verify semantic diff, version reads, take-range and undo round trips.

## 10. Phases, worklog, deliverables
Phases: P1 shell + theme + document model + timeline with rulers → P2 tracks/notes editing with §2 rules, inspector, undo →
P3 live preview + audio + test play → P4 camera/line channels + vocabulary + lanes → P5 MCP server + all tools →
P6 Claude panel → P7 analysis exporter → P8 tests, export preset, screenshots, README → P9 git versions + compare view (§11).
**Worklog protocol**: keep `charter/worklog.md`; after each verified step append what was done, how it was
verified, and where you stopped. If the worklog already has entries, continue from the last one instead of restarting.
Deliver: the app (runs from the Godot project and as `dist/Charter/LAgeTendreCharter.exe` if export templates are
installed — if not, say so), `charter/README.md` (Chinese: how to run, every MCP tool with an example, the camera vocabulary
table), tests passing, screenshots in `charter/shots/`. End the worklog with `CHARTER_APP DONE` (or `CHARTER_APP PARTIAL`
plus what remains).
