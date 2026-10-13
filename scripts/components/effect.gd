class_name Effect
extends Component
## BUFF/DEBUFF 实例（§4：stat_id / value / duration）。
## 设计说明（对 §3 的实现取舍）：World 按类型每实体只存一个组件实例，
## 而实体可能同时受多个来源、不同数值的效果，故本组件作为条目容器：
## entries = stat_id(StringName) -> {"value": float, "duration": float}。
## AuraSystem 施加/刷新并倒计时，过期条目移除（§5 #6/#11）。


var entries: Dictionary = {}


func has_stat(stat_id: StringName) -> bool:
	return entries.has(stat_id)


func get_value(stat_id: StringName) -> float:
	if entries.has(stat_id):
		return float(entries[stat_id]["value"])
	return 0.0


func get_duration(stat_id: StringName) -> float:
	if entries.has(stat_id):
		return float(entries[stat_id]["duration"])
	return 0.0


## 施加或刷新（覆盖为最新值并重置持续时间）。
func apply(stat_id: StringName, value: float, duration: float) -> void:
	entries[stat_id] = {"value": value, "duration": duration}


## 倒计时，返回本帧到期被移除的 stat_id 列表。
func tick_down(dt: float) -> Array:
	var expired: Array = []
	for k in entries:
		var e: Dictionary = entries[k]
		var d: float = float(e["duration"]) - dt
		if d <= 0.0:
			expired.append(k)
		else:
			e["duration"] = d
	for k in expired:
		entries.erase(k)
	return expired


func is_empty() -> bool:
	return entries.is_empty()
