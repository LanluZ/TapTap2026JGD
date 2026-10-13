class_name TargetingSystem
extends System
## #7 索敌与发射（§5）：路径上按 target_mask acquisition 最近敌人，
## 冷却就绪且在射程内则发射射弹（Projectile 实体，#8 飞行、#9 结算）。
## 攻击者自身 Effect（如指挥所 damage_up）以乘区作用于单发伤害。


func tick(world, dt: float) -> void:
	for id in world.query(&"Attack"):
		if not world.is_alive(id):
			continue
		var atk = world.get_component(id, &"Attack")
		if atk.cooldown_left > 0.0:
			atk.cooldown_left -= dt
			if atk.cooldown_left > 0.0:
				continue
		# 目标 acquisition（当前仅敌人可被索敌）
		if (atk.target_mask & GameConfig.MASK_ENEMY) == 0:
			continue
		var origin = EntityLocator.position(world, id)
		if origin == null:
			continue
		var best := -1
		var best_d: float = atk.range
		for eid in world.query(&"Enemy"):
			if not world.is_alive(eid):
				continue
			var epos = EntityLocator.position(world, eid)
			if epos == null:
				continue
			var d: float = origin.distance_to(epos)
			if d <= atk.range and (best == -1 or d < best_d):
				best = eid
				best_d = d
		if best == -1:
			continue # 射程内无敌：保持就绪，下帧继续找
		var pdef: Dictionary = world.config.get_projectile(atk.projectile)
		if pdef.is_empty():
			atk.cooldown_left = atk.cooldown # 配置缺失也别每帧刷错误
			continue
		var damage: float = atk.damage
		var eff = world.get_component(id, &"Effect")
		if eff != null and eff.has_stat(GameConfig.STAT_ATTACK_DAMAGE_MULT):
			damage *= eff.get_value(GameConfig.STAT_ATTACK_DAMAGE_MULT)
		var pid: int = world.create_entity()
		var p := Projectile.new()
		p.target = best
		p.damage = damage
		p.speed = float(pdef["speed"])
		p.position = origin
		world.add_component(pid, p)
		atk.cooldown_left = atk.cooldown
