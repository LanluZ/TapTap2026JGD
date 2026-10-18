extends SceneTree
## 表现层血量条验证（headless，非视觉）：
##   敌人精灵下挂 HpBar / 位置压在精灵顶边上方 / 比例随 Health 变化 / 非敌无条 / 销毁随精灵移除。
##
## 运行：
##   godot --headless --path <项目目录> -s res://tests/entity_layer_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const DT := 0.1 # 逻辑步长（秒），与 smoke.gd 一致

const EntityLayerScript = preload("res://scripts/views/entity_layer.gd")
const BootstrapScript = preload("res://scripts/bootstrap.gd")

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _init() -> void:
	var code := _run()
	_finished = true
	quit(code)


## 兜底：若 quit() 在 _init 阶段未生效，首个逻辑帧强制退出。
func _process(_dt: float) -> bool:
	return _finished


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


func _run() -> int:
	print("======== 表现层血量条测试 ========")
	var config = GameConfig.load_all()
	if config == null:
		printerr("配置加载失败，后续测试无法进行")
		return 1
	var w = BootstrapScript.build_world(config, &"level_1")
	w.state.waves_running = false # 关掉波次刷怪，隔离被测对象
	var layer = EntityLayerScript.new()
	layer.setup(w)

	# 敌人实体（PathFollower 提供位置，Health 提供血量，Enemy 提供贴图类型）
	var id: int = w.create_entity()
	var pf := PathFollower.new()
	pf.path_id = config.get_level(&"level_1")["path_id"]
	pf.speed = 90.0
	w.add_component(id, pf)
	var hp := Health.new()
	hp.max_hp = 30.0
	hp.hp = 30.0
	w.add_component(id, hp)
	var en := Enemy.new()
	en.etype = &"slime"
	w.add_component(id, en)
	# 非敌人实体（占位图，不该有血条）
	var other: int = w.create_entity()

	layer.call("_process", 0.016)
	var sprites = layer.get("_sprites")
	_ok(sprites.has(id), "敌人实体生成精灵视图")
	_ok(sprites.has(other), "非敌人实体生成占位精灵")
	if not sprites.has(id):
		printerr("精灵未生成，后续断言无法进行")
		return _failures
	var spr = sprites[id]
	var children: Array = spr.get_children()
	_ok(children.size() == 1, "敌人精灵下挂 1 个子节点（血条），实际 %d" % children.size())
	if children.is_empty():
		return _failures
	var bar = children[0]
	_ok(bar.get("entity_id") == id, "子节点是 HpBar（entity_id=%s 匹配 %d）" % [bar.get("entity_id"), id])
	_ok(is_equal_approx(float(bar.get("_ratio")), 1.0), "满血初始比例 1.0（实际 %s）" % bar.get("_ratio"))

	# 血条底边必须在精灵顶边之上（都在精灵局部坐标系比；AnimatedSprite2D 无 get_rect，取帧贴图）
	_ok(spr is AnimatedSprite2D, "敌人精灵是 AnimatedSprite2D（slime 有帧动画）")
	var frame_tex: Texture2D = (spr as AnimatedSprite2D).sprite_frames.get_frame_texture(&"move", 0)
	var sprite_top: float = -frame_tex.get_size().y * 0.5
	var bar_bottom: float = float(bar.position.y) + float(bar.bar_h) * 0.5
	_ok(bar_bottom <= sprite_top,
		"血条底边在精灵顶边上方（bar_bottom=%.1f ≤ sprite_top=%.1f）" % [bar_bottom, sprite_top])
	_ok(is_equal_approx(float(bar.get("bar_w")), frame_tex.get_size().x),
		"条宽 = 帧贴图宽（%.1f）" % frame_tex.get_size().x)

	# 血量变化 → 比例刷新（_process 值变才重绘）
	hp.hp = 15.0
	bar.call("_process", 0.016)
	_ok(is_equal_approx(float(bar.get("_ratio")), 0.5), "血量减半后比例 0.5（实际 %s）" % bar.get("_ratio"))
	hp.hp = 0.0
	bar.call("_process", 0.016)
	_ok(is_equal_approx(float(bar.get("_ratio")), 0.0), "血量归零后比例 0.0（实际 %s）" % bar.get("_ratio"))

	# 非敌人无血条
	var other_children: Array = (sprites[other] as Node2D).get_children()
	_ok(other_children.is_empty(), "非敌人精灵下无血条，实际 %d 个子节点" % other_children.size())

	# 销毁：entity_destroyed → 精灵（连带血条）移除
	w.destroy_entity(id)
	w.tick(DT)
	_ok(not sprites.has(id), "敌人销毁后精灵记录移除")

	print("======== 结果: %d/%d 通过，%d 失败 ========" % [_checks - _failures, _checks, _failures])
	return _failures
