class_name DamageSystem
extends System
## #9 伤害结算（§5）：pending_damage → hp；死亡 → 掉落入账（§7 击杀普通敌人掉
## 零件、精英掉特殊材料）→ 发 entity_died → 标记延迟销毁（#11 清理）。


func tick(world, _dt: float) -> void:
	var state = world.state
	for id in world.query(&"Health"):
		if not world.is_alive(id):
			continue
		var hp = world.get_component(id, &"Health")
		if hp.pending_damage > 0.0:
			hp.hp -= hp.pending_damage
			hp.pending_damage = 0.0
		if hp.hp > 0.0:
			continue
		# —— 死亡 ——
		var en = world.get_component(id, &"Enemy")
		if en != null and en.loot_id != &"":
			state.add(en.loot_id, en.loot_amount)
			world.resource_gained.emit(en.loot_id, en.loot_amount)
		world.entity_died.emit(id)
		world.destroy_entity(id)
