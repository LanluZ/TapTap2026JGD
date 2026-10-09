extends Button
## 按钮动画：悬停放大+提亮，按下缩小，抬起回弹。
## 用 button_down/button_up 而非 pressed——pressed 在默认 release 模式下松手才发。

@export var hover_scale := 1.05
@export var press_scale := 0.92

const HOVER_TINT := Color(1.1, 1.1, 1.1)
const IDLE_TINT := Color(1, 1, 1)
const PRESS_TINT := Color(0.85, 0.85, 0.85)

var _tween: Tween

func _ready() -> void:
	resized.connect(_update_pivot)
	_update_pivot()
	mouse_entered.connect(_animate.bind(hover_scale, HOVER_TINT, 0.15, Tween.TRANS_BACK))
	mouse_exited.connect(_animate.bind(1.0, IDLE_TINT, 0.2, Tween.TRANS_QUAD))
	button_down.connect(_animate.bind(press_scale, PRESS_TINT, 0.06, Tween.TRANS_QUAD))
	button_up.connect(_animate.bind(hover_scale, HOVER_TINT, 0.12, Tween.TRANS_BACK))

func _update_pivot() -> void:
	pivot_offset = size / 2.0

func _animate(scale_target: float, tint: Color, duration: float, trans: int) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE * scale_target, duration) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "self_modulate", tint, duration)