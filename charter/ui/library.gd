extends Control
## Song library, like the conversation list of the Claude app: one clean row per song (cover,
## title, artist, its game difficulties as chips), its editor working copies listed underneath.
## Click a row or a chip to open it; right-click for export and the game song list.

signal open_dir(dir: String)
signal action(what: String, dir: String)

const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Lib = preload("res://song_library.gd")
const SONG_H := 64.0
const COPY_H := 32.0
const HEAD_H := 30.0

var root := ""
var current := ""          # the open song folder
var filter := ""
var groups: Array = []
var rows: Array = []       # {kind: song|copy|head, group, dir, y, h, chips: [[Rect2, dir]]}
var hover := -1
var hover_chip := ""
var menu := PopupMenu.new()
var _menu_dir := ""
var _covers: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover = -1; hover_chip = ""; queue_redraw())
	add_child(menu)
	menu.id_pressed.connect(func(id): action.emit(["open", "export_package", "export_chart", "add_to_game", "reveal", "settings"][id], _menu_dir))

func rescan() -> void:
	groups = Lib.scan(root) if not root.is_empty() else []
	rebuild()

func rebuild() -> void:
	rows = []
	var y := 4.0
	var q := filter.strip_edges().to_lower()
	for g in groups:
		var dirs := []
		for d in g.diffs: dirs.append(d.dir)
		for c in g.copies: dirs.append(c.dir)
		var hay := (str(g.title) + " " + str(g.artist) + " " + " ".join(dirs)).to_lower()
		if not q.is_empty() and not q in hay: continue
		if g.get("other", false):
			rows.append({"kind": "head", "group": g, "dir": "", "y": y, "h": HEAD_H}); y += HEAD_H
		else:
			var first: String = g.diffs[0].dir if not g.diffs.is_empty() else (g.copies[0].dir if not g.copies.is_empty() else "")
			rows.append({"kind": "song", "group": g, "dir": first, "y": y, "h": SONG_H, "chips": []}); y += SONG_H
		for c in g.copies:
			rows.append({"kind": "copy", "group": g, "dir": c.dir, "item": c, "y": y, "h": COPY_H}); y += COPY_H
		y += 6
	custom_minimum_size.y = y
	queue_redraw()

func _row_at(p: Vector2) -> int:
	for i in rows.size():
		if p.y >= rows[i].y and p.y < rows[i].y + rows[i].h: return i
	return -1

func _chip_at(i: int, p: Vector2) -> String:
	if i < 0 or rows[i].kind != "song": return ""
	for c in rows[i].get("chips", []):
		if c[0].has_point(p): return c[1]
	return ""

func _cover(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _covers.has(path):
		var img := Image.load_from_file(path)
		if img != null:
			var s := mini(img.get_width(), img.get_height())
			img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
			img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		_covers[path] = ImageTexture.create_from_image(img) if img != null else null
	return _covers[path]

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _row_at(e.position); var hc := _chip_at(h, e.position)
		if h != hover or hc != hover_chip: hover = h; hover_chip = hc; queue_redraw()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 and rows[h].kind != "head" else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed:
		var i := _row_at(e.position)
		if i < 0 or rows[i].kind == "head": return
		var dir: String = _chip_at(i, e.position)
		if dir.is_empty(): dir = rows[i].dir
		if dir.is_empty(): return
		if e.button_index == MOUSE_BUTTON_LEFT: open_dir.emit(dir); accept_event()
		elif e.button_index == MOUSE_BUTTON_RIGHT: open_menu(dir, get_screen_position() + e.position); accept_event()

func open_menu(dir: String, at: Vector2) -> void:
	_menu_dir = dir
	menu.clear()
	menu.add_item("打开 " + dir, 0)
	menu.add_item("歌曲设置（BPM、偏移、歌名）", 5)
	menu.add_separator()
	menu.add_item("导出歌曲包（.zip）…", 1)
	menu.add_item("导出谱面 chart.json…", 2)
	menu.add_item("加入游戏歌单…", 3)
	menu.add_separator()
	menu.add_item("在资源管理器中显示", 4)
	menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))

func _draw() -> void:
	var t := Tokens.tokens()
	var semi := Tokens.font("sans", 600); var sans := Tokens.font("sans")
	for i in rows.size():
		var r: Dictionary = rows[i]
		var g: Dictionary = r.group
		match r.kind:
			"head":
				draw_string(semi, Vector2(10, r.y + 21), str(g.title), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, t.muted)
			"song":
				var rect := Rect2(4, r.y + 2, size.x - 8, r.h - 4)
				var is_open := false
				for d in g.diffs:
					if d.dir == current:
						is_open = true
				if i == hover and hover_chip.is_empty(): draw_style_box(Tokens.box(t.hover, 10), rect)
				var cover := _cover(str(g.cover))
				var cr := Rect2(12, r.y + 10, 44, 44)
				if cover != null: draw_texture_rect(cover, cr, false)
				else:
					draw_style_box(Tokens.box(t.s3, 8, t.border), cr)
					Icons.draw(self, "wave", cr.get_center(), 18, t.faint)
				draw_style_box(Tokens.box(Color.TRANSPARENT, 6, t.border_strong), cr)
				var x0 := 68.0
				draw_string(semi, Vector2(x0, r.y + 27), str(g.title), HORIZONTAL_ALIGNMENT_LEFT, size.x - x0 - 10, Tokens.BODY, t.clay if is_open else t.text)
				# artist, then difficulty chips on the same line when they fit
				var chips := []
				var cx := x0
				var cy: float = r.y + 36
				for d in g.diffs:
					var label: String = str(d.version) if not str(d.version).is_empty() else d.dir
					if int(d.level) > 0: label += " " + str(d.level)
					var w := semi.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS).x + 14
					var chip := Rect2(cx, cy, w, 20)
					var on: bool = d.dir == current
					var hot: bool = hover_chip == d.dir
					draw_style_box(Tokens.box(t.clay if on else (t.clay_tint if hot else t.s3), 10, Color.TRANSPARENT if on else t.border), chip)
					draw_string(semi, Vector2(cx + 7, cy + 14.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, Color.WHITE if on else (t.clay if hot else t.muted))
					chips.append([chip, d.dir]); cx += w + 6
				if not str(g.artist).is_empty():
					draw_string(sans, Vector2(cx + (4 if not chips.is_empty() else 0), cy + 15), str(g.artist), HORIZONTAL_ALIGNMENT_LEFT, maxf(0, size.x - cx - 14), Tokens.BODY, t.faint)
				r["chips"] = chips
			"copy":
				var rect := Rect2(4, r.y + 1, size.x - 8, r.h - 2)
				var on: bool = r.dir == current
				if on: draw_style_box(Tokens.box(t.clay_tint, 8), rect)
				elif i == hover: draw_style_box(Tokens.box(t.hover, 8), rect)
				var x := 68.0 if not g.get("other", false) else 14.0
				Icons.draw(self, "branch", Vector2(x + 8, r.y + r.h / 2.0), 16, t.clay if on else t.faint)
				draw_string(sans, Vector2(x + 24, r.y + 21), str(r.dir), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 110, Tokens.BODY, t.clay if on else t.text)
				var tag := "工作副本" if not g.get("other", false) else ""
				if not tag.is_empty():
					var tw := sans.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS).x
					draw_string(sans, Vector2(size.x - tw - 14, r.y + 21), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, t.faint)

func _get_tooltip(at: Vector2) -> String:
	var i := _row_at(at)
	if i < 0 or rows[i].kind == "head": return ""
	var dir := _chip_at(i, at)
	if dir.is_empty(): dir = rows[i].dir
	return "打开 %s（右键：导出、加入游戏歌单）" % dir
