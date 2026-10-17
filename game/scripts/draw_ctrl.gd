## A Control whose drawing is delegated to `painter` (Callable(control)).
extends Control

var painter: Callable

func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
