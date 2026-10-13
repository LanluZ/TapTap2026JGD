extends Control
## 关卡 HUD：资源条（零件/特殊材料/电力/水/矿）、波次进度、路径敌人数/失败上限计数。
## 只做展示：数据由调用方注入，本脚本不引用逻辑层任何类型。

const RESOURCE_IDS: Array[String] = ["parts", "special", "power", "water", "ore"]

var _values: Dictionary = {}            # 资源 id -> Label（数值位）
var _unknown_warned: Dictionary = {}    # 已警告过的未知资源 id
var _wave_text: Label
var _wave_bar: ProgressBar
var _enemy_text: Label
var _enemy_bar: ProgressBar
var _resolve_attempted := false


func _ready() -> void:
	_resolve()


func _resolve() -> void:
	if _resolve_attempted:
		return
	_resolve_attempted = true
	_wave_text = get_node_or_null("TopBar/Row/WaveBox/WaveText") as Label
	_wave_bar = get_node_or_null("TopBar/Row/WaveBox/WaveBar") as ProgressBar
	_enemy_text = get_node_or_null("TopBar/Row/EnemyBox/EnemyText") as Label
	_enemy_bar = get_node_or_null("TopBar/Row/EnemyBox/EnemyBar") as ProgressBar
	if _wave_text == null or _wave_bar == null or _enemy_text == null or _enemy_bar == null:
		push_error("[HUD] 缺少波次/敌人数节点，检查 main.tscn 中 TopBar/Row 结构")
		return
	_collect_slots()


func _collect_slots() -> void:
	_values.clear()
	var bar := get_node_or_null("TopBar/Row/ResourceBar")
	if bar == null:
		push_error("[HUD] 缺少 ResourceBar 节点")
		return
	for slot in bar.get_children():
		var value := slot.get_node_or_null("VBox/Value") as Label
		if value == null:
			push_warning("[HUD] 资源槽位缺少 Value 标签：%s" % slot.name)
			continue
		_values[String(slot.name).to_lower()] = value
	for id in RESOURCE_IDS:
		if not _values.has(id):
			push_warning("[HUD] 资源槽位缺失：%s" % id)


## 注入资源数值：{ "parts": int, "special": int, "power": int, "water": int, "ore": int }
## 未知 id 只警告一次并忽略，不伪造显示。
func set_resources(resources: Dictionary) -> void:
	_resolve()
	for id in resources:
		if not _values.has(id):
			if not _unknown_warned.has(id):
				push_warning("[HUD] 未知资源 id，忽略显示：%s" % str(id))
				_unknown_warned[id] = true
			continue
		var label := _values[id] as Label
		if label != null:
			label.text = str(resources[id])


## 波次进度：current / total（total<=0 时按 0 处理）
func set_wave_info(current: int, total: int) -> void:
	_resolve()
	if _wave_text == null or _wave_bar == null:
		return
	_wave_text.text = "波次 %d / %d" % [current, total]
	_wave_bar.max_value = max(total, 1)
	_wave_bar.value = clampi(current, 0, max(total, 0))


## 路径敌人数 / 失败上限
func set_enemy_count(count: int, cap: int) -> void:
	_resolve()
	if _enemy_text == null or _enemy_bar == null:
		return
	_enemy_text.text = "路径敌人 %d / %d" % [count, cap]
	_enemy_bar.max_value = max(cap, 1)
	_enemy_bar.value = clampi(count, 0, max(cap, 0))


## 当前已显示的资源数值（只读回查，便于接线自检）
func get_shown_resources() -> Dictionary:
	var out := {}
	for id in _values:
		var label := _values[id] as Label
		out[id] = label.text if label != null else ""
	return out
