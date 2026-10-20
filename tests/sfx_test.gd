extends SceneTree
## headless 验证全局音效（autoload Sfx）：
## 注册项、7 个音频文件可加载、按钮 node_added 自动挂接（悬停/点击 → 播放器拿到流）、
## 禁用按钮不发悬停音、play_if_exists 静态入口、缺音效只警告不伪造播放。
##
## 运行：
##   godot --headless --path <项目目录> -s res://tests/sfx_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 注：`-s` 模式会照常实例化 autoload（game_helper 能注册即为证），本测试直接用
##     /root/Sfx 真单例；不要手动 new 第二个实例——_sfx_hooked meta 会让先接线
##     的实例独占按钮，第二个实例的断言必然落空。

var _checks: int = 0
var _failures: int = 0
var _done: bool = false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_run())
	return true


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


func _summary() -> int:
	print("======== 汇总: %d 项检查, %d 项失败 ========" % [_checks, _failures])
	return _failures


## 清空播放器池（停播 + 摘流），让下一次播放必然落在干净状态
func _reset_pool(sfx: Node) -> Array:
	var pool: Array = []
	for child in sfx.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
			pool.append(child)
	return pool


## 池里是否有播放器拿到指定音效流（按文件名后缀匹配）
func _pool_has(pool: Array, suffix: String) -> bool:
	for p in pool:
		if p.stream != null and String(p.stream.resource_path).ends_with(suffix):
			return true
	return false


func _run() -> int:
	print("======== Sfx 音效自检 ========")

	# 1) autoload 注册项
	var cfg := FileAccess.get_file_as_string("res://project.godot")
	_ok(cfg.contains('Sfx="*res://scripts/ui/sfx.gd"'),
		"project.godot 已注册 autoload Sfx")

	# 2) 真单例已由 -s 模式实例化
	var sfx := root.get_node_or_null("Sfx")
	_ok(sfx != null, "/root/Sfx 单例存在（-s 会实例化 autoload）")
	if sfx == null:
		return _summary()
	var script: GDScript = load("res://scripts/ui/sfx.gd")
	_ok(script != null, "sfx.gd 可加载")
	if script == null:
		return _summary()
	_ok(sfx.get_script() == script, "Sfx 挂的是 sfx.gd")

	# 3) 7 个音频文件全部可加载
	var sounds: Dictionary = script.SOUNDS
	_ok(sounds.size() == 7, "SOUNDS 映射 7 个音效（实际 %d）" % sounds.size())
	for key in sounds:
		var stream := load(sounds[key]) as AudioStream
		_ok(stream != null, "音频可加载: %s" % str(key))

	# 4) 播放器池 6 个
	var pool := _reset_pool(sfx)
	_ok(pool.size() == 6, "播放器池 6 个（实际 %d）" % pool.size())

	# 5) 按钮进树 → 真单例自动挂接；button_down → 点击音
	var btn := Button.new()
	root.add_child(btn)
	_ok(btn.has_meta(&"_sfx_hooked"), "按钮进树自动挂接（meta 已打标）")
	btn.button_down.emit()
	_ok(_pool_has(pool, "点击.ogg"), "button_down 触发点击音")

	# 6) 悬停音
	_reset_pool(sfx)
	btn.mouse_entered.emit()
	_ok(_pool_has(pool, "悬停.ogg"), "mouse_entered 触发悬停音")

	# 7) 禁用按钮不发悬停音
	_reset_pool(sfx)
	btn.disabled = true
	btn.mouse_entered.emit()
	_ok(not _pool_has(pool, "悬停.ogg"), "禁用按钮悬停不发声")
	btn.disabled = false

	# 8) play_if_exists 静态入口：单例在场 → 真播
	_reset_pool(sfx)
	script.play_if_exists("通知")
	_ok(_pool_has(pool, "通知.ogg"), "play_if_exists 单例在场时播放")

	# 9) 缺音效名：不伪造播放、不崩
	_reset_pool(sfx)
	script.play_if_exists("不存在的音效")
	_ok(not _pool_has(pool, ".ogg"), "未定义音效名不播放（只警告）")

	return _summary()
