## Screen-local selection shared by keyboard and mouse. Never handles gameplay input.
extends Control

signal selection_changed(index: int)

var rows: Array[Dictionary] = []
var _hover_connections: Array[Dictionary] = []
var selected := 0
var _rect := Rect2()
var _from := Rect2()
var _target := Rect2()
var _elapsed := 0.12
var _placed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30

func clear() -> void:
	for connection in _hover_connections:
		if is_instance_valid(connection.control):
			connection.control.mouse_entered.disconnect(connection.callback)
	_hover_connections.clear()
	rows.clear()
	selected = 0

func _watch_hover(control: Control, index: int) -> void:
	var callback := func():
		if is_visible_in_tree(): select(index)
	control.mouse_entered.connect(callback)
	_hover_connections.append({"control": control, "callback": callback})

func add_row(control: Control, action := Callable(), adjust := Callable()) -> void:
	var index := rows.size()
	rows.append({"control": control, "action": action, "adjust": adjust})
	_watch_hover(control, index)
	# Containers themselves can be covered by their interactive children.
	for child in control.find_children("*", "Control", true, false):
		if child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_watch_hover(child, index)

func available(index: int) -> bool:
	if index < 0 or index >= rows.size(): return false
	var control: Control = rows[index].control
	return is_instance_valid(control) and not control.is_queued_for_deletion() and control.is_visible_in_tree() and not (control is BaseButton and control.disabled)

func select(index: int, instant := false) -> void:
	if not available(index): return
	var changed := selected != index
	selected = index
	if instant: _placed = false
	for i in rows.size():
		if is_instance_valid(rows[i].control):
			var tint := Color(1, 1, 1, 1.0 if i == selected else 0.72)
			rows[i].control.self_modulate = tint
			# self_modulate leaves reveal animation alpha intact, but does not
			# propagate to the labels/buttons inside a settings or title row.
			for child in rows[i].control.find_children("*", "Control", true, false):
				child.self_modulate = tint
	if changed: selection_changed.emit(index)

func move_selection(direction: int) -> void:
	if rows.is_empty(): return
	for offset in range(1, rows.size() + 1):
		var index := posmod(selected + direction * offset, rows.size())
		if available(index):
			select(index)
			return

func activate() -> void:
	if available(selected) and rows[selected].action.is_valid(): rows[selected].action.call()

func adjust(direction: int, fast: bool) -> void:
	if available(selected) and rows[selected].adjust.is_valid(): rows[selected].adjust.call(direction, fast)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if not available(selected): move_selection(1)
	if not available(selected): return
	var control: Control = rows[selected].control
	var rect := Rect2(control.global_position - global_position, control.size).grow(5.0)
	if not _placed:
		_rect = rect; _target = rect; _placed = true
	elif not rect.is_equal_approx(_target):
		_from = _rect; _target = rect; _elapsed = 0.0
	_elapsed = minf(_elapsed + delta, 0.12)
	if _elapsed < 0.12:
		var weight := 1.0 - pow(1.0 - _elapsed / 0.12, 3.0)
		_rect = Rect2(_from.position.lerp(_target.position, weight), _from.size.lerp(_target.size, weight))
	else: _rect = _target
	queue_redraw()

func _draw() -> void:
	if not _placed or not available(selected): return
	draw_rect(_rect, Color(1, 1, 1, 0.055))
	draw_rect(_rect, Color(1, 1, 1, 0.65), false, 1.0)
