extends "res://ui/stable_pane.gd"
## Bottom drawer for on-demand tools, like the terminal drawer of the Claude app: one tool at
## a time, opened from the status strip (or Alt+1..7), drag its top edge to resize; the size
## and the open tool are remembered. Tabs: camera, track, music, history, checks, json, versions.

signal closed
signal resized_to(height: float)

const U = preload("res://ui/ui_util.gd")
const W = preload("res://ui/widgets.gd")
const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Ops = preload("res://edit_ops.gd")
const Lanes = preload("res://ui/lanes.gd")
const Vocab = preload("res://vocabulary.gd")
const TABS := {
	"camera": ["镜头与判定线", "camera", "Alt+1"], "track": ["轨道属性", "sliders", "Alt+2"], "music": ["音乐", "wave", "Alt+3"],
	"history": ["历史", "history", "Alt+4"], "checks": ["检查", "warning", "Alt+5"], "json": ["JSON", "braces", "Alt+6"], "versions": ["写法与版本", "branch", "Alt+7"],
}

var app
var doc
var timeline
var tab := "camera"
var height := 270.0
var grip := Control.new()
var header := HBoxContainer.new()
var title := Label.new()
var subtitle := Label.new()
var tools := HBoxContainer.new()
var content := MarginContainer.new()
var camera_lanes = Lanes.new()
var track_lanes = Lanes.new()
var music := Control.new()
var history := ItemList.new()
var checks := ItemList.new()
var json_box := VBoxContainer.new()
var json_view := TextEdit.new()
var json_edit := false
var versions_box := VBoxContainer.new()
var compare_checks: Dictionary = {}
var camera_scroll := ScrollContainer.new()
var track_scroll := ScrollContainer.new()
var _check_rows: Array = []

func _ready() -> void:
	theme_type_variation = "Pane"
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); add_child(v)
	grip.custom_minimum_size = Vector2(0, 6); grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE; grip.tooltip_text = "拖动调整高度"
	grip.gui_input.connect(_grip_input); grip.draw.connect(func():
		grip.draw_line(Vector2(grip.size.x / 2.0 - 18, 2), Vector2(grip.size.x / 2.0 + 18, 2), Tokens.c("border_strong"), 3, true))
	v.add_child(grip)
	v.add_child(header)
	header.add_theme_constant_override("separation", 12)
	U.bounded_label(title, 144)
	title.theme_type_variation = "Heading"; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; header.add_child(title)
	subtitle.add_theme_font_override("font", Tokens.font("num")); subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.theme_type_variation = "Faint"; subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL; subtitle.clip_text = true
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; header.add_child(subtitle)
	header.add_child(tools)
	var close_b := W.IconButton.new("close", "收起（Ctrl+J）"); close_b.pressed.connect(func(): closed.emit()); header.add_child(close_b)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(content)
	for lanes in [camera_lanes, track_lanes]:
		lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lanes.seek.connect(func(t): app.seek(t))
	track_lanes.mode = "track"
	for pair in [[camera_scroll, camera_lanes], [track_scroll, track_lanes]]:
		pair[0].horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pair[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
		pair[0].add_child(pair[1])
	camera_lanes.picked.connect(func(): app.on_selection())
	music.draw.connect(_draw_music); music.gui_input.connect(_music_input); music.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.item_activated.connect(_history_jump); history.item_clicked.connect(func(i, _p, _b): _history_jump(i))
	checks.item_clicked.connect(func(i, _p, _b):
		if i < _check_rows.size(): app.seek(maxf(0.0, float(_check_rows[i]) - 0.5)))
	json_view.theme_type_variation = "Code"; json_view.editable = false; json_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	json_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	json_box.add_child(json_view)

func open(which: String) -> void:
	tab = which
	for c in content.get_children(): content.remove_child(c)
	for c in tools.get_children(): tools.remove_child(c); c.queue_free()
	var info: Array = TABS[which]
	title.text = info[0]
	match which:
		"camera": _open_camera()
		"track": _open_track()
		"music": subtitle.text = "波形、能量和段落。点击或拖动跳到那个位置"; content.add_child(music)
		"history": subtitle.text = "点击一行回到那一步"; content.add_child(history)
		"checks": content.add_child(checks)
		"json": _open_json()
		"versions": _open_versions()
	refresh()

func _scroll(child: Control) -> ScrollContainer:
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(child); content.add_child(sc)
	return sc

func _open_camera() -> void:
	subtitle.text = "双击添加关键帧，拖动改时间和数值，右键改缓动"
	var pick := MenuButton.new(); pick.text = "通道"; pick.flat = true
	var popup := pick.get_popup(); popup.hide_on_checkable_item_selection = false
	var keys: Array = Vocab.data().keys()
	for i in keys.size():
		popup.add_check_item(str(Vocab.data()[keys[i]].label) + "  " + keys[i], i); popup.set_item_checked(i, keys[i] in camera_lanes.channels)
	popup.id_pressed.connect(func(i):
		var key: String = keys[i]
		if key in camera_lanes.channels:
			if camera_lanes.channels.size() > 1: camera_lanes.channels.erase(key)
		else: camera_lanes.channels.append(key)
		popup.set_item_checked(i, key in camera_lanes.channels); camera_lanes.update_height(); camera_lanes.queue_redraw())
	tools.add_child(pick)
	var follow := W.IconButton.new("camera", "判定线随镜头倾斜（±2°）", "跟随倾斜"); follow.toggle_mode = true
	follow.button_pressed = doc.raw.get("meta", {}).get("line_follow_roll", false)
	follow.toggled.connect(func(on):
		var meta: Dictionary = doc.raw.get("meta", {}).duplicate(true); meta.line_follow_roll = on
		timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "判定线跟随镜头", "ops": [{"target": "meta", "value": meta}]})))
	tools.add_child(follow)
	camera_lanes.update_height(); content.add_child(camera_scroll)

func _open_track() -> void:
	subtitle.text = "所选轨道随时间的变化。拖动关键帧调整，双击添加"
	track_lanes.update_height(); content.add_child(track_scroll)

func _open_json() -> void:
	subtitle.text = "所选对象的原始数据（只读）"
	var edit_b := W.IconButton.new("braces", "高级：直接编辑 JSON 并应用", "编辑"); edit_b.toggle_mode = true; edit_b.button_pressed = json_edit
	edit_b.toggled.connect(func(on): json_edit = on; json_view.editable = on; refresh())
	tools.add_child(edit_b)
	if json_edit:
		var apply_b := Button.new(); apply_b.text = "应用"; apply_b.pressed.connect(_apply_json); tools.add_child(apply_b)
	content.add_child(json_box)

func _open_versions() -> void:
	subtitle.text = "每种写法是一条分支，保存版本即提交；勾选 2–4 个可以并排比较"
	content.add_child(versions_box)

func refresh() -> void:
	if doc == null or doc.raw.is_empty(): return
	camera_lanes.doc = doc; camera_lanes.timeline = timeline; track_lanes.doc = doc; track_lanes.timeline = timeline
	match tab:
		"camera":
			camera_lanes.cursor = timeline.cursor; camera_lanes.queue_redraw()
			if doc.raw.get("fx", []).is_empty(): subtitle.text = "谱面还没有镜头事件，现在是自动镜头。双击添加第一个关键帧，就改为手写镜头"
		"track":
			track_lanes.cursor = timeline.cursor; track_lanes.queue_redraw()
		"music": music.queue_redraw()
		"history": _fill_history()
		"checks": _fill_checks()
		"json": _fill_json()
		"versions": _fill_versions()

func tick() -> void:
	match tab:
		"camera": camera_lanes.cursor = timeline.cursor; camera_lanes.queue_redraw()
		"track": track_lanes.cursor = timeline.cursor; track_lanes.queue_redraw()
		"music": music.queue_redraw()

func _grip_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		height = clampf(height - e.relative.y, 140.0, 620.0); custom_minimum_size.y = height; resized_to.emit(height)

## ------------------------------------------------------------------ music
func _draw_music() -> void:
	var tk := Tokens.tokens()
	var end := maxf(1.0, doc.core.end_time); var w := music.size.x; var h := music.size.y
	var mid := h * 0.45
	var wave: Dictionary = doc.music.get("waveform", {})
	var peaks: Array = wave.get("peaks", [])
	for i in peaks.size():
		var x := (float(wave.get("audio_start_chart_seconds", 0)) + float(i) / maxi(1, peaks.size() - 1) * float(wave.get("audio_duration_seconds", end))) / end * w
		music.draw_line(Vector2(x, mid - float(peaks[i]) * h * 0.32), Vector2(x, mid + float(peaks[i]) * h * 0.32), Color(tk.text, 0.13), 1)
	var energy: Dictionary = doc.raw.get("meta", {}).get("breath", {})
	var values: Array = energy.get("energy", []); var pts := PackedVector2Array()
	for i in values.size(): pts.append(Vector2((float(energy.get("t0", 0)) + i * float(energy.get("dt", 1))) / end * w, h * 0.85 - float(values[i]) * h * 0.6))
	if pts.size() > 1: music.draw_polyline(pts, Color(tk.clay, 0.8), 1.5, true)
	for k in doc.raw.get("meta", {}).get("kiai", []):
		music.draw_rect(Rect2(float(k.t0) / end * w, 0, (float(k.t1) - float(k.t0)) / end * w, 4), Color(tk.clay, 0.6))
	var f := Tokens.font("sans")
	var last := ""
	var last_x := -999.0
	for s in doc.music.get("sections", []):
		var section := str(s.get("name", ""))
		if section == last: continue
		last = section
		var t: float = doc.seconds("%d.1" % int(s.get("bar", 0)))
		if not is_finite(t): continue
		var x := t / end * w
		music.draw_line(Vector2(x, 8), Vector2(x, h), Color(tk.text, 0.12), 1)
		if x - last_x > 64:
			music.draw_string(f, Vector2(x + 5, h - 8), section, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.muted); last_x = x
	var cx: float = timeline.cursor / end * w
	music.draw_line(Vector2(cx, 0), Vector2(cx, h), tk.clay, 2)

func _music_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		app.seek(clampf(e.position.x / maxf(1.0, music.size.x), 0, 1) * doc.core.end_time)

## ------------------------------------------------------------------ history
func _fill_history() -> void:
	history.clear()
	history.add_item("  打开谱面")
	for e in doc.undo_stack:
		history.add_item(("  ✦ " if e.get("author", "user") == "Claude" else "  ") + str(e.get("label", "编辑")))
	for i in range(doc.redo_stack.size() - 1, -1, -1):
		history.add_item("  " + str(doc.redo_stack[i].get("label", "编辑")) + "（已撤销）")
		history.set_item_custom_fg_color(history.item_count - 1, Tokens.c("faint"))
	history.select(doc.undo_stack.size())
	subtitle.text = "共 %d 步。点击一行回到那一步" % doc.undo_stack.size()

func _history_jump(i: int) -> void:
	var target := i
	while doc.undo_stack.size() > target:
		if doc.undo().has("error"): break
	while doc.undo_stack.size() < target and not doc.redo_stack.is_empty():
		if doc.redo().has("error"): break
	app.on_document_changed()

## ------------------------------------------------------------------ checks
func _fill_checks() -> void:
	checks.clear(); _check_rows = []
	var warnings: Array = doc.core.chart.get("warnings", [])
	var cov: Array = doc.coverage(doc.raw)
	for w in warnings:
		checks.add_item("  游戏校验：" + str(w)); var m := RegEx.create_from_string("t=([0-9.]+)").search(str(w))
		_check_rows.append(float(m.get_string(1)) if m else 0.0)
	for f in cov:
		checks.add_item("  音符 %d（%s）：%s" % [int(f.note), Ops.pretty(doc, float(f.t)), Ops.explain({"error": "track rule refused", "detail": {"reason": f.reason}})])
		_check_rows.append(float(f.t))
	for k in doc.ext.get("motions", {}):
		var found := false
		for n in doc.raw.notes:
			if Ops.motion_key(n) == k: found = true; break
		if not found: checks.add_item("  音符运动：找不到它对应的音符（" + k + "）"); _check_rows.append(0.0)
	for id in doc.ext.get("shapes", {}):
		checks.add_item("  轨道 %s：形状需要新轨道语法，游戏暂按近似外轮廓显示" % id); _check_rows.append(float(Ops.lifetimes(doc, int(id))[0][0]) if not Ops.lifetimes(doc, int(id)).is_empty() else 0.0)
	if checks.item_count == 0: checks.add_item("  没有问题"); _check_rows.append(timeline.cursor)
	subtitle.text = "%d 条。点击一条跳到它的位置" % (checks.item_count if _check_rows.size() and checks.get_item_text(0) != "  没有问题" else 0)

var _issue_rev := ""
var _issue_count := 0
func count_issues() -> int:
	if doc == null or doc.raw.is_empty(): return 0
	if _issue_rev != doc.revision():
		_issue_rev = doc.revision()
		_issue_count = doc.core.chart.get("warnings", []).size() + doc.ext.get("shapes", {}).size() + (doc._check_cov.size() if doc._check_rev == doc.revision() else doc.coverage(doc.raw, doc.core.chart).size())
	return _issue_count

## ------------------------------------------------------------------ json
func selection_json() -> String:
	var out := {}
	if not timeline.sel_nodes.is_empty() and not timeline.work.is_empty():
		var shapes := []
		for s in timeline.work.shapes: shapes.append(s.to_dict())
		out = {"track": timeline.work.id, "editor_shape": shapes}
	elif not doc.selection.get("notes", []).is_empty():
		var notes := []
		for i in doc.selection.notes: notes.append(doc.raw.notes[int(i)])
		out = {"notes": notes} if notes.size() > 1 else notes[0]
	elif not doc.selection.get("fx", []).is_empty():
		out = doc.raw.fx[int(doc.selection.fx[0])]
	elif not doc.selection.get("tracks", []).is_empty():
		out = {"lights": Ops.track_events(doc, int(doc.selection.tracks[0]))}
	else:
		out = {"bpm": doc.raw.get("bpm"), "offset": doc.raw.get("offset"), "timing": doc.raw.get("timing"), "meta": doc.raw.get("meta", {}).keys()}
	return JSON.stringify(out, "  ", false)

func _fill_json() -> void:
	if not json_edit or not json_view.has_focus(): json_view.text = selection_json()

func _apply_json() -> void:
	var value = JSON.parse_string(json_view.text)
	if not value is Dictionary: timeline.say("不是有效的 JSON 对象"); return
	var ops := []
	if not doc.selection.get("notes", []).is_empty() and doc.selection.notes.size() == 1:
		ops = [{"target": "notes", "op": "update", "index": int(doc.selection.notes[0]), "value": value}]
	elif not doc.selection.get("fx", []).is_empty():
		ops = [{"target": "fx", "op": "update", "index": int(doc.selection.fx[0]), "value": value}]
	else:
		timeline.say("高级编辑只支持单个音符或镜头事件"); return
	timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "JSON 编辑", "ops": ops}))

## ------------------------------------------------------------------ versions
func _fill_versions() -> void:
	for c in versions_box.get_children(): versions_box.remove_child(c); c.queue_free()
	var store = doc.version_store()
	var info: Dictionary = store.list_versions()
	if not info.get("enabled", false):
		var row := HBoxContainer.new(); versions_box.add_child(row)
		var l := Label.new(); l.text = "这首歌还没有启用版本管理。启用后，每次保存版本都会留下一个可以比较、可以回退的版本。"; l.theme_type_variation = "Muted"; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new(); b.text = "启用版本管理"; b.theme_type_variation = "Primary"; b.pressed.connect(func(): timeline.report(store.initialize()); refresh()); row.add_child(b)
		return
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 24); cols.size_flags_vertical = Control.SIZE_EXPAND_FILL; versions_box.add_child(cols)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 300; cols.add_child(left)
	var hl := Label.new(); hl.text = "写法（当前：%s）" % str(info.get("current", "")); hl.theme_type_variation = "Section"; U.bounded_label(hl); left.add_child(hl)
	var refs := ["working"]
	for b in info.get("branches", []): refs.append(b)
	for ref in refs:
		var row := HBoxContainer.new(); left.add_child(row)
		var cb := CheckBox.new(); cb.text = "工作副本" if ref == "working" else ref; cb.clip_text = true; cb.custom_minimum_size.x = 260; cb.button_pressed = compare_checks.get(ref, false)
		cb.toggled.connect(func(on): compare_checks[ref] = on); row.add_child(cb)
		if ref != "working" and ref != info.get("current", ""):
			var sw := W.IconButton.new("branch", "切换到这个写法", "切换"); sw.pressed.connect(func(): timeline.report(store.branch_switch(ref)); app.on_document_changed()); row.add_child(sw)
	var actions := HBoxContainer.new(); left.add_child(actions)
	var cmp := Button.new(); cmp.text = "并排比较"; cmp.pressed.connect(_compare); actions.add_child(cmp)
	var overlay := W.IconButton.new("copy", "叠加显示两个版本", "叠加"); overlay.toggle_mode = true; overlay.button_pressed = app.compare_view.overlay
	overlay.toggled.connect(func(on): app.compare_view.overlay = on; app.compare_view.queue_redraw()); actions.add_child(overlay)
	var branch_name := LineEdit.new(); branch_name.placeholder_text = "新写法名称"; left.add_child(branch_name)
	var nb := Button.new(); nb.text = "从当前创建写法"; nb.pressed.connect(func(): timeline.report(store.branch_create(branch_name.text)); refresh()); left.add_child(nb)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols.add_child(right)
	var hr := Label.new(); hr.text = "版本"; hr.theme_type_variation = "Section"; right.add_child(hr)
	var list := ItemList.new(); list.size_flags_vertical = Control.SIZE_EXPAND_FILL; list.custom_minimum_size.y = 90; right.add_child(list)
	for entry in info.get("commits", []):
		list.add_item("%s    %s：%s" % [str(entry.time).left(16), str(entry.author), str(entry.message)])
	var commit_row := HBoxContainer.new(); right.add_child(commit_row)
	var message := LineEdit.new(); message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var labels := []
	for entry in doc.undo_stack.slice(store.last_commit_size): labels.append(("Claude: " if entry.get("author", "") == "Claude" else "") + str(entry.label))
	message.text = "; ".join(labels).left(160) if not labels.is_empty() else "保存谱面版本"
	commit_row.add_child(message)
	var cb2 := Button.new(); cb2.text = "保存版本"; cb2.theme_type_variation = "Primary"
	cb2.pressed.connect(func(): timeline.report(store.commit(message.text, false)); refresh()); commit_row.add_child(cb2)
	var import_row := HBoxContainer.new(); right.add_child(import_row)
	for variant in app.song_dirs:
		var source: String = app.songs_root().path_join(variant).path_join("chart.json")
		if FileAccess.file_exists(source) and not source.get_base_dir() == doc.path.get_base_dir():
			var ib := W.IconButton.new("branch", "把这个文件夹作为一个写法导入（不删除源文件夹）", "导入 " + variant)
			ib.pressed.connect(func(): timeline.report(store.import_variant(source, variant)); refresh()); import_row.add_child(ib)

func _compare() -> void:
	var refs := []
	for ref in compare_checks:
		if compare_checks[ref]: refs.append(ref)
	if refs.size() < 2 or refs.size() > 4: timeline.say("请勾选 2–4 个版本"); return
	app.open_compare(refs)
