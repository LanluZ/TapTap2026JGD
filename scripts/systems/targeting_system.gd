class_name TargetingSystem
extends System
## #7 索敌与发射（§5）：路径上按 target_mask acquisition 最近敌人，
## 冷却就绪且在射程内则发射射弹（Projectile 实体，#8 飞行、#9 结算）。
## 攻击者自身 Effect（如指挥所 damage_up）以乘区作用于单发伤害。
##
## 任务 6「弹药与水效果消费端」：
##   · ammo > 0 → 每发扣 1；ammo == 0 → 断弹惩罚：冷却 ×2 **且** 伤害 ×0.5（同时生效，
##     按发射时刻的 ammo 判定；伤害直接定格进 Projectile.damage，不改扣血处）。
##   · hydro_thirsty 且 world.is_watered == false → 停摆不发射（不扣弹、不点冷却）。
##   · hydro_love 且供水 → 实际冷却 ×0.8。与断弹惩罚**乘算**：
##     base × 2（断弹）× 0.8（喜水有水）= 1.6 base，谁先乘都一样。
##   · hydro_none：先看基因再决定是否查水网——默认路径零 is_watered 调用。

const HYDRO_LOVE := &"hydro_love"
const HYDRO_THIRSTY := &"hydro_thirsty"

## 断弹惩罚（冷却倍率 / 伤害倍率）与喜水加速（冷却倍率）——精确取值见规格。
const DRY_COOLDOWN_MULT := 2.0
const DRY_DAMAGE_MULT := 0.5
const LOVE_COOLDOWN_MULT := 0.8


func tick(world, dt: float) -> void:
	for id in world.query(&"Attack"):
		if not world.is_alive(id):
			continue
		var atk = world.get_component(id, &"Attack")
		if atk.cooldown_left > 0.0:
			atk.cooldown_left -= dt
			if atk.cooldown_left > 0.0:
				continue
		# —— 亲水（任务 6）：hydro_none 直接过（不碰水网）；嗜水断水 = 停摆 ——
		# 与「射程内无敌」同路径：保持就绪（冷却不被烧掉），水一通当帧就能打。
		if atk.hydro == HYDRO_THIRSTY and not world.is_watered(id):
			continue
		# 目标 acquisition（当前仅敌人可被索敌）
		if (atk.target_mask & GameConfig.MASK_ENEMY) == 0:
			continue
		var origin = EntityLocator.position(world, id)
		if origin == null:
			continue
		# 瞄准策略来自 DNA 瞄准座（Attack.targeting）：nearest / farthest / highest_hp / lowest_hp
		var mode := String(atk.targeting)
		# 射程倍率（增程光环，§18.2 range_up）：选目标前算，不改冷却
		var reach: float = atk.range
		var eff_range = world.get_component(id, &"Effect")
		if eff_range != null and eff_range.has_stat(GameConfig.STAT_ATTACK_RANGE_MULT):
			reach *= eff_range.get_value(GameConfig.STAT_ATTACK_RANGE_MULT)
		var best := -1
		var best_d: float = 0.0
		var best_hp: float = 0.0
		for eid in world.query(&"Enemy"):
			if not world.is_alive(eid):
				continue
			var epos = EntityLocator.position(world, eid)
			if epos == null:
				continue
			var d: float = origin.distance_to(epos)
			if d > reach:
				continue
			var ehp = world.get_component(eid, &"Health")
			var hpv: float = ehp.hp if ehp != null else 0.0
			var better := false
			if best == -1:
				better = true
			else:
				match mode:
					"farthest":
						better = d > best_d
					"highest_hp":
						better = hpv > best_hp
					"lowest_hp":
						better = hpv < best_hp
					_:
						better = d < best_d
			if better:
				best = eid
				best_d = d
				best_hp = hpv
		if best == -1:
			continue # 射程内无敌：保持就绪，下帧继续找
		var pdef: Dictionary = world.config.get_projectile(atk.projectile)
		if pdef.is_empty():
			atk.cooldown_left = atk.cooldown # 配置缺失也别每帧刷错误
			continue
		var dry: bool = int(atk.ammo) <= 0 # 断弹判定取发射时刻的弹药（本发仍发射：半伤空放）
		var damage: float = atk.damage
		var eff = world.get_component(id, &"Effect")
		if eff != null and eff.has_stat(GameConfig.STAT_ATTACK_DAMAGE_MULT):
			damage *= eff.get_value(GameConfig.STAT_ATTACK_DAMAGE_MULT)
		if dry:
			damage *= DRY_DAMAGE_MULT # 断弹：伤害 ×0.5（定格进 Projectile.damage）
		else:
			atk.ammo -= 1 # 每发扣 1 矿
		var pid: int = world.create_entity()
		var p := Projectile.new()
		p.proj_id = atk.projectile
		p.target = best
		p.damage = damage
		p.speed = float(pdef["speed"])
		p.position = origin
		world.add_component(pid, p)
		atk.cooldown_left = _effective_cooldown(world, id, atk, dry)


## 生效冷却（任务 6）：base × 断弹(×2) × 喜水有水(×0.8)。两因子乘算，次序无关。
## 先判基因再查水：hydro_none / 断水 的实体不会调用 world.is_watered（默认路径零开销）。
func _effective_cooldown(world, id: int, atk, dry: bool) -> float:
	var cd: float = atk.cooldown
	if dry:
		cd *= DRY_COOLDOWN_MULT
	if atk.hydro == HYDRO_LOVE and world.is_watered(id):
		cd *= LOVE_COOLDOWN_MULT
	return cd
