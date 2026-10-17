extends Container
## Explicit pane dimensions are the layout contract. Child text/content minima
## stay inside the pane and cannot push neighbouring panes or the parent window.
## Scrollable content retains its own vertical minimum inside its ScrollContainer.
func _init() -> void:
	clip_contents = true

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var style := get_theme_stylebox("panel", theme_type_variation if not theme_type_variation.is_empty() else "PanelContainer")
		var rect := Rect2(style.get_offset(), (size - style.get_minimum_size()).max(Vector2.ZERO))
		for child in get_children():
			if child is Control: fit_child_in_rect(child, rect)
	if what == NOTIFICATION_THEME_CHANGED:
		queue_sort(); queue_redraw()

func _draw() -> void:
	draw_style_box(get_theme_stylebox("panel", theme_type_variation if not theme_type_variation.is_empty() else "PanelContainer"), Rect2(Vector2.ZERO, size))
