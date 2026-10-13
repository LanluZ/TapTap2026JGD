class_name ProjectileSystem
extends System
## #8 射弹（§5）：飞行、命中判定。命中不直接扣血——把伤害记入目标
## Health.pending_damage，由 DamageSystem（#9）统一结算（保持伤害入口单一）。
## 目标已亡/无法定位则射弹失效；命中判定用几何跨越（步长 ≥ 剩余距离），无魔法阈值。


func tick(world, dt: float) -> void:
	for id in world.query(&"Projectile"):
		if not world.is_alive(id):
			continue
		var p = world.get_component(id, &"Projectile")
		if not world.is_alive(p.target):
			world.destroy_entity(id) # 目标已死：射弹落空
			continue
		var target_pos = EntityLocator.position(world, p.target)
		if target_pos == null:
			world.destroy_entity(id)
			continue
		var to_target: Vector2 = target_pos - p.position
		var dist: float = to_target.length()
		var step: float = p.speed * dt
		if dist <= 0.0001 or step >= dist:
			# 命中：登记待结算伤害
			var hp = world.get_component(p.target, &"Health")
			if hp != null:
				hp.pending_damage += p.damage
			world.destroy_entity(id)
		else:
			p.position += to_target / dist * step
