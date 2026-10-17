extends Node2D
## Only instantiated by demo_tour.gd. A drawn cursor is captured by Movie Maker.
var pulse := 0.0
func _process(dt: float) -> void:
	pulse = maxf(0.0, pulse - dt * 3.5)
	queue_redraw()
func _draw() -> void:
	if pulse > 0.0:
		draw_arc(Vector2.ZERO, 8.0 + (1.0 - pulse) * 15.0, 0, TAU, 40, Color(0.91, 0.65, 0.46, pulse * 0.7), 2.0, true)
	var outline := PackedVector2Array([Vector2(0,0),Vector2(0,25),Vector2(6.4,18.9),Vector2(11,29),Vector2(15.4,27),Vector2(10.8,17.3),Vector2(19,17.3),Vector2(0,0)])
	draw_colored_polygon(outline, Color("17191d"))
	draw_polyline(outline, Color(1,1,1,0.98), 1.6, true)
