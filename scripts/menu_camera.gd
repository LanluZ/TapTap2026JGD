extends Node3D
## 场景：scenes/menu.tscn 主菜单。作用：3D 背景——驱动球体（含描边壳）自转，相机轻微上下浮动。

@onready var _pivot: Node3D = $SpherePivot
@onready var _camera: Camera3D = $Camera3D

var _time := 0.0

func _process(delta: float) -> void:
	_time += delta
	_pivot.rotate_y(delta * 0.4)
	_camera.position.y = sin(_time * 0.8) * 0.2
