extends Control
## Vertical chart timeline: time runs up (later = higher), the play field runs left -> right
## (0..15 key units plus the spill zones). Direct manipulation:
##   notes   click / Shift add / Ctrl toggle, drag = move (time + key), Alt-drag = duplicate,
##           drag a hold's top end = length, Shift while dragging = free (no snap)
##   tracks  click the body = select; its outline shows nodes (real = squares, grid crossings =
##           small rings). Drag a node, an edge (widen / narrow) or the body; Alt toggles snap,
##           Shift constrains to one axis; Ctrl+click two nodes = segment popover; double-click an
##           edge inserts a node; marquee selects nodes of the selected track.
##   create  tap / hold tools place on the grid (ghost turns red with a reason when refused);
##           track tool drags a box -> rectangle / diamond / circle / star / heart
##   view    wheel = time, Ctrl+wheel = zoom at the cursor, Shift+wheel = one grid step,
##           middle-drag = pan, drag in the time gutters = scrub

signal selected
signal seek(t: float)
signal status(text: String)
signal nodes_changed
signal popover_requested(shape_index: int, a: int, b: int)

const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Ops = preload("res://edit_ops.gd")
const Shape = preload("res://track_shape.gd")
const Adapter = preload("res://track_adapter.gd")
const Motion = preload("res://note_motion.gd")
const GRIDS := [1, 2, 3, 4, 6, 8, 12, 16]
const L := 70.0     # bar.beat gutter
const R := 78.0     # m:ss gutter
const T := 32.0     # key-unit ruler
const B := 38.0     # home-row letters
const LO := SU.LIGHT_OVER

var doc
var cursor := 0.0
var pixels := 110.0
var grid := 16
var snap: int:
	get: return grid
	set(v): grid = v
var tool := "select"
var shape_kind := "rect"
var light := false
var hidden_tracks: Dictionary = {}
var locked_tracks: Dictionary = {}
var solo := -1
var show_windows := false
var show_fingering := false
var changed_notes: Array = []
var changed_tracks: Array = []

var cache_rev := ""
var _entries: Dictionary = {}      # id -> {sig, light, entry}: unchanged tracks are not rebuilt
var _entries_path := ""
var notes_view: Array = []
var tracks_view: Dictionary = {}
var work: Dictionary = {}          # {id, shapes, sig}
var sel_nodes: Array = []          # [{s, n}] in work.shapes
var hover: Dictionary = {}
var drag: Dictionary = {}
var ghost: Dictionary = {}
var bubble: Dictionary = {}
var clipboard: Array = []
var menu := PopupMenu.new()
var motion_menu := PopupMenu.new()
var _menu_ctx: Dictionary = {}
var _work_screen: Array = []       # per shape: {pts, owner}
var mouse := Vector2(-1, -1)

func _ready() -> void:
	clip_contents = true; focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	add_child(menu); menu.id_pressed.connect(_menu_action)
	motion_menu.name = "motion"; menu.add_child(motion_menu); motion_menu.id_pressed.connect(func(id): _menu_action(1000 + id))
	mouse_exited.connect(func(): mouse = Vector2(-1, -1); hover = {}; ghost = {}; queue_redraw())

## ------------------------------------------------------------------ geometry
func field_w() -> float: return maxf(10.0, size.x - L - R)
func x_of(u: float) -> float: return L + (u + LO) / (1.0 + 2.0 * LO) * field_w()
func u_of(px: float) -> float: return (px - L) / field_w() * (1.0 + 2.0 * LO) - LO
func judge_y() -> float: return size.y - B - (size.y - T - B) * 0.16
func y_of(t: float) -> float: return judge_y() - (t - cursor) * pixels
func time_of(y: float) -> float: return cursor + (judge_y() - y) / pixels
func t_lo() -> float: return time_of(size.y - B)
func t_hi() -> float: return time_of(T)
func xt_to_screen() -> Transform2D:
	var sx := field_w() / (1.0 + 2.0 * LO)
	return Transform2D(Vector2(sx, 0), Vector2(0, -pixels), Vector2(L + LO * sx, judge_y() + cursor * pixels))
func screen(p: Vector2) -> Vector2: return Vector2(x_of(p.x), y_of(p.y))
func step_seconds(t: float) -> float: return doc.position(t).beat_seconds * 4.0 / grid

func snap_time(t: float) -> float:
	var p = doc.position(t)
	var base: float = doc.seconds("%d.1" % int(p.bar))
	if is_nan(base): return t
	return maxf(0.0, base + snappedf(t - base, p.beat_seconds * 4.0 / grid))

func snap_u(u: float) -> float: return snappedf(u, 1.0 / 60.0)

func cycle_grid(direction: int) -> void:
	grid = GRIDS[clampi(GRIDS.find(grid) + direction, 0, GRIDS.size() - 1)]
	status.emit("网格：每小节 %d 格" % grid); queue_redraw()

## ------------------------------------------------------------------ caches
func refresh(force := false) -> void:
	if doc == null or doc.raw.is_empty(): return
	if not force and cache_rev == doc.revision(): return
	cache_rev = doc.revision()
	notes_view = []
	for n in doc.core.notes:
		var i := int(n.get("raw_id", n.id))
		var st = doc.state_at(doc.core.tl.get(int(n.light), []), float(n.t))
		var x: float = st.x + (float(n.u) - 0.5) * st.w if st.alive else 0.5
		notes_view.append({"i": i, "t": float(n.t), "dur": float(n.dur), "x": x, "k": int(n.k), "kind": n.kind, "ex": n.ex, "big": n.big,
			"light": int(n.light), "key": str(n.get("key_code", "")), "ticks": n.get("ticks", []), "w_e": float(n.get("w_e", 0.0)), "w_l": float(n.get("w_l", 0.0))})
	if _entries_path != doc.path: _entries = {}; _entries_path = doc.path
	var counts := Ops.roles(doc)
	var by_id := {}
	for e in doc.raw.lights:
		var key := int(e.get("id", -1))
		if not by_id.has(key): by_id[key] = []
		by_id[key].append(e)
	tracks_view = {}
	for id in doc.core.tl:
		var count := int(counts.get(id, 0))
		if not work.is_empty() and work.id == id:
			tracks_view[id] = _track_entry(id, work.shapes, count); continue
		var events: Array = by_id.get(id, [])
		var sig := Adapter.signature(events)
		var key := sig + str(hash(JSON.stringify(doc.ext.get("shapes", {}).get(str(id), {})))) + str(doc.shape_memo.has(sig))
		var cached: Dictionary = _entries.get(id, {})
		if cached.get("sig", "") == key and cached.get("light", -1) == int(light) and int(cached.entry.count) == count:
			tracks_view[id] = cached.entry; continue
		var entry := _track_entry(id, Ops.shapes_for(doc, id, events, sig), count)
		_entries[id] = {"sig": key, "light": int(light), "entry": entry}
		tracks_view[id] = entry
	if not work.is_empty():
		var sig := Adapter.signature(Ops.track_events(doc, work.id))
		if sig != work.sig or not doc.core.tl.has(work.id): select_track(work.id if doc.core.tl.has(work.id) else -1, true)
	queue_redraw()

func _track_entry(id: int, shapes: Array, count: int) -> Dictionary:
	var polys := []; var transparent := true; var visible_any := false; var exact := true; var cue := false
	for s in shapes:
		var poly: Dictionary = s.polygon()
		var pts: PackedVector2Array = poly.points
		var tris := Geometry2D.triangulate_polygon(pts)
		var cols := PackedColorArray()
		for p in pts:
			var pr: Dictionary = s.prop_at(p.y)
			var a: float = pr.a if pr.a >= 0 else 1.0
			cols.append(Color(Tokens.tint(int(pr.tint), light), a))
			if a > 0.001: transparent = false; visible_any = true
		var r: Array = s.t_range()
		polys.append({"pts": pts, "owner": poly.owner, "tris": tris, "cols": cols, "lo": r[0], "hi": r[1]})
		if not Adapter.is_representable(s).ok: exact = false
		for k in s.pins:
			if s.pins[k].get("auto", true) == false: cue = true
	var role := "carrier" if count > 0 else ("cue" if cue else ("performer" if visible_any else "background"))
	return {"id": id, "shapes": shapes, "polys": polys, "role": role, "transparent": transparent, "count": count, "exact": exact}

## ------------------------------------------------------------------ selection helpers
func selected_track() -> int:
	return int(doc.selection.tracks[0]) if not doc.selection.get("tracks", []).is_empty() else -1

func select_track(id: int, keep_nodes := false) -> void:
	if id < 0:
		work = {}; sel_nodes = []
	else:
		work = {"id": id, "shapes": Ops.shapes_for(doc, id), "sig": Adapter.signature(Ops.track_events(doc, id))}
		if not keep_nodes: sel_nodes = []
		var valid := []
		for sn in sel_nodes:
			if sn.s < work.shapes.size() and sn.n < work.shapes[sn.s].size(): valid.append(sn)
		sel_nodes = valid
		if tracks_view.has(id): tracks_view[id] = _track_entry(id, work.shapes, int(tracks_view[id].count))
	nodes_changed.emit(); queue_redraw()

func set_selection(notes: Array, tracks: Array, emit := true) -> void:
	doc.selection.notes = notes; doc.selection.tracks = tracks; doc.selection.fx = []; doc.selection["track_events"] = []
	if tracks.size() == 1 and notes.is_empty():
		if work.is_empty() or work.id != int(tracks[0]): select_track(int(tracks[0]))
	elif not notes.is_empty() and not work.is_empty():
		work = {}; sel_nodes = []; nodes_changed.emit()
	elif tracks.is_empty():
		work = {}; sel_nodes = []; nodes_changed.emit()
	if emit: selected.emit()
	queue_redraw()

func say(text: String, bad := true, at := Vector2(-1, -1)) -> void:
	var p := at if at.x >= 0 else (mouse if mouse.x >= 0 else size / 2.0)
	bubble = {"text": text, "pos": p, "until": Time.get_ticks_msec() + 2600, "bad": bad}
	status.emit(text); queue_redraw()

func report(result: Dictionary, success := "") -> bool:
	if result.has("error"):
		say(Ops.explain(result)); return false
	if not success.is_empty(): status.emit(success)
	return true

## ------------------------------------------------------------------ hit testing
func note_rect(nv: Dictionary) -> Rect2:
	var w := 34.0 if nv.big else 22.0
	return Rect2(x_of(nv.x) - w / 2.0, y_of(nv.t) - 4.5, w, 9)

func hit(p: Vector2) -> Dictionary:
	if p.x < L or p.x > size.x - R: return {"kind": "gutter"}
	if p.y < T - 4 or p.y > size.y - B + 4: return {"kind": "ruler"}
	var lo := time_of(p.y + 12); var hi := time_of(p.y - 12)
	# nodes and handles of the selected track first: they sit on top
	if not work.is_empty():
		for sn in sel_nodes:
			var s = work.shapes[sn.s]
			for seg_i in [sn.n, s.prev(sn.n)]:
				if s.segs[seg_i].ease != "bezier": continue
				for which in ["h1", "h2"]:
					if screen(s.segs[seg_i][which]).distance_to(p) < 7: return {"kind": "handle", "s": sn.s, "seg": seg_i, "which": which}
		for si in work.shapes.size():
			var s = work.shapes[si]
			for ni in s.size():
				if screen(s.pos(ni)).distance_to(p) < 7: return {"kind": "node", "s": si, "n": ni}
		for v in virtual_nodes():
			if screen(v.p).distance_to(p) < 6: return {"kind": "vnode", "s": v.s, "seg": v.seg, "u": v.u, "t": v.t}
	for nv in selected_notes_view():
		var m: Dictionary = doc.ext.motions.get(Ops.motion_key(doc.raw.notes[nv.i]), {})
		if m.is_empty(): continue
		var start_x := motion_start_x(nv, m)
		if not is_nan(start_x) and Vector2(x_of(start_x), y_of(nv.t + Motion.FALL)).distance_to(p) < 8: return {"kind": "motion", "i": nv.i}
	for nv in notes_view:
		if nv.t + nv.dur < lo - 1 or nv.t > hi + 1 or not note_visible(nv): continue
		if nv.kind == "hold" and absf(y_of(nv.t + nv.dur) - p.y) < 6 and absf(x_of(nv.x) - p.x) < 12: return {"kind": "tail", "i": nv.i}
		if note_rect(nv).grow(4).has_point(p): return {"kind": "note", "i": nv.i}
	if not work.is_empty():
		_ensure_work_screen()
		var best := {}; var bd := 6.0
		for si in _work_screen.size():
			var pts: PackedVector2Array = _work_screen[si].pts
			for k in pts.size():
				var a := pts[k]; var b := pts[(k + 1) % pts.size()]
				var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
				if d < bd: bd = d; best = {"kind": "edge", "s": si, "seg": int(_work_screen[si].owner[k])}
		if not best.is_empty(): return best
	var xt := Vector2(u_of(p.x), time_of(p.y))
	var found := -1; var area := INF
	for id in tracks_view:
		if not track_visible(id): continue
		var tv: Dictionary = tracks_view[id]
		for pi in tv.polys.size():
			var poly: Dictionary = tv.polys[pi]
			if xt.y < poly.lo or xt.y > poly.hi: continue
			if Geometry2D.is_point_in_polygon(xt, poly.pts):
				var env: Vector2 = tv.shapes[pi].envelope(xt.y, poly.pts)
				var w := env.y - env.x
				if work.get("id", -99) == id: w *= 0.25
				if tv.count > 0: w *= 0.6
				if w < area: area = w; found = id
	if found >= 0: return {"kind": "body", "id": found}
	return {"kind": "empty"}

func note_visible(nv: Dictionary) -> bool:
	return not hidden_tracks.get(nv.light, false) and (solo < 0 or nv.light == solo)

func track_visible(id: int) -> bool:
	return not hidden_tracks.get(id, false) and (solo < 0 or id == solo)

func selected_notes_view() -> Array:
	var out := []
	var want := {}
	for i in doc.selection.get("notes", []): want[int(i)] = true
	for nv in notes_view:
		if want.has(nv.i): out.append(nv)
	return out

## Grid crossings of the selected outline: draggable "virtual" nodes.
func virtual_nodes() -> Array:
	var out := []
	if work.is_empty() or doc == null: return out
	var lo := t_lo(); var hi := t_hi()
	var spacing := step_seconds(cursor) * pixels
	if spacing < 9: return out
	var times := []
	for g in doc.grid(maxf(0, lo), hi, grid): times.append(float(g.seconds))
	for si in work.shapes.size():
		var s = work.shapes[si]
		for seg in s.size():
			var a: Dictionary = s.nodes[seg]; var b: Dictionary = s.nodes[s.next(seg)]
			var tmin := minf(a.t, b.t); var tmax := maxf(a.t, b.t)
			if tmax < lo or tmin > hi or tmax - tmin < 1e-6: continue
			for g in times:
				if g <= tmin + 1e-4 or g >= tmax - 1e-4: continue
				for sp in seg_params(s, seg, g):
					var e: Array = s.seg_eval(seg, sp)
					out.append({"s": si, "seg": seg, "u": sp, "t": g, "p": Vector2(e[0], g)})
	return out

func seg_params(s, seg: int, t: float) -> Array:
	var a: Dictionary = s.nodes[seg]; var b: Dictionary = s.nodes[s.next(seg)]
	if s.segs[seg].ease != "bezier": return [(t - a.t) / (b.t - a.t)]
	var out := []
	var prev_s := 0.0; var prev_t: float = a.t
	for k in range(1, 33):
		var sp := k / 32.0; var pt: float = s.seg_point(seg, sp).y
		if (prev_t - t) * (pt - t) <= 0 and absf(pt - prev_t) > 1e-9:
			var lo_s := prev_s; var hi_s := sp
			for _it in 20:
				var mid := (lo_s + hi_s) / 2.0
				if (s.seg_point(seg, mid).y - t) * (prev_t - t) > 0: lo_s = mid
				else: hi_s = mid
			out.append((lo_s + hi_s) / 2.0)
		prev_s = sp; prev_t = pt
	return out

func motion_start_x(nv: Dictionary, m: Dictionary) -> float:
	var t = Motion.find(str(m.get("type", "")))
	if t == null: return NAN
	var p: Dictionary = Motion.defaults(t.ID); p.merge(m.get("params", {}), true)
	var off: float = t.start(p, {"doc": doc, "note": doc.raw.notes[nv.i], "land_x": nv.x})
	return NAN if is_nan(off) else nv.x + off

## ------------------------------------------------------------------ input
func _gui_input(e: InputEvent) -> void:
	if doc == null or doc.raw.is_empty(): return
	if e is InputEventMouseMotion:
		mouse = e.position
		if not drag.is_empty(): _drag_motion(e)
		else:
			hover = hit(e.position); _update_ghost(e)
			mouse_default_cursor_shape = _cursor_for(hover)
		queue_redraw(); return
	if e is InputEventMouseButton:
		mouse = e.position
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
			var d := 1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if e.ctrl_pressed:
				var anchor := time_of(e.position.y)
				pixels = clampf(pixels * pow(1.15, d), 18.0, 900.0)
				seek.emit(maxf(0.0, anchor - (judge_y() - e.position.y) / pixels))
			elif e.shift_pressed: seek.emit(maxf(0.0, snap_time(cursor + d * step_seconds(cursor))))
			else: seek.emit(maxf(0.0, cursor + d * 90.0 / pixels))
			accept_event(); return
		if e.button_index == MOUSE_BUTTON_MIDDLE:
			drag = {"mode": "pan", "y": e.position.y, "cursor": cursor} if e.pressed else {}
			accept_event(); return
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			grab_focus(); _context_menu(e.position); accept_event(); return
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed: grab_focus(); _press(e)
			else: _release(e)
			accept_event(); queue_redraw(); return
	if e is InputEventKey and e.pressed and has_focus():
		if _key(e): accept_event()

func _cursor_for(h: Dictionary) -> int:
	match h.get("kind", ""):
		"gutter": return Control.CURSOR_VSIZE
		"node", "vnode", "handle", "motion": return Control.CURSOR_DRAG
		"edge": return Control.CURSOR_HSIZE
		"tail": return Control.CURSOR_VSIZE
		"note": return Control.CURSOR_POINTING_HAND
		"body": return Control.CURSOR_MOVE if h.id == work.get("id", -99) else Control.CURSOR_POINTING_HAND
	return Control.CURSOR_CROSS if tool != "select" else Control.CURSOR_ARROW

func _update_ghost(e: InputEvent) -> void:
	ghost = {}
	if not tool in ["tap", "hold"] or hover.get("kind", "") in ["note", "tail", "gutter", "ruler", "node", "handle"]: return
	var t := time_of(e.position.y)
	if not (e is InputEventWithModifiers and e.shift_pressed): t = snap_time(t)
	var k := Ops.key_of(u_of(e.position.x))
	var dur := step_seconds(t) * 4.0 if tool == "hold" else 0.0
	var place := Ops.placement(doc, t, k, dur, selected_track(), locked_tracks, hidden_tracks)
	ghost = {"t": t, "k": k, "dur": dur, "ok": place.ok, "reason": place.get("reason", ""), "light": place.get("light", -1)}

func _press(e: InputEventMouseButton) -> void:
	var h := hit(e.position)
	var t := time_of(e.position.y); var u := u_of(e.position.x)
	if h.kind == "gutter" or h.kind == "ruler":
		if h.kind == "gutter": drag = {"mode": "scrub"}; seek.emit(maxf(0.0, snap_time(t)))
		return
	if e.double_click:
		if h.kind == "edge": _insert_node_at(h.s, h.seg, t); return
		if h.kind in ["empty", "body"] and tool == "select":
			_place(snap_time(t), Ops.key_of(u), 0.0); return
	match h.kind:
		"handle":
			drag = {"mode": "handle", "s": h.s, "seg": h.seg, "which": h.which, "orig": _clone_work()}; return
		"node":
			var key := {"s": h.s, "n": h.n}
			if e.ctrl_pressed or e.shift_pressed:
				if _has_node(key): sel_nodes = sel_nodes.filter(func(x): return not (x.s == key.s and x.n == key.n))
				else: sel_nodes.append(key)
				nodes_changed.emit()
				if e.ctrl_pressed and sel_nodes.size() == 2 and sel_nodes[0].s == sel_nodes[1].s: popover_requested.emit(sel_nodes[0].s, sel_nodes[0].n, sel_nodes[1].n)
				return
			if not _has_node(key): sel_nodes = [key]; nodes_changed.emit()
			_start_node_drag(e.position, key); return
		"vnode":
			var at: int = _insert_virtual(h)
			if at < 0: return
			sel_nodes = [{"s": h.s, "n": at}]; nodes_changed.emit()
			_start_node_drag(e.position, sel_nodes[0]); return
		"motion":
			drag = {"mode": "motion", "i": h.i, "start": e.position, "orig": doc.ext.motions.duplicate(true)}; return
		"tail":
			_select_note(h.i, e)
			drag = {"mode": "tail", "i": h.i, "start": e.position}; return
		"note":
			_select_note(h.i, e)
			if h.i in doc.selection.notes:
				var n: Dictionary = doc.raw.notes[h.i]
				drag = {"mode": "notes", "anchor": h.i, "t0": float(n.t), "k0": Ops.note_key(n) if Ops.note_key(n) >= 0 else Ops.key_of(_note_x(h.i)),
					"start": e.position, "dup": e.alt_pressed, "ids": doc.selection.notes.duplicate(), "preview": []}
			return
	match tool:
		"tap":
			_place_ghost(); return
		"hold":
			var t0 := snap_time(t); var k := Ops.key_of(u)
			drag = {"mode": "hold_create", "t0": t0, "k": k, "t1": t0 + step_seconds(t0)}; return
		"track":
			var t0s := snap_time(t)
			drag = {"mode": "create", "a": Vector2(snap_u(u), t0s), "b": Vector2(snap_u(u), t0s)}; return
	if h.kind == "edge":
		_start_edge_drag(e.position, h); return
	if h.kind == "body":
		if work.get("id", -99) == h.id:
			drag = {"mode": "body", "start": e.position, "s": _shape_at(h.id, t), "orig": _clone_work(), "t0": t}
			return
		set_selection([], [h.id]); return
	drag = {"mode": "marquee", "a": e.position, "b": e.position, "shift": e.shift_pressed, "ctrl": e.ctrl_pressed}

func _release(e: InputEventMouseButton) -> void:
	var d := drag; drag = {}
	match d.get("mode", ""):
		"marquee": _finish_marquee(d, e)
		"notes": _finish_note_drag(d)
		"tail": _finish_tail(d, e)
		"node", "edge", "body", "handle":
			if d.get("moved", false): _commit_work({"node": "移动节点", "edge": "调整轨道宽度", "body": "移动轨道", "handle": "调整曲线"}[d.mode])
		"create": _finish_create(d)
		"hold_create":
			_place(d.t0, d.k, maxf(step_seconds(d.t0), d.t1 - d.t0))
		"motion":
			if d.get("moved", false):
				var final: Dictionary = doc.ext.motions
				doc.ext.motions = d.orig
				var ext: Dictionary = doc.ext.duplicate(true); ext.motions = final
				report(doc.edit({"expected_revision": doc.revision(), "label": "调整音符运动起点", "ops": [], "ext": ext}))
	hover = hit(e.position); queue_redraw()

func _drag_motion(e: InputEventMouseMotion) -> void:
	var t := time_of(e.position.y); var u := u_of(e.position.x)
	match drag.mode:
		"pan": seek.emit(maxf(0.0, drag.cursor + (e.position.y - drag.y) / pixels))
		"scrub": seek.emit(maxf(0.0, snap_time(t) if not e.shift_pressed else t))
		"marquee": drag.b = e.position
		"create":
			drag.b = Vector2(snap_u(u) if not e.alt_pressed else u, snap_time(t) if not e.alt_pressed else t)
			if e.shift_pressed:   # constrain to a square-ish box in screen space
				var dx := absf(x_of(drag.b.x) - x_of(drag.a.x)); var sign_t := signf(drag.b.y - drag.a.y)
				drag.b.y = drag.a.y + sign_t * dx / pixels
		"hold_create": drag.t1 = maxf(drag.t0 + step_seconds(drag.t0), snap_time(t))
		"tail":
			var n: Dictionary = doc.raw.notes[drag.i]
			var end := t if e.shift_pressed else snap_time(t)
			drag["dur"] = maxf(step_seconds(float(n.t)), end - float(n.t))
			var place := Ops.placement(doc, float(n.t), Ops.note_key(n), drag.dur, int(n.light), locked_tracks)
			drag["ok"] = place.ok; drag["reason"] = place.get("reason", "")
		"notes":
			var target: float = time_of(e.position.y) + (drag.t0 - time_of(drag.start.y))
			if not e.shift_pressed: target = snap_time(target)
			var dt: float = target - drag.t0
			var dk: int = Ops.key_of(u_of(e.position.x)) - Ops.key_of(u_of(drag.start.x))
			drag["moved"] = e.position.distance_to(drag.start) > 4
			var res := Ops.move_notes(doc, drag.ids, dt, dk, drag.dup, locked_tracks)
			drag["dt"] = dt; drag["dk"] = dk; drag["preview"] = res.preview; drag["ok"] = res.ok; drag["reason"] = res.reason
		"node", "edge", "body": _drag_shape(e)
		"handle":
			_restore_work(drag.orig)
			var s = work.shapes[drag.s]
			var p := Vector2(u if e.alt_pressed else snap_u(u), t)
			s.segs[drag.seg][drag.which] = p
			var node_i: int = drag.seg if drag.which == "h1" else s.next(drag.seg)
			if s.nodes[node_i].smooth:
				var other_seg: int = s.prev(drag.seg) if drag.which == "h1" else s.next(drag.seg)
				var other_which := "h2" if drag.which == "h1" else "h1"
				if s.segs[other_seg].ease == "bezier":
					var c: Vector2 = s.pos(node_i)
					var arm: float = (s.segs[other_seg][other_which] - c).length()
					s.segs[other_seg][other_which] = c - (p - c).normalized() * arm
			drag["moved"] = true; _refresh_work_entry()
		"motion":
			var nv := _view_of(drag.i)
			var m: Dictionary = drag.orig.get(Ops.motion_key(doc.raw.notes[drag.i]), {})
			var t0 = Motion.find(str(m.get("type", "")))
			if t0 == null: return
			var base := motion_start_x(nv, m)
			var delta := snap_u(u) - base
			var motions: Dictionary = drag.orig.duplicate(true)
			for i in doc.selection.notes:
				var key := Ops.motion_key(doc.raw.notes[int(i)])
				if not motions.has(key): continue
				var mt = Motion.find(str(motions[key].type))
				if mt == null: continue
				var p: Dictionary = Motion.defaults(mt.ID); p.merge(motions[key].get("params", {}), true)
				var nvi := _view_of(int(i))
				var cur: float = mt.start(p, {"doc": doc, "note": doc.raw.notes[int(i)], "land_x": nvi.x})
				if is_nan(cur): continue
				motions[key].params = mt.with_start(p, cur + delta, {"doc": doc})
			doc.ext.motions = motions; drag["moved"] = true

## ------------------------------------------------------------------ notes
func _note_x(i: int) -> float:
	var nv := _view_of(i)
	return nv.get("x", 0.5)

func _view_of(i: int) -> Dictionary:
	for nv in notes_view:
		if nv.i == i: return nv
	return {}

func _select_note(i: int, e: InputEventMouseButton) -> void:
	var notes: Array = doc.selection.get("notes", []).duplicate()
	if e.ctrl_pressed:
		if i in notes: notes.erase(i)
		else: notes.append(i)
	elif e.shift_pressed:
		if not i in notes: notes.append(i)
	elif not i in notes: notes = [i]
	var tracks := []
	for j in notes:
		var id := int(doc.raw.notes[int(j)].light)
		if not id in tracks: tracks.append(id)
	set_selection(notes, tracks)

func _place_ghost() -> void:
	if ghost.is_empty(): return
	_place(ghost.t, ghost.k, ghost.dur if tool == "hold" else 0.0)

func _place(t: float, k: int, dur: float) -> void:
	var place := Ops.placement(doc, t, k, dur, selected_track(), locked_tracks, hidden_tracks)
	if not place.ok: say(place.reason); return
	var n := {"t": Adapter.num(t), "light": place.light, "u": place.u, "kind": "hold" if dur > 0 else "tap", "k": k}
	if dur > 0: n["dur"] = Adapter.num(dur)
	var result: Dictionary = doc.edit({"expected_revision": doc.revision(), "label": "放置长按" if dur > 0 else "放置音符", "ops": [{"target": "notes", "op": "add", "value": n}]})
	if report(result, "已在 %s 放一个 %s 键音符" % [doc.position(t).bar_beat, Ops.key_name(k)]):
		set_selection([doc.raw.notes.size() - 1], [int(place.light)])

func _finish_note_drag(d: Dictionary) -> void:
	if not d.get("moved", false) or (d.get("dt", 0.0) == 0.0 and d.get("dk", 0) == 0 and not d.dup): return
	if not d.get("ok", false): say(d.get("reason", "不能放在这里")); return
	var res := Ops.move_notes(doc, d.ids, d.dt, d.dk, d.dup, locked_tracks)
	var result: Dictionary = doc.edit({"expected_revision": doc.revision(), "label": "复制音符" if d.dup else "移动音符", "ops": res.ops, "ext": res.ext})
	if report(result) and d.dup:
		var start: int = doc.raw.notes.size() - d.ids.size()
		set_selection(range(start, doc.raw.notes.size()), doc.selection.tracks)

func _finish_tail(d: Dictionary, _e) -> void:
	if not d.has("dur"): return
	if not d.get("ok", true): say(d.reason); return
	var n: Dictionary = doc.raw.notes[d.i]
	report(doc.edit({"expected_revision": doc.revision(), "label": "长按长度", "ops": [{"target": "notes", "op": "update", "index": d.i, "value": {"kind": "hold", "dur": Adapter.num(d.dur)}}]}))

func _finish_marquee(d: Dictionary, e: InputEventMouseButton) -> void:
	var r := Rect2(d.a, Vector2.ZERO).expand(d.b)
	if r.size.length() < 4:
		if not d.shift and not d.ctrl:
			sel_nodes = []; set_selection([], [])
		return
	var t0 := time_of(r.end.y); var t1 := time_of(r.position.y)
	doc.selection.from = maxf(0.0, t0); doc.selection.to = t1
	if not work.is_empty():
		var picked := []
		for si in work.shapes.size():
			for ni in work.shapes[si].size():
				if r.has_point(screen(work.shapes[si].pos(ni))): picked.append({"s": si, "n": ni})
		if not picked.is_empty():
			if d.shift or d.ctrl:
				for p in picked:
					if not _has_node(p): sel_nodes.append(p)
			else: sel_nodes = picked
			nodes_changed.emit(); selected.emit(); return
	var notes: Array = doc.selection.notes.duplicate() if (d.shift or d.ctrl) else []
	for nv in notes_view:
		if note_visible(nv) and r.has_point(Vector2(x_of(nv.x), y_of(nv.t))):
			if d.ctrl and nv.i in notes: notes.erase(nv.i)
			elif not nv.i in notes: notes.append(nv.i)
	var fx := []
	for i in doc.raw.get("fx", []).size():
		if doc.raw.fx[i].t >= t0 and doc.raw.fx[i].t < t1: fx.append(i)
	var tracks := []
	for i in notes:
		var id := int(doc.raw.notes[int(i)].light)
		if not id in tracks: tracks.append(id)
	set_selection(notes, tracks, false); doc.selection.fx = fx
	selected.emit()

## ------------------------------------------------------------------ track shapes
func _has_node(key: Dictionary) -> bool:
	for x in sel_nodes:
		if x.s == key.s and x.n == key.n: return true
	return false

func _clone_work() -> Array:
	var out := []
	for s in work.shapes: out.append(s.clone())
	return out

func _restore_work(orig: Array) -> void:
	var out := []
	for s in orig: out.append(s.clone())
	work.shapes = out

func _refresh_work_entry() -> void:
	if work.is_empty(): return
	tracks_view[work.id] = _track_entry(work.id, work.shapes, int(tracks_view.get(work.id, {"count": 0}).count))
	queue_redraw()

func _shape_at(id: int, t: float) -> int:
	if work.is_empty(): return 0
	for si in work.shapes.size():
		var r: Array = work.shapes[si].t_range()
		if t >= r[0] and t <= r[1]: return si
	return 0

func lane_info(s) -> Dictionary:
	var rep := Adapter.is_representable(s)
	if not rep.ok: return {}
	var left := []; var right := []
	for i in s.size():
		var n: Dictionary = s.nodes[i]
		var p: int = s.partner(i)
		if p < 0: continue
		if n.x <= s.nodes[p].x: left.append(i)
		else: right.append(i)
	return {"left": left, "right": right}

func _start_node_drag(at: Vector2, anchor: Dictionary) -> void:
	var s = work.shapes[anchor.s]
	drag = {"mode": "node", "start": at, "anchor": anchor, "orig": _clone_work(), "a0": s.pos(anchor.n), "at0": s.nodes[anchor.n].t, "lane": not lane_info(s).is_empty()}

func _start_edge_drag(at: Vector2, h: Dictionary) -> void:
	var s = work.shapes[h.s]
	var lane := lane_info(s)
	var nodes := []
	if not lane.is_empty():
		var a: int = h.seg; var b: int = s.next(h.seg)
		if a in lane.left and b in lane.left: nodes = lane.left
		elif a in lane.right and b in lane.right: nodes = lane.right
		else: nodes = [a, b]
	else: nodes = [h.seg, s.next(h.seg)]
	var sel := []
	for n in nodes: sel.append({"s": h.s, "n": n})
	drag = {"mode": "edge", "start": at, "nodes": sel, "orig": _clone_work(), "x_only": not lane.is_empty() and nodes.size() > 2}

func _drag_shape(e: InputEventMouseMotion) -> void:
	var snap_on := not e.alt_pressed
	var du := u_of(e.position.x) - u_of(drag.start.x)
	var dtime := time_of(e.position.y) - time_of(drag.start.y)
	if e.shift_pressed:
		if absf(e.position.x - drag.start.x) > absf(e.position.y - drag.start.y): dtime = 0.0
		else: du = 0.0
	if snap_on: du = snappedf(du, 1.0 / 60.0)
	_restore_work(drag.orig)
	match drag.mode:
		"node":
			var s = work.shapes[drag.anchor.s]
			if snap_on and dtime != 0.0: dtime = snap_time(drag.at0 + dtime) - drag.at0
			var moving := sel_nodes.duplicate()
			# lane tracks keep paired nodes at the same time (today's syntax: one keyframe time for both edges)
			if drag.lane and absf(dtime) > 1e-9:
				for sn in sel_nodes:
					var p: int = work.shapes[sn.s].partner(sn.n)
					if p >= 0 and not _has_node({"s": sn.s, "n": p}) and not moving.any(func(x): return x.s == sn.s and x.n == p): moving.append({"s": sn.s, "n": p})
			for sn in moving:
				var sh = work.shapes[sn.s]
				var old_t: float = sh.nodes[sn.n].t
				var dx := du if _has_node(sn) else 0.0
				sh.move_node(sn.n, dx, dtime)
				if absf(dtime) > 1e-9: _retime_keys(sh, old_t, old_t + dtime)
		"edge":
			for sn in drag.nodes:
				work.shapes[sn.s].move_node(sn.n, du, 0.0 if drag.x_only else (snap_time(work.shapes[sn.s].nodes[sn.n].t + dtime) - work.shapes[sn.s].nodes[sn.n].t if snap_on else dtime))
		"body":
			if snap_on and dtime != 0.0: dtime = snap_time(drag.t0 + dtime) - drag.t0
			work.shapes[drag.s].translate(du, dtime)
	drag["moved"] = e.position.distance_to(drag.start) > 3
	_refresh_work_entry()

func _retime_keys(s, old_t: float, new_t: float) -> void:
	var ok := Shape.tkey(old_t); var nk := Shape.tkey(new_t)
	if s.pins.has(ok): s.pins[nk] = s.pins[ok]; s.pins.erase(ok)
	if s.keep.has(ok): s.keep.erase(ok); s.keep[nk] = true
	for p in s.props:
		if absf(p.t - old_t) < 1e-6: p.t = new_t
	s.props.sort_custom(func(a, b): return a.t < b.t)

func _insert_virtual(h: Dictionary) -> int:
	var s = work.shapes[h.s]
	var lane := not lane_info(s).is_empty()
	var at: int = s.insert(h.seg, h.u)
	s.nodes[at].t = h.t
	if lane: _pair_insert(s, at)
	return _find_node(s, h.t, s.nodes[at].x)

func _pair_insert(s, at: int) -> void:
	var t: float = s.nodes[at].t
	for seg in s.size():
		if seg == at or s.next(seg) == at: continue
		var a: Dictionary = s.nodes[seg]; var b: Dictionary = s.nodes[s.next(seg)]
		if minf(a.t, b.t) < t - 1e-6 and maxf(a.t, b.t) > t + 1e-6:
			var i2: int = s.insert(seg, (t - a.t) / (b.t - a.t))
			s.nodes[i2].t = t
			break
	var found := false
	for p in s.props:
		if absf(p.t - t) < 1e-6: found = true
	if not found:
		var pr: Dictionary = s.prop_at(t)
		s.props.append({"t": t, "a": pr.a, "tint": pr.tint}); s.props.sort_custom(func(x, y): return x.t < y.t)

func _find_node(s, t: float, x: float) -> int:
	for i in s.size():
		if absf(s.nodes[i].t - t) < 1e-6 and absf(s.nodes[i].x - x) < 1e-6: return i
	return 0

func _insert_node_at(si: int, seg: int, t: float) -> void:
	var s = work.shapes[si]
	var sp: Array = seg_params(s, seg, snap_time(t))
	if sp.is_empty(): sp = seg_params(s, seg, t)
	if sp.is_empty(): return
	var tt := snap_time(t) if not seg_params(s, seg, snap_time(t)).is_empty() else t
	var at: int = s.insert(seg, sp[0]); s.nodes[at].t = tt
	_pair_insert_if_lane(s, at)
	sel_nodes = [{"s": si, "n": _find_node(s, tt, s.nodes[at].x)}]
	nodes_changed.emit(); _refresh_work_entry()
	status.emit("已插入节点，拖动它改变轨道形状")

func _pair_insert_if_lane(s, at: int) -> void:
	var copy = s.clone(); copy.remove(at)
	if not lane_info(copy).is_empty(): _pair_insert(s, at)

func _commit_work(label: String) -> void:
	if work.is_empty(): return
	var result := Ops.commit_shapes(doc, work.id, work.shapes, label)
	if result.has("error"):
		say(Ops.explain(result)); select_track(work.id, true); refresh(true); return
	work.sig = Adapter.signature(Ops.track_events(doc, work.id))
	if not result.get("exact", true):
		say("游戏会按近似外轮廓显示这条轨道（" + "；".join(result.get("reasons", [])) + "），精确形状等引擎支持新轨道语法", false)
	refresh(true)

func _finish_create(d: Dictionary) -> void:
	var x0 := minf(d.a.x, d.b.x); var x1 := maxf(d.a.x, d.b.x)
	var t0 := minf(d.a.y, d.b.y); var t1 := maxf(d.a.y, d.b.y)
	if x1 - x0 < SU.KEY_UNIT - 1e-6: x1 = x0 + SU.KEY_UNIT; say("轨道至少一键宽，已按一键创建", false)
	if t1 - t0 < step_seconds(t0) * 0.99: t1 = t0 + step_seconds(t0) * grid / 4.0
	var result := Ops.create_track(doc, shape_kind, x0, x1, t0, t1)
	if report(result, "已创建轨道 %d" % result.get("id", -1)):
		set_selection([], [int(result.id)])
		if not result.get("exact", true): say("形状已保存到 chart.ext.json；游戏暂按外轮廓近似（需要新轨道语法）", false)

## Segment operations from the popover (or keyboard): `a`, `b` are node indices of shape si.
func segment_nodes(si: int, a: int, b: int) -> Dictionary:
	var s = work.shapes[si]
	var forward := []; var i := a
	while i != b and forward.size() <= s.size(): forward.append(i); i = s.next(i)
	var backward := []; i = b
	while i != a and backward.size() <= s.size(): backward.append(i); i = s.next(i)
	var segs: Array = forward if forward.size() <= backward.size() else backward
	var t0 := minf(s.nodes[a].t, s.nodes[b].t); var t1 := maxf(s.nodes[a].t, s.nodes[b].t)
	var lane := not lane_info(s).is_empty()
	if lane and absf(t1 - t0) > 1e-6:
		segs = []
		for k in s.size():
			var na: Dictionary = s.nodes[k]; var nb: Dictionary = s.nodes[s.next(k)]
			if minf(na.t, nb.t) >= t0 - 1e-6 and maxf(na.t, nb.t) <= t1 + 1e-6 and absf(na.t - nb.t) > 1e-9: segs.append(k)
	return {"segs": segs, "t0": t0, "t1": t1, "lane": lane}

func segment_op(si: int, a: int, b: int, op: String, value = null) -> void:
	if work.is_empty() or si >= work.shapes.size(): return
	var s = work.shapes[si]
	var seg := segment_nodes(si, a, b)
	var label := "片段"
	match op:
		"ease":
			for k in seg.segs: s.set_ease(k, str(value))
			label = {"linear": "片段改为直线", "in": "片段缓入", "out": "片段缓出", "inout": "片段缓入缓出", "bezier": "片段改为自由曲线"}.get(str(value), "片段曲线")
		"smooth", "corner":
			for n in [a, b]:
				s.nodes[n].smooth = op == "smooth"
				for k in [n, s.prev(n)]:
					if s.segs[k].ease != "bezier" and absf(s.nodes[k].t - s.nodes[s.next(k)].t) > 1e-9: s.set_ease(k, "inout" if op == "smooth" else "linear")
			label = "平滑节点" if op == "smooth" else "尖角节点"
		"insert":
			var tm := snap_time((seg.t0 + seg.t1) / 2.0)
			if tm <= seg.t0 + 1e-6 or tm >= seg.t1 - 1e-6: tm = (seg.t0 + seg.t1) / 2.0
			var k0: int = seg.segs[0] if not seg.segs.is_empty() else a
			for k in seg.segs:
				if minf(s.nodes[k].t, s.nodes[s.next(k)].t) < tm and maxf(s.nodes[k].t, s.nodes[s.next(k)].t) > tm: k0 = k; break
			var at: int = s.insert(k0, (tm - s.nodes[k0].t) / (s.nodes[s.next(k0)].t - s.nodes[k0].t)); s.nodes[at].t = tm
			_pair_insert_if_lane(s, at)
			label = "插入节点"
		"delete":
			delete_nodes(); return
		"flatten":
			var removed := 0
			var again := true
			while again:
				again = false
				for k in s.size():
					var nt: float = s.nodes[k].t
					if nt <= seg.t0 + 1e-6 or nt >= seg.t1 - 1e-6: continue
					var p: int = s.prev(k); var q: int = s.next(k)
					if s.segs[p].ease != "linear" or s.segs[k].ease != "linear": continue
					var d := Geometry2D.get_closest_point_to_segment(s.pos(k), s.pos(p), s.pos(q)).distance_to(s.pos(k))
					if d < 1e-4 and s.remove(k):
						_drop_keys(s, nt); removed += 1; again = true; break
			label = "拉平片段（移除 %d 个节点）" % removed
		"center", "width":
			for k in s.size():
				var n: Dictionary = s.nodes[k]
				if n.t < seg.t0 - 1e-6 or n.t > seg.t1 + 1e-6: continue
				var p: int = s.partner(k)
				if p < 0: continue
				var l: float = minf(n.x, s.nodes[p].x); var r: float = maxf(n.x, s.nodes[p].x)
				var c := (l + r) / 2.0; var w := r - l
				if op == "center": c = float(value)
				else: w = maxf(SU.KEY_UNIT, float(value))
				n.x = c - w / 2.0 if n.x <= s.nodes[p].x else c + w / 2.0
			label = "片段位置" if op == "center" else "片段宽度"
		"a0", "a1":
			var tt: float = seg.t0 if op == "a0" else seg.t1
			_ensure_prop(s, tt)
			for p in s.props:
				if absf(p.t - tt) < 1e-6: p.a = clampf(float(value), 0, 1)
			label = "片段不透明度"
		"tint":
			_ensure_prop(s, seg.t0); _ensure_prop(s, seg.t1)
			for p in s.props:
				if p.t > seg.t0 + 1e-6 and p.t <= seg.t1 + 1e-6: p.tint = int(value)
			label = "片段色调"
	_refresh_work_entry()
	_commit_work(label)

func _ensure_prop(s, t: float) -> void:
	for p in s.props:
		if absf(p.t - t) < 1e-6: return
	var pr: Dictionary = s.prop_at(t)
	s.props.append({"t": t, "a": pr.a, "tint": pr.tint}); s.props.sort_custom(func(x, y): return x.t < y.t)

func _drop_keys(s, t: float) -> void:
	var k := Shape.tkey(t)
	s.pins.erase(k); s.keep.erase(k)

func delete_nodes() -> void:
	if work.is_empty() or sel_nodes.is_empty(): return
	var by_shape := {}
	for sn in sel_nodes:
		if not by_shape.has(sn.s): by_shape[sn.s] = []
		by_shape[sn.s].append(sn.n)
	for si in by_shape:
		var s = work.shapes[si]
		var lane := not lane_info(s).is_empty()
		var times := []
		for n in by_shape[si]: times.append(s.nodes[n].t)
		var r: Array = s.t_range()
		for t in times:
			if lane and (absf(t - r[0]) < 1e-6 or absf(t - r[1]) < 1e-6): continue   # start/end edges stay
			var again := true
			while again:
				again = false
				for i in s.size():
					if absf(s.nodes[i].t - t) < 1e-6 and (lane or i in by_shape[si]):
						if s.remove(i): again = true; break
			_drop_keys(s, t)
			s.props = s.props.filter(func(p): return absf(p.t - t) > 1e-6 or s.props.size() <= 1)
	sel_nodes = []; nodes_changed.emit()
	_refresh_work_entry(); _commit_work("删除节点")

func nudge_nodes(dx: float, dt: float) -> void:
	var orig := _clone_work()
	for sn in sel_nodes:
		var s = work.shapes[sn.s]
		var old_t: float = s.nodes[sn.n].t
		s.move_node(sn.n, dx, dt)
		if absf(dt) > 0:
			var p: int = s.partner(sn.n)
			if p >= 0 and not _has_node({"s": sn.s, "n": p}) and not lane_info(orig[sn.s]).is_empty(): s.move_node(p, 0.0, dt)
			_retime_keys(s, old_t, old_t + dt)
	_refresh_work_entry(); _commit_work("微调节点")

## ------------------------------------------------------------------ keyboard
func _key(e: InputEventKey) -> bool:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			if not sel_nodes.is_empty(): delete_nodes(); return true
			if not doc.selection.notes.is_empty(): delete_selected_notes(); return true
			if selected_track() >= 0: report(Ops.delete_track(doc, selected_track())); return true
		KEY_ESCAPE:
			if not drag.is_empty(): drag = {}; refresh(true); return true
			sel_nodes = []; set_selection([], []); return true
		KEY_BRACKETLEFT: cycle_grid(-1); return true
		KEY_BRACKETRIGHT: cycle_grid(1); return true
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			var vertical := e.keycode in [KEY_UP, KEY_DOWN]
			var d := 1 if e.keycode in [KEY_UP, KEY_RIGHT] else -1
			if not sel_nodes.is_empty():
				if vertical: nudge_nodes(0.0, d * step_seconds(cursor))
				else: nudge_nodes(d * (1.0 / 15.0 if e.shift_pressed else (1.0 / 240.0 if e.alt_pressed else 1.0 / 60.0)), 0.0)
				return true
			if not doc.selection.notes.is_empty():
				var res := Ops.move_notes(doc, doc.selection.notes, d * step_seconds(cursor) if vertical else 0.0, 0 if vertical else d, false, locked_tracks)
				if not res.ok: say(res.reason); return true
				report(doc.edit({"expected_revision": doc.revision(), "label": "微调音符", "ops": res.ops, "ext": res.ext}))
				return true
			if vertical: seek.emit(maxf(0.0, snap_time(cursor + d * step_seconds(cursor)))); return true
		KEY_C:
			if ctrl and not doc.selection.notes.is_empty():
				clipboard = Ops.copy_notes(doc, doc.selection.notes); status.emit("已复制 %d 个音符" % clipboard.size()); return true
		KEY_X:
			if ctrl and not doc.selection.notes.is_empty():
				clipboard = Ops.copy_notes(doc, doc.selection.notes); delete_selected_notes(); return true
		KEY_V:
			if ctrl and not clipboard.is_empty(): paste_at(snap_time(cursor)); return true
		KEY_D:
			if ctrl and not doc.selection.notes.is_empty(): duplicate_notes(); return true
		KEY_A:
			if ctrl:
				var notes := []
				for nv in notes_view:
					if note_visible(nv) and nv.t >= t_lo() and nv.t <= t_hi(): notes.append(nv.i)
				set_selection(notes, []); return true
		KEY_ENTER, KEY_KP_ENTER:
			if sel_nodes.size() == 2 and sel_nodes[0].s == sel_nodes[1].s: popover_requested.emit(sel_nodes[0].s, sel_nodes[0].n, sel_nodes[1].n); return true
	return false

func delete_selected_notes() -> void:
	var res := Ops.delete_notes(doc, doc.selection.notes)
	if report(doc.edit({"expected_revision": doc.revision(), "label": "删除音符", "ops": res.ops, "ext": res.ext})): set_selection([], [])

func paste_at(t: float) -> void:
	var res := Ops.paste_notes(doc, clipboard, t, locked_tracks)
	if not res.ok: say(res.reason); return
	if report(doc.edit({"expected_revision": doc.revision(), "label": "粘贴音符", "ops": res.ops, "ext": res.ext})):
		set_selection(range(doc.raw.notes.size() - res.ops.size(), doc.raw.notes.size()), [])

func duplicate_notes() -> void:
	var lo := INF; var hi := -INF
	for i in doc.selection.notes: lo = minf(lo, float(doc.raw.notes[int(i)].t)); hi = maxf(hi, float(doc.raw.notes[int(i)].t))
	var clip := Ops.copy_notes(doc, doc.selection.notes)
	var step := step_seconds(hi)
	var offset := maxf(step, snappedf(hi - lo, step) + step)
	var saved := clipboard; clipboard = clip; paste_at(lo + offset); clipboard = saved

## ------------------------------------------------------------------ context menu
func _context_menu(p: Vector2) -> void:
	var h := hit(p)
	_menu_ctx = {"hit": h, "t": time_of(p.y), "u": u_of(p.x), "pos": p}
	menu.clear(); motion_menu.clear()
	match h.kind:
		"note", "tail":
			if not h.i in doc.selection.notes: set_selection([h.i], [int(doc.raw.notes[h.i].light)])
			var n: Dictionary = doc.raw.notes[h.i]
			menu.add_item("转为点按" if n.get("kind", "") == "hold" else "转为长按", 10)
			menu.add_check_item("大音符", 11); menu.set_item_checked(menu.item_count - 1, n.get("big", false))
			menu.add_check_item("EX（黄键）", 12); menu.set_item_checked(menu.item_count - 1, n.get("ex", false))
			menu.add_separator()
			motion_menu.add_item("直落（无运动）", 0)
			var types := Motion.types()
			for i in types.size(): motion_menu.add_item(types[i].LABEL, i + 1)
			menu.add_submenu_node_item("运动", motion_menu)
			menu.add_separator()
			menu.add_item("复制", 13); menu.set_item_accelerator(menu.item_count - 1, KEY_MASK_CTRL | KEY_C)
			menu.add_item("原位复制到后面", 14); menu.set_item_accelerator(menu.item_count - 1, KEY_MASK_CTRL | KEY_D)
			menu.add_item("选中所在轨道", 15)
			menu.add_separator()
			menu.add_item("删除", 16); menu.set_item_accelerator(menu.item_count - 1, KEY_DELETE)
		"node", "vnode", "handle", "edge":
			if h.kind == "node" and not _has_node({"s": h.s, "n": h.n}): sel_nodes = [{"s": h.s, "n": h.n}]; nodes_changed.emit()
			if h.kind == "edge" or h.kind == "vnode": menu.add_item("在此插入节点", 20)
			if not sel_nodes.is_empty():
				menu.add_item("平滑节点", 21); menu.add_item("尖角节点", 22)
				if sel_nodes.size() == 2: menu.add_item("片段设置…", 23); menu.set_item_accelerator(menu.item_count - 1, KEY_ENTER)
				menu.add_item("删除节点", 24); menu.set_item_accelerator(menu.item_count - 1, KEY_DELETE)
			menu.add_separator()
			_track_items(work.id)
		"body":
			if work.get("id", -99) != h.id: set_selection([], [h.id])
			menu.add_item("在此插入节点", 20)
			menu.add_separator()
			_track_items(h.id)
		_:
			var k := Ops.key_of(_menu_ctx.u)
			menu.add_item("在此放置音符（%s 键）" % Ops.key_name(k), 40)
			if not clipboard.is_empty(): menu.add_item("粘贴 %d 个音符" % clipboard.size(), 41); menu.set_item_accelerator(menu.item_count - 1, KEY_MASK_CTRL | KEY_V)
			menu.add_item("在此创建轨道（一小节）", 42)
			menu.add_separator()
			menu.add_item("播放头跳到这里", 43)
			menu.add_item("全选可见音符", 44); menu.set_item_accelerator(menu.item_count - 1, KEY_MASK_CTRL | KEY_A)
	menu.reset_size()
	menu.popup(Rect2i(Vector2i(get_screen_position() + p), Vector2i.ZERO))

func _track_items(id: int) -> void:
	_menu_ctx["track"] = id
	menu.add_check_item("隐藏", 30); menu.set_item_checked(menu.item_count - 1, hidden_tracks.get(id, false))
	menu.add_check_item("独奏", 31); menu.set_item_checked(menu.item_count - 1, solo == id)
	menu.add_check_item("锁定", 32); menu.set_item_checked(menu.item_count - 1, locked_tracks.get(id, false))
	menu.add_separator()
	menu.add_item("设为透明承载轨（不透明度 0）", 33)
	menu.add_item("设为可见（不透明度 0.5）", 34)
	menu.add_separator()
	menu.add_item("删除轨道", 35)

func _menu_action(id: int) -> void:
	var h: Dictionary = _menu_ctx.get("hit", {})
	var t: float = _menu_ctx.get("t", cursor)
	match id:
		10:
			var ops := []
			for i in doc.selection.notes:
				var n: Dictionary = doc.raw.notes[int(i)]
				var hold: bool = n.get("kind", "") != "hold"
				ops.append({"target": "notes", "op": "update", "index": int(i), "value": {"kind": "hold" if hold else "tap", "dur": Adapter.num(doc.position(float(n.t)).beat_seconds) if hold else 0}})
			report(doc.edit({"expected_revision": doc.revision(), "label": "转换长按", "ops": ops}))
		11, 12:
			var field := "big" if id == 11 else "ex"
			var on: bool = not doc.raw.notes[int(h.i)].get(field, false)
			var ops := []
			for i in doc.selection.notes: ops.append({"target": "notes", "op": "update", "index": int(i), "value": {field: on}})
			report(doc.edit({"expected_revision": doc.revision(), "label": "大音符" if id == 11 else "EX", "ops": ops}))
		13: clipboard = Ops.copy_notes(doc, doc.selection.notes); status.emit("已复制 %d 个音符" % clipboard.size())
		14: duplicate_notes()
		15: set_selection([], [int(doc.raw.notes[int(h.i)].light)])
		16: delete_selected_notes()
		20:
			if h.kind in ["edge", "vnode"]: _insert_node_at(h.s, h.seg, t)
			elif not work.is_empty():
				var si := _shape_at(work.id, t)
				var s = work.shapes[si]
				for seg in s.size():
					var a: Dictionary = s.nodes[seg]; var b: Dictionary = s.nodes[s.next(seg)]
					if minf(a.t, b.t) < t and maxf(a.t, b.t) > t: _insert_node_at(si, seg, t); break
		21: segment_op(sel_nodes[0].s, sel_nodes[0].n, sel_nodes[-1].n, "smooth")
		22: segment_op(sel_nodes[0].s, sel_nodes[0].n, sel_nodes[-1].n, "corner")
		23: popover_requested.emit(sel_nodes[0].s, sel_nodes[0].n, sel_nodes[1].n)
		24: delete_nodes()
		30: hidden_tracks[_menu_ctx.track] = not hidden_tracks.get(_menu_ctx.track, false); refresh(true); selected.emit()
		31: solo = -1 if solo == _menu_ctx.track else _menu_ctx.track; refresh(true); selected.emit()
		32: locked_tracks[_menu_ctx.track] = not locked_tracks.get(_menu_ctx.track, false); selected.emit(); queue_redraw()
		33, 34: report(Ops.set_track_props(doc, _menu_ctx.track, {"a": 0.0 if id == 33 else 0.5}, "轨道不透明度")); select_track(_menu_ctx.track)
		35: if report(Ops.delete_track(doc, _menu_ctx.track)): set_selection([], [])
		40: _place(snap_time(t), Ops.key_of(_menu_ctx.u), 0.0)
		41: paste_at(snap_time(t))
		42:
			var k := Ops.key_of(_menu_ctx.u); var t0 := snap_time(t)
			var r := Ops.create_track(doc, "rect", Ops.key_x(k) - 1.0 / 15.0, Ops.key_x(k) + 1.0 / 15.0, t0, t0 + doc.position(t0).beat_seconds * 4.0)
			if report(r): set_selection([], [int(r.id)])
		43: seek.emit(maxf(0.0, snap_time(t)))
		44:
			var notes := []
			for nv in notes_view:
				if note_visible(nv) and nv.t >= t_lo() and nv.t <= t_hi(): notes.append(nv.i)
			set_selection(notes, [])
		_:
			if id >= 1000: set_motion(id - 1000)

func set_motion(choice: int) -> void:
	var motions: Dictionary = doc.ext.motions.duplicate(true)
	var types := Motion.types()
	for i in doc.selection.notes:
		var key := Ops.motion_key(doc.raw.notes[int(i)])
		if choice == 0: motions.erase(key)
		else: motions[key] = {"type": types[choice - 1].ID, "params": Motion.defaults(types[choice - 1].ID)}
	var ext: Dictionary = doc.ext.duplicate(true); ext.motions = motions
	report(doc.edit({"expected_revision": doc.revision(), "label": "音符运动", "ops": [], "ext": ext}))

## ------------------------------------------------------------------ drawing
func _draw() -> void:
	if doc == null or doc.raw.is_empty(): return
	refresh()
	var tk := Tokens.tokens(light)
	var font := Tokens.font("sans"); var mono := Tokens.font("mono")
	var num := Tokens.font("num"); var bar_font := Tokens.font("num", 600)
	var lo := maxf(-2.0, t_lo()); var hi := t_hi()
	var fx0 := x_of(-LO); var fx1 := x_of(1.0 + LO)
	draw_style_box(Tokens.box(tk.canvas, 12, tk.border), Rect2(Vector2.ZERO, size))
	# spill zones and key lanes
	var top := T; var bottom := size.y - B
	draw_rect(Rect2(fx0, top, x_of(0) - fx0, bottom - top), Color(tk.text, 0.025))
	draw_rect(Rect2(x_of(1), top, fx1 - x_of(1), bottom - top), Color(tk.text, 0.025))
	# Shift-row cells (left Shift, Z X, C V, B N, M ",", ". /", right Shift): alternate shading + faint guides
	var cells := shift_cells()
	for ci in cells.size():
		var c: Dictionary = cells[ci]
		if ci % 2 == 1: draw_rect(Rect2(x_of(c.x0 / 15.0), top, x_of(c.x1 / 15.0) - x_of(c.x0 / 15.0), bottom - top), Color(tk.text, 0.02))
		if ci > 0: draw_line(Vector2(x_of(c.x0 / 15.0), top), Vector2(x_of(c.x0 / 15.0), bottom), Color(tk.text, 0.06), 1)
	if ghost.size() > 0 or tool in ["tap", "hold"]:
		if mouse.x > L and mouse.x < size.x - R:
			var hk := Ops.key_of(u_of(mouse.x))
			draw_rect(Rect2(x_of((1.75 + hk) / 15.0), top, x_of(1.0 / 15.0) - x_of(0), bottom - top), Color(tk.clay, 0.05))
	draw_dashed_line(Vector2(x_of(7.5 / 15.0), top), Vector2(x_of(7.5 / 15.0), bottom), Color(tk.text, 0.07), 1, 4)   # G | H centre
	# time grid
	var beat_px: float = doc.position(cursor).beat_seconds * pixels
	for pos in doc.grid(maxf(0, lo), hi, grid):
		var y := y_of(pos.seconds)
		var on_beat := absf(pos.beat - roundf(pos.beat)) < 0.01
		var on_bar := on_beat and roundi(pos.beat) == 1
		var col: Color = tk.grid_bar if on_bar else (tk.grid_beat if on_beat else tk.grid)
		if not on_beat and step_seconds(pos.seconds) * pixels < 7: continue
		draw_line(Vector2(fx0, y), Vector2(fx1, y), col, 1)
		if on_bar:
			draw_string(bar_font, Vector2(16, y + 6), str(int(pos.bar)), HORIZONTAL_ALIGNMENT_LEFT, L - 18, Tokens.MD, tk.text)
			var secs: float = pos.seconds
			if absf(y - judge_y()) > 14:   # the playhead's own time sits there instead
				draw_string(mono, Vector2(size.x - R + 10, y + 4), "%d:%05.2f" % [int(secs) / 60, fmod(secs, 60.0)], HORIZONTAL_ALIGNMENT_LEFT, R - 12, Tokens.XS, tk.muted)
		elif on_beat and beat_px > 22:
			draw_string(num, Vector2(30, y + 4), ".%d" % roundi(pos.beat), HORIZONTAL_ALIGNMENT_LEFT, L - 32, Tokens.XS, tk.faint)
	for segment in doc.timing():
		if segment.t >= lo and segment.t < hi:
			draw_string(Tokens.font("num", 600), Vector2(fx0 + 6, y_of(segment.t) - 7), "♩ %.1f" % (60.0 / segment.beat), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.clay)
	for k in doc.raw.get("meta", {}).get("kiai", []):
		var y0 := y_of(float(k.get("t0", 0))); var y1 := y_of(float(k.get("t1", 0)))
		draw_rect(Rect2(L - 6, minf(y0, y1), 3, absf(y1 - y0)), Color(tk.clay, 0.35))
	# selection time span (in the gutters only, the field stays clean)
	if doc.selection.to > doc.selection.from:
		var ys := y_of(doc.selection.to); var ye := y_of(doc.selection.from)
		draw_rect(Rect2(L - 11, ys, 3, ye - ys), Color(tk.clay, 0.8))
	_draw_tracks(tk)
	_draw_notes(tk, lo, hi, mono)
	_draw_work(tk)
	_draw_overlays(tk, font, mono)

func _draw_tracks(tk: Dictionary) -> void:
	var xf := xt_to_screen()
	var lo := t_lo(); var hi := t_hi()
	var ci := get_canvas_item()
	var ids := tracks_view.keys()
	# performers underneath, note carriers on top
	ids.sort_custom(func(a, b): return int(tracks_view[a].count > 0) < int(tracks_view[b].count > 0))
	for id in ids:
		if not track_visible(id): continue
		var tv: Dictionary = tracks_view[id]
		var is_sel: bool = work.get("id", -99) == id
		var is_hover: bool = hover.get("kind", "") == "body" and hover.get("id", -99) == id
		var changed: bool = id in changed_tracks
		for poly in tv.polys:
			if poly.hi < lo or poly.lo > hi: continue
			var pts: PackedVector2Array = xf * poly.pts
			var cols := PackedColorArray()
			for c in poly.cols:
				var fill: float = 0.035 + 0.13 * c.a if c.a > 0.001 else 0.025
				if is_sel: fill += 0.05
				cols.append(Color(c.r, c.g, c.b, fill))
			if poly.tris.size() >= 3: RenderingServer.canvas_item_add_triangle_array(ci, poly.tris, pts, cols)
			var outline: Color = Tokens.tint(-1, light) if poly.cols.is_empty() else Color(poly.cols[0].r, poly.cols[0].g, poly.cols[0].b)
			var oa := 0.55 if tv.transparent else 0.32
			if is_hover: oa += 0.2
			var closed := pts.duplicate(); closed.append(pts[0])
			if is_sel or changed:
				draw_polyline(closed, tk.clay, 1.5, true)
			elif tv.transparent:
				_dashed(closed, Color(outline, oa), 1.2)
			else:
				draw_polyline(closed, Color(outline, oa), 1.0, true)
			if not tv.exact and not is_sel:
				draw_string(Tokens.font("sans"), pts[0] + Vector2(4, -5), "近似", HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, Color(tk.clay, 0.85))

func _dashed(pts: PackedVector2Array, col: Color, w: float) -> void:
	var segs := PackedVector2Array()
	var on := true; var acc := 0.0; var dash := 6.0; var gap := 4.0
	for k in pts.size() - 1:
		var a := pts[k]; var b := pts[k + 1]
		var seglen := a.distance_to(b)
		if seglen < 0.01: continue
		if (a.y < -20 and b.y < -20) or (a.y > size.y + 20 and b.y > size.y + 20): continue
		var pos := 0.0
		while pos < seglen:
			var limit := (dash if on else gap) - acc
			var stepl := minf(limit, seglen - pos)
			if on:
				segs.append(a.lerp(b, pos / seglen)); segs.append(a.lerp(b, (pos + stepl) / seglen))
			pos += stepl; acc += stepl
			if acc >= (dash if on else gap) - 0.001: acc = 0.0; on = not on
	if segs.size() >= 2: draw_multiline(segs, col, w, true)

func _draw_notes(tk: Dictionary, lo: float, hi: float, mono: Font) -> void:
	var sel := {}
	for i in doc.selection.get("notes", []): sel[int(i)] = true
	var moving := {}
	if drag.get("mode", "") == "notes" and drag.get("moved", false):
		for p in drag.preview: moving[p.i] = p
	for nv in notes_view:
		if nv.t + nv.dur < lo - 0.2 or nv.t > hi + 0.2 or not note_visible(nv): continue
		var x := x_of(nv.x); var y := y_of(nv.t)
		var base: Color = tk.note_ex if nv.ex else tk.note
		var is_sel: bool = sel.has(nv.i)
		var col: Color = tk.clay if is_sel else base
		if moving.has(nv.i) and not drag.dup: col = Color(col, 0.28)
		if nv.kind == "hold":
			var yt := y_of(nv.t + nv.dur)
			var tail_dur: float = drag.get("dur", nv.dur) if drag.get("mode", "") == "tail" and drag.i == nv.i else nv.dur
			yt = y_of(nv.t + tail_dur)
			draw_rect(Rect2(x - 4, yt, 8, y - yt), Color(col, 0.32))
			draw_line(Vector2(x - 7, yt), Vector2(x + 7, yt), Color(col, 0.9), 2, true)
			for tick in nv.ticks:
				var ty := y_of(float(tick))
				draw_line(Vector2(x - 4, ty), Vector2(x + 4, ty), Color(col, 0.6), 1)
		if show_windows: draw_line(Vector2(x, y_of(nv.t - nv.w_e)), Vector2(x, y_of(nv.t + nv.w_l)), Color(col, 0.45), 1)
		var r := note_rect(nv)
		draw_style_box(Tokens.box(col, 4), r)
		if is_sel: draw_style_box(Tokens.box(Color.TRANSPARENT, 6, Color(tk.clay, 0.5), 0, 0, 1), r.grow(3))
		if nv.i in changed_notes: draw_arc(Vector2(x, y), 15, 0, TAU, 32, tk.clay, 1.5, true)
		if show_fingering or is_sel or hover.get("i", -1) == nv.i:
			var label := Ops.key_name(nv.k) if nv.k >= 0 else "?"
			draw_string(Tokens.font("sans", 600), Vector2(r.end.x + 6, y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, tk.muted if not is_sel else tk.clay)
		var m: Dictionary = doc.ext.motions.get(Ops.motion_key(doc.raw.notes[nv.i]), {}) if nv.i < doc.raw.notes.size() else {}
		if not m.is_empty(): _draw_motion(nv, m, is_sel, tk)
	for p in moving.values():
		var nv := _view_of(p.i)
		var r := Rect2(x_of(Ops.key_x(p.k)) - (17 if nv.big else 11), y_of(p.t) - 4.5, 34 if nv.big else 22, 9)
		draw_style_box(Tokens.box(Color(tk.clay if p.ok else tk.danger, 0.85), 4), r)

func _draw_motion(nv: Dictionary, m: Dictionary, is_sel: bool, tk: Dictionary) -> void:
	var path := Motion.path(m, {"doc": doc, "note": doc.raw.notes[nv.i], "land_x": nv.x})
	if path.is_empty(): return
	var pts := PackedVector2Array()
	for p in path: pts.append(Vector2(x_of(p[1]), y_of(nv.t + p[0])))
	draw_polyline(pts, Color(tk.clay if is_sel else tk.muted, 0.55 if is_sel else 0.25), 1.2, true)
	if is_sel:
		var sx := motion_start_x(nv, m)
		if not is_nan(sx):
			var hp := Vector2(x_of(sx), y_of(nv.t + Motion.FALL))
			draw_circle(hp, 5, tk.s3, true, -1, true); draw_arc(hp, 5, 0, TAU, 20, tk.clay, 1.5, true)

func _ensure_work_screen() -> void:
	_work_screen = []
	if work.is_empty(): return
	for s in work.shapes:
		var poly: Dictionary = s.polygon()
		var pts := PackedVector2Array()
		for p in poly.points: pts.append(screen(p))
		_work_screen.append({"pts": pts, "owner": poly.owner})

func _draw_work(tk: Dictionary) -> void:
	_ensure_work_screen()
	if work.is_empty(): return
	for si in work.shapes.size():
		var s = work.shapes[si]
		if not Adapter.is_representable(s).ok:
			var r: Array = s.t_range()
			var lbl := Vector2(x_of(s.envelope((r[0] + r[1]) / 2.0).y) + 8, y_of((r[0] + r[1]) / 2.0))
			if lbl.y > T and lbl.y < size.y - B:
				var msg := "游戏按近似外轮廓显示"
				var mw := Tokens.font("sans").get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x
				draw_style_box(Tokens.box(Color(tk.s3, 0.95), 6, tk.border_strong, 6, 3), Rect2(lbl - Vector2(0, 13), Vector2(mw + 16, 26)))
				draw_string(Tokens.font("sans"), lbl + Vector2(8, 5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, tk.clay)
	# handles of selected nodes
	for sn in sel_nodes:
		if sn.s >= work.shapes.size(): continue
		var s = work.shapes[sn.s]
		for seg_i in [sn.n, s.prev(sn.n)]:
			if s.segs[seg_i].ease != "bezier": continue
			var a := screen(s.pos(seg_i)); var b := screen(s.pos(s.next(seg_i)))
			var h1 := screen(s.segs[seg_i].h1); var h2 := screen(s.segs[seg_i].h2)
			draw_line(a, h1, Color(tk.clay, 0.6), 1, true); draw_line(b, h2, Color(tk.clay, 0.6), 1, true)
			for h in [h1, h2]: draw_circle(h, 3.5, tk.s3, true, -1, true); draw_arc(h, 3.5, 0, TAU, 16, tk.clay, 1.2, true)
	# grid crossings = virtual nodes, then real nodes
	for v in virtual_nodes():
		var p := screen(v.p)
		if p.y < T or p.y > size.y - B: continue
		var hv: bool = hover.get("kind", "") == "vnode" and hover.s == v.s and hover.seg == v.seg and absf(hover.t - v.t) < 1e-6
		draw_arc(p, 3.2 if not hv else 4.5, 0, TAU, 14, Color(tk.clay, 0.55 if not hv else 1.0), 1.1, true)
	for si in work.shapes.size():
		var s = work.shapes[si]
		for ni in s.size():
			var p := screen(s.pos(ni))
			if p.y < T - 6 or p.y > size.y - B + 6: continue
			var on := _has_node({"s": si, "n": ni})
			var hv: bool = hover.get("kind", "") == "node" and hover.s == si and hover.n == ni
			var r := Rect2(p - Vector2(4.5, 4.5), Vector2(9, 9))
			if s.nodes[ni].smooth:
				draw_circle(p, 5, tk.clay if on else tk.s3, true, -1, true); draw_arc(p, 5, 0, TAU, 18, tk.clay, 1.3 if not hv else 2.0, true)
			else:
				draw_rect(r, tk.clay if on else tk.s3); draw_rect(r, tk.clay, false, 1.3 if not hv else 2.0)

func _draw_overlays(tk: Dictionary, font: Font, mono: Font) -> void:
	var num := Tokens.font("num")
	# rulers: key units on top, the Shift row of the active keyboard layout at the bottom
	draw_rect(Rect2(L, 0, field_w(), T - 2), Color(tk.canvas, 0.92))
	draw_rect(Rect2(L, size.y - B + 2, field_w(), B - 3), Color(tk.canvas, 0.92))
	for q in 61:
		var x := x_of(q / 60.0)
		var hgt := 7.0 if q % 4 == 0 else 3.0
		draw_line(Vector2(x, T - 2 - hgt), Vector2(x, T - 2), Color(tk.text, 0.22 if q % 4 == 0 else 0.1), 1)
		if q % 12 == 0:
			var qs := str(q / 4)
			draw_string(num, Vector2(x - num.get_string_size(qs, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS).x / 2.0, 15), qs, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.faint)
	var mu := u_of(mouse.x) * 15.0 if mouse.x > L and mouse.x < size.x - R else -99.0
	var kf := Tokens.font("sans", 500)
	for c in shift_cells():
		var x0 := x_of(c.x0 / 15.0); var x1 := x_of(c.x1 / 15.0)
		if c.x0 > 0.0: draw_line(Vector2(x0, size.y - B + 6), Vector2(x0, size.y - 6), Color(tk.text, 0.12), 1)
		var w := kf.get_string_size(c.label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x
		var hot: bool = mu >= c.x0 and mu < c.x1
		draw_string(kf, Vector2((x0 + x1 - w) / 2.0, size.y - 13), c.label, HORIZONTAL_ALIGNMENT_LEFT, x1 - x0, Tokens.BODY, tk.clay if hot else tk.muted)
	# drags in progress
	match drag.get("mode", ""):
		"marquee":
			var r := Rect2(drag.a, Vector2.ZERO).expand(drag.b)
			draw_rect(r, Color(tk.clay, 0.06)); draw_rect(r, Color(tk.clay, 0.55), false, 1)
		"create":
			var a := screen(drag.a); var b := screen(drag.b)
			var r := Rect2(a, Vector2.ZERO).expand(b)
			var preview = Shape.preset(shape_kind, minf(drag.a.x, drag.b.x), maxf(drag.a.x, drag.b.x), minf(drag.a.y, drag.b.y), maxf(drag.a.y, drag.b.y))
			var pts := PackedVector2Array()
			for p in preview.polygon().points: pts.append(screen(p))
			if pts.size() >= 3:
				pts.append(pts[0]); draw_polyline(pts, tk.clay, 1.5, true)
			draw_rect(r, Color(tk.clay, 0.25), false, 1)
			draw_string(mono, r.end + Vector2(8, -6), "%s  宽 %.2f 键" % [doc.position(minf(drag.a.y, drag.b.y)).bar_beat, absf(drag.b.x - drag.a.x) * 15.0], HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, tk.clay)
		"hold_create":
			var x := x_of(Ops.key_x(drag.k))
			var place := Ops.placement(doc, drag.t0, drag.k, drag.t1 - drag.t0, selected_track(), locked_tracks, hidden_tracks)
			var col: Color = tk.clay if place.ok else tk.danger
			draw_rect(Rect2(x - 4, y_of(drag.t1), 8, y_of(drag.t0) - y_of(drag.t1)), Color(col, 0.3))
			draw_style_box(Tokens.box(col, 4), Rect2(x - 11, y_of(drag.t0) - 4.5, 22, 9))
			if not place.ok: _bubble_at(Vector2(x + 16, y_of(drag.t1)), place.reason, true, tk)
		"notes":
			if drag.get("moved", false) and not drag.get("ok", true): _bubble_at(mouse + Vector2(14, -18), drag.reason, true, tk)
		"tail":
			if not drag.get("ok", true): _bubble_at(mouse + Vector2(14, -18), drag.reason, true, tk)
	# ghost under the cursor for the note tools
	if not ghost.is_empty() and drag.is_empty():
		var x := x_of(Ops.key_x(ghost.k)); var y := y_of(ghost.t)
		var col: Color = tk.clay if ghost.ok else tk.danger
		if tool == "hold" and ghost.ok: draw_rect(Rect2(x - 4, y_of(ghost.t + ghost.dur), 8, y - y_of(ghost.t + ghost.dur)), Color(col, 0.18))
		draw_style_box(Tokens.box(Color(col, 0.35), 4, col, 0, 0, 1), Rect2(x - 11, y - 4.5, 22, 9))
		draw_string(Tokens.font("sans", 600), Vector2(x + 18, y + 5), Ops.key_name(ghost.k) + "  " + doc.position(ghost.t).bar_beat, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, col)
		if not ghost.ok: _bubble_at(Vector2(x + 16, y - 30), ghost.reason, true, tk)
	# hover time readout in the gutter
	if mouse.x >= 0 and mouse.y > T and mouse.y < size.y - B and drag.get("mode", "") != "pan":
		draw_line(Vector2(L, mouse.y), Vector2(size.x - R, mouse.y), Color(tk.text, 0.05), 1)
	# playhead
	var py := judge_y()
	draw_line(Vector2(6, py), Vector2(size.x - R + 4, py), tk.clay, 2, true)
	var secs_now := "%d:%05.2f" % [int(cursor) / 60, fmod(cursor, 60.0)]
	draw_string(Tokens.font("mono", 600), Vector2(size.x - R + 10, py + 4), secs_now, HORIZONTAL_ALIGNMENT_LEFT, R - 12, Tokens.XS, tk.clay)
	var label: String = doc.position(cursor).bar_beat
	var pf := Tokens.font("mono", 600)
	var lw := pf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x
	draw_style_box(Tokens.box(tk.clay, 6), Rect2(4, py - 12, minf(L - 6, lw + 12), 24))
	draw_string(pf, Vector2(10, py + 5), label, HORIZONTAL_ALIGNMENT_LEFT, L - 14, Tokens.BODY, Color.WHITE)
	if not bubble.is_empty():
		if Time.get_ticks_msec() > bubble.until: bubble = {}
		else: _bubble_at(bubble.pos + Vector2(14, -26), bubble.text, bubble.bad, tk)

func _bubble_at(p: Vector2, text: String, bad: bool, tk: Dictionary) -> void:
	var f := Tokens.font("sans")
	var w := minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x + (36 if bad else 24), size.x - 16)
	var at := Vector2(clampf(p.x, 8, size.x - w - 8), clampf(p.y, 8, size.y - 40))
	var b := Tokens.box(tk.s3, 8, Color(tk.danger, 0.7) if bad else tk.border_strong)
	b.shadow_color = tk.shadow; b.shadow_size = 8
	draw_style_box(b, Rect2(at, Vector2(w, 32)))
	if bad: draw_circle(at + Vector2(13, 16), 3.5, tk.danger, true, -1, true)
	draw_string(f, at + Vector2(24 if bad else 12, 21), text, HORIZONTAL_ALIGNMENT_LEFT, w - 28, Tokens.BODY, tk.text)

## The Shift row of the active keyboard layout (scripts/kb.gd rows()) as ruler cells in key units:
## the keys left of Z as one cell, Z..Slash two keys per cell, the keys right of Slash as one cell.
static func shift_cells() -> Array:
	var row: Array = KB.rows(KB.layout)[3]
	var names := func(keys: Array) -> String:
		var parts := []
		for k in keys: parts.append("Shift" if str(k[0]).begins_with("Shift") else KB.label(k[0]))
		return " ".join(parts)
	var zi := -1; var si := -1
	for i in row.size():
		if row[i][0] == "KeyZ": zi = i
		if row[i][0] == "Slash": si = i
	if zi < 0 or si < 0: return []
	var out := []
	if zi > 0: out.append({"x0": 0.0, "x1": float(row[zi][1]), "label": names.call(row.slice(0, zi))})
	var i := zi
	while i <= si:
		var pair: Array = row.slice(i, mini(i + 2, si + 1))
		out.append({"x0": float(pair[0][1]), "x1": float(pair[-1][1]) + float(pair[-1][2]), "label": names.call(pair)})
		i += 2
	if si + 1 < row.size():
		var rest: Array = row.slice(si + 1)
		out.append({"x0": float(rest[0][1]), "x1": maxf(15.0, float(rest[-1][1]) + float(rest[-1][2])), "label": names.call(rest)})
	return out

## Over the key rulers: the exact key under the pointer in every keyboard row.
func _get_tooltip(at: Vector2) -> String:
	if at.x < L or at.x > size.x - R or (at.y > T and at.y < size.y - B): return ""
	var unit := u_of(at.x) * 15.0
	var words := []
	var row_names := ["数字行", "上排", "中排", "下排"]
	var rows: Array = KB.rows(KB.layout)
	for r in rows.size():
		for k in rows[r]:
			if unit >= float(k[1]) and unit < float(k[1]) + float(k[2]):
				words.append("%s %s" % [row_names[r], "Shift" if str(k[0]).begins_with("Shift") else KB.label(k[0])])
	return "第 %.2f 键位：%s" % [unit, "，".join(words)] if not words.is_empty() else "第 %.2f 键位（键盘外）" % unit
