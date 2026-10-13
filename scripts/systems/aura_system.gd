class_name AuraSystem
extends System
## #6 光环（§5）：radius 半径内按 target_mask 施加/刷新 Effect（覆盖最新值并重置
## 持续时间），并对已挂 Effect 倒计时、过期回收（§5 的“过期回收”）。
## 目标位置经 EntityLocator 解析：敌人看路径弧长，工厂看格子中心。


func tick(world, dt: float) -> void:
	# —— 1) 效果倒计时 + 过期回收（先收集再移除，避免遍历中改字典）——
	var expired_ids: Array = []
	for id in world.query(&"Effect"):
		if not world.is_alive(id):
			continue
		var eff = world.get_component(id, &"Effect")
		eff.tick_down(dt)
		if eff.is_empty():
			expired_ids.append(id)
	for id in expired_ids:
		world.remove_component(id, &"Effect")
	# —— 2) 施加/刷新 ——
	for aid in world.query(&"Aura"):
		if not world.is_alive(aid):
			continue
		var aura = world.get_component(aid, &"Aura")
		var origin = EntityLocator.position(world, aid)
		if origin == null:
			continue
		var def: Dictionary = world.config.get_effect(aura.effect_id)
		if def.is_empty():
			continue # get_effect 已报错
		var stat_id: StringName = def["stat_id"]
		var value: float = def["value"]
		var duration: float = def["duration"]
		var mask: int = aura.target_mask
		if (mask & GameConfig.MASK_ENEMY) != 0:
			_apply_to_group(world, aid, origin, aura.radius, &"Enemy", stat_id, value, duration)
		if (mask & GameConfig.MASK_FACTORY) != 0:
			_apply_to_group(world, aid, origin, aura.radius, &"Factory", stat_id, value, duration)


func _apply_to_group(world, source_id: int, origin: Vector2, radius: float,
		group_type: StringName, stat_id: StringName, value: float, duration: float) -> void:
	for tid in world.query(group_type):
		if tid == source_id:
			continue # 不作用于自身
		if not world.is_alive(tid):
			continue
		var pos = EntityLocator.position(world, tid)
		if pos == null:
			continue
		if origin.distance_to(pos) > radius:
			continue
		var eff = world.get_component(tid, &"Effect")
		if eff == null:
			eff = world.add_component(tid, Effect.new())
		eff.apply(stat_id, value, duration)
