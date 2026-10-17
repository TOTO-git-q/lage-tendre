## One draw layer of the renderer; the renderer assigns `painter` (a Callable(layer)) and a blend material.
extends Node2D

var painter: Callable

func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
