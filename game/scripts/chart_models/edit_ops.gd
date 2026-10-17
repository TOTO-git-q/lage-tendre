extends RefCounted
## Editing operations shared by the timeline, inspector, context menus, popovers and tests.
## Everything ends in one document.edit() transaction (one undo step, rules of SPEC §2).

const Adapter = preload("res://scripts/chart_models/track_adapter.gd")
const Shape = preload("res://scripts/chart_models/track_shape.gd")
const KEYS := "ASDFGHJKL;'"
const FALL := 1.3

static func key_x(k: int) -> float: return (2.25 + k) / 15.0
static func key_of(x: float) -> int: return clampi(roundi(x * 15.0 - 2.25), 0, 10)
static func key_name(k: int) -> String: return KEYS[k] if k >= 0 and k <= 10 else "?"

static func note_key(n: Dictionary) -> int:
	var k := int(n.get("k", -1))
	return k if k >= 0 and k <= 10 else -1

## Lifetimes [on, off] of a track from the validated timeline.
static func lifetimes(doc, id: int) -> Array:
	var out := []
	for s in doc.core.tl.get(id, []):
		if s.type == "on": out.append([float(s.t), INF])
		elif s.type == "off" and not out.is_empty(): out[-1][1] = float(s.t)
	return out

static func alive_over(doc, id: int, t0: float, t1: float) -> bool:
	for r in lifetimes(doc, id):
		if t0 >= r[0] - SU.EPS and t1 <= r[1] + SU.EPS: return true
	return false

static func roles(doc) -> Dictionary:
	var carriers := {}
	for n in doc.raw.get("notes", []): carriers[int(n.light)] = carriers.get(int(n.light), 0) + 1
	return carriers

## Where can a note at time t on key k (with hold length dur) live? Prefers `prefer`, then
## note-carrying tracks. Returns {ok, light, u, k} or {ok:false, reason} in plain Chinese.
static func placement(doc, t: float, k: int, dur: float = 0.0, prefer: int = -1, locked: Dictionary = {}, hidden: Dictionary = {}) -> Dictionary:
	if k < 0 or k > 10: return {"ok": false, "reason": "超出键盘范围"}
	var kx := key_x(k)
	var carriers := roles(doc)
	var ids: Array = doc.core.tl.keys()
	ids.sort_custom(func(a, b):
		if a == prefer: return true
		if b == prefer: return false
		return carriers.get(a, 0) > carriers.get(b, 0))
	var reason := "%s 键在这里没有轨道覆盖" % key_name(k)
	for id in ids:
		if hidden.get(id, false): continue
		var st: Dictionary = doc.state_at(doc.core.tl[id], t)
		if not st.alive: continue
		if kx < st.x - st.w / 2.0 - SU.KEY_PAD or kx > st.x + st.w / 2.0 + SU.KEY_PAD: continue
		if locked.get(id, false): reason = "轨道 %d 已锁定" % id; continue
		if not alive_over(doc, id, t - FALL, t + dur):
			reason = ("长按结束前轨道 %d 已消失" % id) if alive_over(doc, id, t - FALL, t) else ("轨道 %d 需要从落下前 1.3 秒就存在" % id)
			continue
		return {"ok": true, "light": id, "u": Adapter.num(clampf((kx - st.x) / maxf(1e-6, st.w) + 0.5, 0.0, 1.0)), "k": k}
	return {"ok": false, "reason": reason}

## Plain-language reason for a refused document edit.
static func explain(result: Dictionary) -> String:
	if not result.has("error"): return ""
	var e := str(result.error)
	var detail := ""
	if result.has("reason"): detail = str(result.reason)
	if result.has("detail") and result.detail is Dictionary: detail = str(result.detail.get("reason", ""))
	var table := {
		"chord notes closer than one key": "同一时刻同一轨道的音符相距不足一键",
		"chord larger than 3": "和弦超过三个音",
		"fewer key centres than chord notes": "轨道太窄，容不下这么多和弦音",
		"w < one key width": "轨道宽度小于一键",
		"interval leaves the line": "轨道超出判定线两端",
		"no key centre inside the light": "轨道内没有任何键的中心",
		"starts inside the previous sweep": "关键帧落在上一段移动之中（踏板/闪光事件不能被移动跨过）",
		"light is not alive": "轨道此时不存在",
		"light is already alive": "轨道已经存在",
		"sweep needs dur": "移动需要大于 0 的时长",
		"landing key is outside live track": "音符的落键不在轨道内",
		"track must be continuously alive": "轨道必须从音符落下前 1.3 秒一直存在到音符结束",
		"hold needs dur": "长按需要时长",
		"unknown light": "音符所在的轨道不存在",
	}
	for key in table:
		if key in detail: return table[key] + _note_suffix(result)
	match e:
		"stale revision": return "谱面刚被修改，请重试"
		"track is locked": return "轨道已锁定"
		"stop or finish the Claude turn before manual edits": return "助手正在修改谱面，请先停止或等它完成"
		"version operation in progress": return "版本操作进行中"
		"nothing to undo": return "没有可撤销的操作"
		"nothing to redo": return "没有可重做的操作"
	return (e + (" · " + detail if not detail.is_empty() else "")).left(120)

static func _note_suffix(result: Dictionary) -> String:
	if result.get("detail", null) is Dictionary and result.detail.has("note"): return "（音符 #%d）" % int(result.detail.note)
	return ""

## ---------------------------------------------------------------- notes
static func motion_key(n: Dictionary) -> String:
	return "%.6f|%d|%d" % [float(n.t), int(n.light), int(n.get("k", -1))]

## Move (or duplicate) notes by dt seconds and dk keys. Returns {ok, ops, ext, preview, reason}.
static func move_notes(doc, ids: Array, dt: float, dk: int, duplicate := false, locked: Dictionary = {}) -> Dictionary:
	var ops := []; var preview := []; var ok := true; var reason := ""
	var ext: Dictionary = doc.ext.duplicate(true)
	var moving := {}
	for i in ids: moving[int(i)] = true
	for i in ids:
		var n: Dictionary = doc.raw.notes[int(i)]
		var k0 := note_key(n)
		if k0 < 0: k0 = key_of(float(doc.state_at(doc.core.tl.get(int(n.light), []), float(n.t)).x))
		var nt: float = maxf(0.0, float(n.t) + dt); var nk := k0 + dk
		var dur := float(n.get("dur", 0.0)) if n.get("kind", "tap") == "hold" else 0.0
		var place := placement(doc, nt, nk, dur, int(n.light), locked)
		preview.append({"i": int(i), "t": nt, "k": nk, "ok": place.ok, "reason": place.get("reason", "")})
		if not place.ok:
			ok = false; reason = place.reason; continue
		var value := {"t": Adapter.num(nt), "k": nk, "u": place.u, "light": place.light}
		if duplicate:
			var copy := n.duplicate(true); copy.merge(value, true)
			ops.append({"target": "notes", "op": "add", "value": copy})
		else:
			ops.append({"target": "notes", "op": "update", "index": int(i), "value": value})
		var old_key := motion_key(n); var moved := n.duplicate(); moved.merge(value, true)
		if ext.motions.has(old_key):
			ext.motions[motion_key(moved)] = ext.motions[old_key].duplicate(true)
			if not duplicate: ext.motions.erase(old_key)
	return {"ok": ok, "ops": ops, "ext": ext, "preview": preview, "reason": reason}

static func delete_notes(doc, ids: Array) -> Dictionary:
	var sorted := ids.duplicate(); sorted.sort(); sorted.reverse()
	var ops := []; var ext: Dictionary = doc.ext.duplicate(true)
	for i in sorted:
		ops.append({"target": "notes", "op": "delete", "index": int(i)})
		ext.motions.erase(motion_key(doc.raw.notes[int(i)]))
	return {"ops": ops, "ext": ext}

static func copy_notes(doc, ids: Array) -> Array:
	var clip := []; var t0 := INF
	for i in ids: t0 = minf(t0, float(doc.raw.notes[int(i)].t))
	for i in ids:
		var n: Dictionary = doc.raw.notes[int(i)].duplicate(true)
		var entry := {"note": n, "dt": float(n.t) - t0, "motion": doc.ext.motions.get(motion_key(n), null)}
		clip.append(entry)
	return clip

static func paste_notes(doc, clip: Array, at: float, locked: Dictionary = {}) -> Dictionary:
	var ops := []; var ext: Dictionary = doc.ext.duplicate(true)
	for c in clip:
		var n: Dictionary = c.note.duplicate(true)
		var k := note_key(n)
		if k < 0: continue
		var t := at + float(c.dt)
		var dur := float(n.get("dur", 0.0)) if n.get("kind", "tap") == "hold" else 0.0
		var place := placement(doc, t, k, dur, int(n.light), locked)
		if not place.ok: return {"ok": false, "reason": place.reason + "（%s 键 · %.3f s）" % [key_name(k), t]}
		n.merge({"t": Adapter.num(t), "u": place.u, "light": place.light, "k": k}, true)
		ops.append({"target": "notes", "op": "add", "value": n})
		if c.motion != null: ext.motions[motion_key(n)] = c.motion.duplicate(true)
	return {"ok": true, "ops": ops, "ext": ext}

## ---------------------------------------------------------------- tracks as shapes
static func track_events(doc, id: int) -> Array:
	var out := []
	for e in doc.raw.lights:
		if int(e.get("id", -1)) == id: out.append(e)
	return out

## Editor shapes of a track: the session memo (keeps nodes the user added), else the sidecar
## shape, else rebuilt from the light events at the current density.
static func shapes_for(doc, id: int, events = null, sig: String = "") -> Array:
	if events == null: events = track_events(doc, id)
	if sig.is_empty(): sig = Adapter.signature(events)
	if doc.shape_memo.has(sig):
		var out := []
		for s in doc.shape_memo[sig]: out.append(s.clone())
		return out
	var side: Dictionary = doc.ext.get("shapes", {}).get(str(id), {})
	if not side.is_empty() and side.get("signature", "") == sig:
		var out := []
		for d in side.get("shapes", []): out.append(Shape.from_dict(d))
		return out
	return Adapter.from_events(doc.raw.lights, id, doc.core.end_time)

## Write a track's shapes back: today's events (lean, exact when representable, envelope
## otherwise) + sidecar for shapes the engine cannot read yet + notes re-seated on their keys.
static func commit_shapes(doc, id: int, shapes: Array, label: String, coalesce: String = "") -> Dictionary:
	var events := []
	var inherit := {"a": -1.0, "tint": -1}
	var exact := true; var reasons := []
	var ordered := shapes.duplicate()
	ordered.sort_custom(func(a, b): return a.t_range()[0] < b.t_range()[0])
	for s in ordered:
		s.id = id
		var out := Adapter.to_events(s, inherit, grid_step(doc, s.t_range()[0]))
		events.append_array(out.events); inherit = out.final
		if not out.exact: exact = false; reasons.append(out.reason)
	var ops := []
	var indices := []
	for i in doc.raw.lights.size():
		if int(doc.raw.lights[i].get("id", -1)) == id: indices.append(i)
	indices.reverse()
	for i in indices: ops.append({"target": "lights", "op": "delete", "index": i})
	for e in events: ops.append({"target": "lights", "op": "add", "value": e})
	var after := []
	for e in doc.raw.lights:
		if int(e.get("id", -1)) != id: after.append(e)
	after.append_array(events)
	ops.append_array(Adapter.reseat_ops(doc, id, after))
	var ext: Dictionary = doc.ext.duplicate(true)
	var sig := Adapter.signature(events)
	if exact: ext.shapes.erase(str(id))
	else:
		var dicts := []
		for s in ordered: dicts.append(s.to_dict())
		ext.shapes[str(id)] = {"signature": sig, "shapes": dicts, "approximated": true, "reason": "；".join(reasons)}
	var result: Dictionary = doc.edit({"expected_revision": doc.revision(), "label": label, "ops": ops, "ext": ext, "coalesce": coalesce})
	if not result.has("error"):
		var memo := []
		for s in ordered: memo.append(s.clone())
		doc.shape_memo[sig] = memo
	result["exact"] = exact; result["reasons"] = reasons
	return result

static func grid_step(doc, t: float) -> float:
	return doc.position(t).beat_seconds / 2.0

static func next_track_id(doc) -> int:
	var top := -1
	for e in doc.raw.lights: top = maxi(top, int(e.get("id", -1)))
	return top + 1

static func create_track(doc, kind: String, x0: float, x1: float, t0: float, t1: float, a: float = 0.5, tint: int = -1) -> Dictionary:
	var id := next_track_id(doc)
	var s = Shape.preset(kind, x0, x1, t0, t1)
	s.id = id
	s.props = [{"t": t0, "a": a, "tint": tint}]
	if kind == "rect": s.props.append({"t": t1, "a": a, "tint": tint})
	var result := commit_shapes(doc, id, [s], "创建轨道" if kind == "rect" else "创建形状轨道")
	result["id"] = id
	return result

static func delete_track(doc, id: int) -> Dictionary:
	var count := int(roles(doc).get(id, 0))
	if count > 0: return {"error": "轨道上还有 %d 个音符，先移走或删除它们" % count}
	var ops := []
	var indices := []
	for i in doc.raw.lights.size():
		if int(doc.raw.lights[i].get("id", -1)) == id: indices.append(i)
	indices.reverse()
	for i in indices: ops.append({"target": "lights", "op": "delete", "index": i})
	var ext: Dictionary = doc.ext.duplicate(true); ext.shapes.erase(str(id))
	return doc.edit({"expected_revision": doc.revision(), "label": "删除轨道 %d" % id, "ops": ops, "ext": ext})

## Set opacity / tint over the whole track (every keyframe), as one step.
static func set_track_props(doc, id: int, values: Dictionary, label: String, coalesce: String = "") -> Dictionary:
	var shapes := shapes_for(doc, id)
	for s in shapes:
		for p in s.props:
			for k in values: p[k] = values[k]
	return commit_shapes(doc, id, shapes, label, coalesce)

## bar.beat for display: exact grid positions as they are, off-grid times (sub-ms drift in
## legacy charts) rounded to the nearest 1/48 beat and marked with ≈.
static func pretty(doc, t: float) -> String:
	var p: Dictionary = doc.position(t)
	var word: String = str(p.bar_beat).trim_suffix("+0/1")
	if not word.contains("/") or int(word.get_slice("/", 1)) <= 48: return word
	var bar_start: float = doc.seconds("%d.1" % int(p.bar))
	if is_nan(bar_start): return word
	var q: float = p.beat_seconds / 48.0
	var snapped := bar_start + roundf((t - bar_start) / q) * q
	return ("" if absf(snapped - t) < 0.0005 else "≈") + str(doc.position(snapped).bar_beat)
