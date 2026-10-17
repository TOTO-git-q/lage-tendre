# Agent IO worklog

## 2026-10-17 — orientation verified
- Read TASK_AGENT_IO.md, charter README/SPEC, chart syntax, document/tool/server/panel/bridge/library/preview paths and the read-only Python converter reference.
- Verified branch `charter/agent-io`; no previous worklog. Existing untracked COMPOSE_TASK.md, COMPOSE_WORKLOG.md and tools/compose are unrelated and preserved.
- Authority: charter sources, game constants (read-only), docs/CHART_SYNTAX.md. Runtime conversion will use GDScript only.
- Plan: bounded attachment storage and ZIP preflight; osu parser/create/open/draft; tool schemas/image transport/preview; panel and bridge; original fixtures and MCP/visual/regression validation.
- Boundaries: no game/judgement or existing song changes; no commits/pushes/dependencies. New songs are library-only. Test userdata stays under repository dist.

## 2026-10-17 - data/import path verified
- Continued from orientation and inherited attachments.gd; section 5 takes precedence (Agent/external/Codex).
- Added native GDScript osu parsing, library-only unique song creation, guarded opening, deterministic 4K..10K drafts, live-constant chart_syntax, tool schemas, and 10000-operation atomic edits. Original Python fixture generator is test-only.
- Verified `python tools/verify_agent_io.py`: 4K/7K metadata/timing/SV, holds and <80ms tap fallback, <=1ms note times, one undo, no orphans, no index write, unsaved discard refusal, attachment copy/hash, safe ZIP listing/images, traversal and bomb rejection, paging and syntax sections all PASS.
- Fixed inherited static DirAccess.is_link misuse after actual compilation. All subsequent runs use the runner's repository-local userdata, Dummy audio and headless/offscreen flags.
- Core sync verified 237 runtime files; no game/judgement or existing song changes. Next: panel/backends and real HTTP/session/token/preview verification.

## 2026-10-17 - real MCP workflow and security verified
- Added independent MCP sessions, strict loopback Origin validation, optional Bearer token, regeneration, persisted fixed-port selection with netsh excluded-range detection/OS-port fallback, bounded activity log, and external-client burst undo labels.
- Verified `charter_agent_http` over actual HTTP: fixture parse -> unique create -> open -> draft -> two sweeps -> camera move -> analysis -> autoplay = 1010000, 30/30 PERFECT, no nonperfect notes. Native MCP image transport works.
- Verified real HTTP missing/wrong/old tokens rejected, valid bearer accepted, token-off accepted, spoofed Origin refused, distinct client sessions, ok/error activity, starter attachment ids/names, save/commit opt-in refusal. No authenticated model execution was needed.
- Agent/external page, shared attachment UI and asynchronous copies, optional Claude/Codex status probing and Codex read-only arguments implemented; continuing panel tests, visual previews, limits/error matrix and full regressions.

## 2026-10-17 - UI, limits and review remediation verified
- Verified original-window files_dropped path with two asynchronous copied attachments, three osu requests, no-CLI external fallback, real endpoint/config, all token-bearing snippets, backend availability/default and remembered Codex choice, shared attachment IDs across backends, and GUI-confirmed single-use discard.
- Rendered and personally inspected external Agent at 1600x900 and 1920x1080 plus the real preview-frame PNG in charter/shots/agent-io. Corrected the oversized wrapped port row and glyph encoding; connection settings collapse while URL/snippets/starter/chips remain readable. Headless preview returns an explicit unavailable error; offscreen graphics HTTP preview is non-black and <=1280px.
- Expanded data matrix PASS: 4K through 10K coverage, explicit key/track groups, malformed/unsupported/missing inputs, mapping atomicity, no populated-song overwrite, loose-osu audio attachment requirement, 300MB/20-file limits, manifest restore/removal/deletion. 3000 edit operations completed atomically in 438ms on a worker-compatible path; failed large batch rolled back.
- Cohesive review remediation: target/revision-bound GUI discard, backend session separation, snapshot attachment-copy state, integer-safe PNG dimensions, bounded clients/workers/activity, background song_create, PID Stop cancellation epoch. Verified real HTTP Stop rejects pending worker adoption without changing revision.
- Updated Chinese README and test/sync entry points. Full existing game + charter suite running; next is final verification/integrity handoff. CLI argument construction is tested without executing an authenticated model turn.

## 2026-10-17 - final targeted verification and preservation
- Latest Agent visual run PASS including live activity text, UI Undo restoring revision, backend availability/preference fixtures, same attachments across backends, GUI-confirmed exact-song discard, and non-black HTTP preview. Inspected both requested screenshot sizes. Plugin workshop visual checks PASS (45 checks), including external starter carrying its unsent plugin request; no login/model call.
- Added chart_syntax_reference.md to export include_filter; sync_core --check verifies it against docs/CHART_SYNTAX.md. Generated runtime/document copies remain ignored; no manual runtime copy edits.
- SHA-256 receipt dist/agent-io/integrity.json compares all tracked song chart/index/audio files directly with HEAD and confirms identical. No tracked game diff. Branch remains charter/agent-io, no commit/push.
- Full regression command is still running. Engine certificate / graphics shutdown resource diagnostics are retained in logs; assertion passes do not claim their remediation. Next: record complete full-suite results and final task status.

## 2026-10-17 - concurrent import boundary verified
- Final real-HTTP checks also verify two simultaneous song_create calls reserve distinct directories atomically, pending edits cannot adopt into a different song with the same content revision, and Stop prevents adoption. These cover the multi-client interaction introduced by section 5.
- Full game run has reached plugin tests; observed game-23-plugin_demo_app_test failure is exactly `create isolated symlink fixture`, matching the owner-described Windows permission limitation. Other completed game suites pass.
- Restored six pre-existing plugin screenshots regenerated by their visual test; only new shots/agent-io deliverables are retained. Plugin visual assertions passed (45), including the renamed Agent entry and copied plugin request.

## 2026-10-17 - all-note timing verification
- Final data tests now compare every 4K and 7K fixture note against parsed source: column/key mapping, chart time and retained hold duration all within 1 ms; no orphans. Both pass. Latest 3000-op atomic check 576ms under concurrent regression load (earlier 438ms).
- Latest targeted data, real HTTP and external visual assertions pass. Default/preference test state is explicitly scoped so repeated visual runs preserve prior preference and still verify first-available selection.
- Full regression has passed through game-29-scroll_projection_recovery_test; known game-23 symlink permission fixture remains the only failure observed so far. Remaining suites still running; no premature DONE marker.

## 2026-10-17 - final full regression / handoff verified
- `python tools/run_tests.py` completed: 45 suites total, 43 pass. All 11 charter suites pass (9 existing plus charter_agent_io and charter_agent_http). Game: 32/34 pass; only game-23-plugin_demo_app_test and game-33-song_plugin_session_test fail on Windows symlink fixture creation, exactly the two known environment limitations. No new failure in the full suite.
- Latest targeted Agent data/import, real HTTP workflow/security/concurrency/Stop/document identity, offscreen external Agent UI/preview and plugin visual assertions pass. Final screenshot inspection caught a stale selector label in the direct callback test path; synchronised the selected index and reran the visual suite successfully. Graphics runs retain Godot shutdown resource diagnostics and the certificate-store diagnostic; these are recorded, not claimed fixed.
- `dist/agent-io/verification.json` records full suite failures/diagnostics, targeted assertion counts and screenshot SHA-256 hashes. `integrity.json` refreshed AFTER the full run: all 21 tracked chart/index/audio files match HEAD byte-for-byte, no tracked game diff, root HEAD unchanged. No owned Godot process remains.
- Chinese README, export syntax reference inclusion, native fixture generator and test entry points complete. Images: charter/shots/agent-io/external-agent-1600x900.png, external-agent-1920x1080.png, preview-frame.png (personally inspected). Unrelated compose files and six pre-existing plugin screenshots preserved.
- CLI discovery/status and Codex argument/stream construction are checked; no authenticated Claude/Codex model turn was executed (acceptance uses scripted MCP and unit checks without login). Editor runtime is native GDScript; Python is test/setup tooling only.
- Branch charter/agent-io; no repository commit or push. Scope complete; the two known environment failures and retained engine diagnostics remain explicit.

AGENT-IO DONE


## Layout stability

- 2026-10-17: Read TASK_LAYOUT_STABLE.md and confirmed branch charter/layout-stable. Unrelated untracked COMPOSE_TASK.md, COMPOSE_WORKLOG.md and tools/compose preserved; no commit/push.
- Focused orientation traced per-frame canonical bar.beat fractions into unbounded top-bar labels, plus content-driven dock/drawer minima, variable save state, validation badges and Agent header/chips.
- Implementation boundary: display-only grid clock, explicit label/option slots, pane geometry independent of content minima, bounded runtime readouts and regression coverage. document.gd canonical positions, game/judgement and songs remain untouched. Validation in progress.

- First full offscreen run PASS: 1600x900 and 1920x1080, each at default zoom and real Ctrl+ zoom (1.1). Each played for 20.50-20.52s; 234846 exact global-rect comparisons, zero geometry failures. Covered all grid divisions/off-grid seeks, selection, panes, every drawer tab, streaming, compare and script header. Canonical MCP position string preserved.
- Short-run remediation caught and corrected viewport overflow after zoom, script binding/title metric changes, and triplet whole-note fraction units. Fixed/max slots use mono/tabular figures, clipping/ellipsis and tooltips; dock widths and drawer heights come from remembered dimensions. Long conversation content stays inside scrolling areas; composer/auth/chips have bounded outer geometry.
- Inspected offscreen screenshots at both requested sizes and zoom. Final full charter+visual regression running. The UI harness now frees only its own detached fixture nodes at teardown, avoiding text-shape diagnostic count drift without changing the diagnostic classifier. Existing segment-popover parent/certificate diagnostics remain explicit.

- Final audit completed the tabular digit coverage in song versions/status, drawer summaries, inspector headings/typed values, enum readouts and compare counts. Clock reservation also covers centisecond carry into an extra minute digit (599.9999 -> 10:00.00), with a dedicated assertion. No document, timing or judgement semantics changed.
- Latest strict headless smoke PASS: both dimensions and Ctrl+ zoom, 50584 exact comparisons, zero failures. The standalone runner now shares the repository diagnostic classifier and records retained diagnostics separately; quick runs are explicitly marked as development-only and do not substitute for the full 20s tests.

- FINAL: `python tools/run_tests.py --suite charter --visual` PASS, all 14 suites (11 existing charter suites, new charter_layout, both existing visual suites), zero failed suites. Latest layout run: 234884 exact global-rect comparisons, zero failures; 1231/1231/1230/1230 continuous-play frames across the four configurations, each 20.50-20.516s. Dedicated centisecond minute-carry reservation assertion PASS. Additional strict headless/offscreen smoke paths PASS; quick timings are not counted toward 20s acceptance.
- New regression is registered in tools/run_tests.py (headless normally; offscreen graphics with --visual). Standalone: `python tools/verify_layout.py`; optional --headless and explicitly non-acceptance --quick. Every launch syncs core first and uses Dummy audio with repository-local userdata. Pane open/close and compare transitions deliberately get fresh baselines after settling; subsequent text/value updates must preserve every captured rectangle exactly.
- Final diff/whitespace and sync checks pass (237 SHA-256 verified runtime files). No diff under game/, songs/ or charter/document.gd. Restored the six pre-existing script visual screenshots regenerated by the suite. No dependency install, judgement/song changes, commit or push. Unrelated compose files remain preserved.
- Deliverables: charter/shots/layout-stability/{1600x900,1920x1080}-zoom{false,true}.png (four inspected stress-state screenshots); dist/layout-stability/verification.json records samples, all suite results, retained diagnostics, source hashes and screenshot hashes. Raw final logs: dist/test-results/charter-11-charter_layout.log and other charter suite logs.
- Remaining diagnostics: existing Windows certificate-store message, existing segment_popover reparent messages in charter_ui, and baseline graphics resource shutdown diagnostics in charter_plugins_visual. Diagnostic classifier unchanged; no new layout-suite diagnostics beyond the certificate message. These pre-existing diagnostics are not claimed fixed.
- Completed on charter/layout-stable, with no commit or push.

LAYOUT DONE
