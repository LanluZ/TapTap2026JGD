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
##
## 二倍体（DNA 杂合座）：Attack.alt 非空 = 第二攻击通道。两条通道各自独立冷却
## （cooldown_left / alt_cd_left）、独立射程·伤害·瞄准·射弹，但**共用同一个弹药仓**
## （谁开火谁扣 1，断弹按各自发射时刻的 ammo 判定）。发射主体只有 `_tick_channel` 一份实现：
## 主通道传 null（走组件扁平字段），第二通道传 alt 字典。
## 水基因是组件级字段（hydro / hydro2），对两条通道同时生效：任一条嗜水且断水 → 两条都停摆；
## 任一条喜水且有水 → 两条冷却都 ×0.8（两者同时满足时同时生效：供水才有输出、断水就停）。

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
		# 水效果按**实体**算一次：两条通道共用同一组水基因（hydro / hydro2），故判据一致。
		# 先判基因再决定是否查水网——hydro_none 且 hydro2 空 = 零 is_watered 调用。
		var blocked := _hydro_blocked(world, id, atk)
		var love_watered := _hydro_love_watered(world, id, atk)
		# 主通道：组件扁平字段（纯合 = 唯一通道，路径与改动前一致）
		_tick_channel(world, id, atk, null, dt, blocked, love_watered)
		# 第二通道：杂合座才有（alt 空 = 直接跳过，纯合零开销）
		if not atk.alt.is_empty():
			_tick_channel(world, id, atk, atk.alt, dt, blocked, love_watered)


## 单通道推进 + 发射：ch == null 用组件扁平字段，否则用 Attack.alt 字典（第二通道）。
## 两条通道走同一段逻辑，只有「数值从哪取 / 冷却写到哪」不同。
func _tick_channel(world, id: int, atk, ch, dt: float, blocked: bool, love_watered: bool) -> void:
	# —— 1) 冷却推进（主通道 cooldown_left / 第二通道 alt_cd_left）——
	var cd_left: float = atk.alt_cd_left if ch != null else atk.cooldown_left
	if cd_left > 0.0:
		cd_left -= dt
		_set_cd(atk, ch, cd_left)
		if cd_left > 0.0:
			return
	# —— 2) 亲水：嗜水断水 = 停摆（不发射、不扣弹、不点冷却）——
	# 与「射程内无敌」同路径：保持就绪（冷却不被烧掉），水一通当帧就能打。
	if blocked:
		return
	# 目标 acquisition（当前仅敌人可被索敌；两条通道共用同一 target_mask）
	if (atk.target_mask & GameConfig.MASK_ENEMY) == 0:
		return
	var origin = EntityLocator.position(world, id)
	if origin == null:
		return
	# 射程与瞄准策略按通道取（数值座 / 瞄准座；第二通道各有自己的一套）
	var mode := String(atk.targeting)
	var reach: float = atk.range
	if ch != null:
		mode = String(ch.get("targeting", atk.targeting))
		reach = float(ch.get("range", atk.range))
	# 射程倍率（增程光环，§18.2 range_up）：选目标前算，不改冷却
	var eff_range = world.get_component(id, &"Effect")
	if eff_range != null and eff_range.has_stat(GameConfig.STAT_ATTACK_RANGE_MULT):
		reach *= eff_range.get_value(GameConfig.STAT_ATTACK_RANGE_MULT)
	var best := _acquire(world, origin, reach, mode)
	if best == -1:
		return # 射程内无敌：保持就绪，下帧继续找
	# 本通道的射弹 / 基础冷却 / 基础伤害
	var proj_id: StringName = atk.projectile
	var cooldown: float = atk.cooldown
	var base_damage: float = atk.damage
	if ch != null:
		proj_id = StringName(ch.get("projectile", atk.projectile))
		cooldown = float(ch.get("cooldown", atk.cooldown))
		base_damage = float(ch.get("damage", atk.damage))
	var pdef: Dictionary = world.config.get_projectile(proj_id)
	if pdef.is_empty():
		_set_cd(atk, ch, cooldown) # 配置缺失也别每帧刷错误（点基础冷却）
		return
	var dry: bool = int(atk.ammo) <= 0 # 断弹判定取发射时刻的弹药（本发仍发射：半伤空放）
	var damage: float = base_damage
	var eff = world.get_component(id, &"Effect")
	if eff != null and eff.has_stat(GameConfig.STAT_ATTACK_DAMAGE_MULT):
		damage *= eff.get_value(GameConfig.STAT_ATTACK_DAMAGE_MULT)
	if dry:
		damage *= DRY_DAMAGE_MULT # 断弹：伤害 ×0.5（定格进 Projectile.damage）
	else:
		atk.ammo -= 1 # 每发扣 1 矿（两条通道共用同一个弹药仓）
	var pid: int = world.create_entity()
	var p := Projectile.new()
	p.proj_id = proj_id
	p.target = best
	p.damage = damage
	p.speed = float(pdef["speed"])
	p.position = origin
	world.add_component(pid, p)
	_set_cd(atk, ch, _effective_cooldown(cooldown, dry, love_watered))


## 索敌：reach 射程内按瞄准策略挑一个敌人，无候选返回 -1。
## 策略来自 DNA 瞄准座：nearest / farthest / highest_hp / lowest_hp。
func _acquire(world, origin: Vector2, reach: float, mode: String) -> int:
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
	return best


## 写回通道冷却（主通道 cooldown_left / 第二通道 alt_cd_left）。
func _set_cd(atk, ch, value: float) -> void:
	if ch == null:
		atk.cooldown_left = value
	else:
		atk.alt_cd_left = value


## 停摆判据（任务 6 + 二倍体）：任一水基因嗜水且断水 → 整座停摆（两条通道一起停）。
## 两条水基因都不是嗜水时**不调用** world.is_watered（默认路径零开销）。
func _hydro_blocked(world, id: int, atk) -> bool:
	if atk.hydro != HYDRO_THIRSTY and atk.hydro2 != HYDRO_THIRSTY:
		return false
	return not world.is_watered(id)


## 加速判据（任务 6 + 二倍体）：任一水基因喜水且供水 → 冷却 ×0.8（两条通道都加速）。
## 两条水基因都不是喜水时不查水网（默认路径零开销）。
func _hydro_love_watered(world, id: int, atk) -> bool:
	if atk.hydro != HYDRO_LOVE and atk.hydro2 != HYDRO_LOVE:
		return false
	return world.is_watered(id)


## 生效冷却（任务 6）：base × 断弹(×2) × 喜水有水(×0.8)。两因子乘算，次序无关。
## 喜水判据在调用前已按 hydro / hydro2 双基因算好（love_watered），这里只做乘法。
func _effective_cooldown(base_cd: float, dry: bool, love_watered: bool) -> float:
	var cd: float = base_cd
	if dry:
		cd *= DRY_COOLDOWN_MULT
	if love_watered:
		cd *= LOVE_COOLDOWN_MULT
	return cd
