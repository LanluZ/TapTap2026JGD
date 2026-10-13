class_name ProductionSystem
extends System
## #5 生产（§5）：按配方推进——输入（含电力，电力是普通资源 §7）存入池中且
## 足够才扣款开产；产出先进 ResourceBuffer；输入不足即停产等待。
## 缓冲按 flush_interval 定期汇入玩家资源池（§7「工厂产出经 ResourceBuffer 定期汇入」）。


func tick(world, dt: float) -> void:
	var state = world.state
	# —— 1) 推进生产 ——
	var buf_bit := Entity.bit_for(&"ResourceBuffer")
	for id in world.query(&"Production"):
		if not world.is_alive(id):
			continue
		if (world.mask_of(id) & buf_bit) == 0:
			continue # 配置校验已要求 Production 蓝图带 ResourceBuffer，防御跳过
		var prod = world.get_component(id, &"Production")
		var buffer = world.get_component(id, &"ResourceBuffer")
		if not prod.active:
			# 扣款开产：输入（含电力）不足 → 不开工，停产待料
			var recipe: Dictionary = world.config.get_recipe(prod.recipe_id)
			if recipe.is_empty():
				continue
			if state.can_afford(recipe["inputs"]):
				if not state.pay(recipe["inputs"]):
					continue
				prod.active = true
				prod.progress = 0.0
		if prod.active:
			prod.progress += dt
			if prod.progress >= prod.interval:
				var recipe: Dictionary = world.config.get_recipe(prod.recipe_id)
				for rid in recipe["outputs"]:
					buffer.add(StringName(rid), int(recipe["outputs"][rid]))
				prod.active = false
				prod.progress = 0.0
	# —— 2) 缓冲定期汇入资源池 ——
	for id in world.query(&"ResourceBuffer"):
		if not world.is_alive(id):
			continue
		var buffer = world.get_component(id, &"ResourceBuffer")
		if buffer.flush_interval <= 0.0:
			continue
		buffer.flush_timer += dt
		if buffer.flush_timer < buffer.flush_interval:
			continue
		buffer.flush_timer -= buffer.flush_interval
		if buffer.flush_timer > buffer.flush_interval:
			buffer.flush_timer = 0.0 # 长帧补偿，避免连环汇入
		for rid in buffer.stored:
			var n := int(buffer.stored[rid])
			if n != 0:
				state.add(StringName(rid), n)
				world.resource_gained.emit(StringName(rid), n)
		buffer.stored = {}
