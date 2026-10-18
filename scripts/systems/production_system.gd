class_name ProductionSystem
extends System
## #5 生产（§5）：按配方推进——输入（含电力，电力是普通资源 §7）存入池中且
## 足够才扣款开产；产出先进 ResourceBuffer；输入不足即停产等待。
## 缓冲按 flush_interval 定期汇入玩家资源池（§7「工厂产出经 ResourceBuffer 定期汇入」）。
##
## 任务 5「生产端物理化」（物流规格 §7）：
##   · water / ore 不再汇入资源池：产出进工厂**本地缓冲**，由物流系统搬走
##     （泵→管网 1 水/秒；矿机→传送带 ≤2 块/秒）。本地缓冲容量 4；
##     **放不下本次产出就不开工**（判据在扣款前）→ 无路可走时积满即停产。
##   · synth_special（装配台）改用传送带进料：开产条件 = 本地矿库存 ≥ 3 且池里能扣电；
##     开产扣库存 3 矿 + 池扣电 2（矿不从池扣，配方里也没有 ore 输入）。
##   · 其他资源（power / parts / special_material …）照旧：先进 ResourceBuffer 再定期汇入池。

## 物流本地缓冲（泵/矿机出料队列）：容量 4，由 LogisticsSystem 按块/秒吐到带/管。
## 水/矿判定走 ResourceBuffer.is_physical（唯一物理资源清单），这里只用 ORE 扣库存。
const ResourceBufferScript = preload("res://scripts/components/resource_buffer.gd")
const ORE := &"ore"


func tick(world, dt: float) -> void:
	var state = world.state
	var lg = world.logistics
	# —— 1) 推进生产 ——
	var buf_bit := Entity.bit_for(&"ResourceBuffer")
	for id in world.query(&"Production"):
		if not world.is_alive(id):
			continue
		if (world.mask_of(id) & buf_bit) == 0:
			continue # 配置校验已要求 Production 蓝图带 ResourceBuffer，防御跳过
		var prod = world.get_component(id, &"Production")
		var buffer = world.get_component(id, &"ResourceBuffer")
		var recipe: Dictionary = world.config.get_recipe(prod.recipe_id)
		if recipe.is_empty():
			continue
		# 进料库存上限（配方驱动）：装配台矿堆 6；deliver_ore 亦按此截断
		var ore_cap: int = ResourceBufferScript.ore_cap_of(prod.recipe_id)
		if ore_cap > 0 and buffer.cap != ore_cap:
			buffer.cap = ore_cap
		if not prod.active:
			# 扣款开产：池输入 / 进料库存 / 本地缓冲空间任一不足 → 停产待料
			if not _can_start(world, lg, id, buffer, recipe):
				continue
			if not state.pay(recipe["inputs"]):
				continue
			var ore_cost: int = ResourceBufferScript.ore_cost_of(prod.recipe_id)
			if ore_cost > 0:
				buffer.take(ORE, ore_cost)
			prod.active = true
			prod.progress = 0.0
		if prod.active:
			prod.progress += dt
			if prod.progress >= prod.interval:
				for rid in recipe["outputs"]:
					_store_output(lg, id, buffer, StringName(rid), int(recipe["outputs"][rid]))
				prod.active = false
				prod.progress = 0.0
	# —— 2) 缓冲定期汇入资源池（水/矿除外：留在本地等物流搬走）——
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
		for rid in buffer.stored.keys():
			if ResourceBufferScript.is_physical(StringName(rid)):
				continue # §7：水/矿不进资源池（泵/矿机缓冲、装配台矿堆）
			var n := int(buffer.stored[rid])
			buffer.stored.erase(rid)
			if n != 0:
				state.add(StringName(rid), n)
				world.resource_gained.emit(StringName(rid), n)


## 开产判据（全部在扣款前评估，避免扣了电却产不出来）：
##   ① 池资源够扣（电力等普通资源）；
##   ② 进料库存够（装配台矿堆 ≥ 3）；
##   ③ 物理产出放得下（泵/矿机本地缓冲剩余 ≥ 本次产出）——满则停产。
func _can_start(world, lg, id: int, buffer, recipe: Dictionary) -> bool:
	if world.state == null or not world.state.can_afford(recipe["inputs"]):
		return false
	var ore_cost: int = ResourceBufferScript.ore_cost_of(recipe["id"])
	if ore_cost > 0 and buffer.count_of(ORE) < ore_cost:
		return false
	for rid in recipe["outputs"]:
		if not ResourceBufferScript.is_physical(StringName(rid)):
			continue
		if lg == null:
			return false # 无物流系统 = 水/矿无处可去（bootstrap 必须装 LogisticsSystem）
		if not lg.buffer_has_space(id, int(recipe["outputs"][rid])):
			return false
	return true


## 产出去向：水/矿进物流本地缓冲（由带/管搬走）；其余进组件缓冲再定期汇入池。
func _store_output(lg, id: int, buffer, rid: StringName, amount: int) -> void:
	if ResourceBufferScript.is_physical(rid):
		if lg != null:
			lg.add_buffer(id, amount) # 开产前已确认放得下，不截断
		return
	buffer.add(rid, amount)
