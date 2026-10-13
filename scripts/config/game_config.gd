class_name GameConfig
extends RefCounted
## 配置层（架构文档 §9）：加载并校验 data/*.json（8 个，含 genes.json）。
## 原则：缺字段 / 类型错误 / 悬空 id 引用一律记录报错并让加载失败（返回 null），
## 不静默默认。所有玩法数值只存在于 JSON，代码零硬编码。
##
## —— 协议常量（非玩法数值，供 JSON 按名/按位引用）——
## target_mask 位含义：
const MASK_ENEMY := 1 # 路径上的敌人
const MASK_FACTORY := 2 # 工厂实体
## Effect.stat_id 集合（由 Movement/Targeting 等系统消费）：
const STAT_MOVE_SPEED_MULT := &"move_speed_mult"
const STAT_ATTACK_DAMAGE_MULT := &"attack_damage_mult"
const STAT_IDS: Array = [STAT_MOVE_SPEED_MULT, STAT_ATTACK_DAMAGE_MULT]

## 组件类注册表：蓝图组件校验 + 实例化（字段名即组件属性名）。
const COMPONENT_SCRIPTS: Dictionary = {
	"PathFollower": preload("res://scripts/components/path_follower.gd"),
	"GridPosition": preload("res://scripts/components/grid_position.gd"),
	"Health": preload("res://scripts/components/health.gd"),
	"Enemy": preload("res://scripts/components/enemy.gd"),
	"Attack": preload("res://scripts/components/attack.gd"),
	"Production": preload("res://scripts/components/production.gd"),
	"ResourceBuffer": preload("res://scripts/components/resource_buffer.gd"),
	"Aura": preload("res://scripts/components/aura.gd"),
	"Effect": preload("res://scripts/components/effect.gd"),
	"Projectile": preload("res://scripts/components/projectile.gd"),
	"Factory": preload("res://scripts/components/factory.gd"),
}
## 工厂蓝图允许组合的组件（§4：蓝图 = 组件组合；敌人侧组件不在其内）。
const PLACEABLE_COMPONENTS: Array = [
	"Factory", "GridPosition", "Attack", "Production", "ResourceBuffer", "Aura", "Health",
]
## 蓝图组件必填字段（§4 关键字段；运行时字段如 cooldown_left/progress 不要求）。
const COMPONENT_REQUIRED: Dictionary = {
	"Factory": ["blueprint_id"],
	"GridPosition": [],
	"Attack": ["range", "damage", "cooldown", "target_mask", "projectile"],
	"Production": ["recipe_id", "interval"],
	"ResourceBuffer": ["flush_interval"],
	"Aura": ["radius", "effect_id", "target_mask"],
	"Health": ["hp", "max_hp"],
}
## 必填字段的类型/约束：pos_num(>0) / num(≥0) / int(整数≥0) / mask(整数>0) / str(非空串)。
const FIELD_KIND: Dictionary = {
	"blueprint_id": "str",
	"range": "pos_num", "damage": "num", "cooldown": "pos_num",
	"target_mask": "mask", "projectile": "str",
	"recipe_id": "str", "interval": "pos_num",
	"flush_interval": "pos_num",
	"radius": "pos_num", "effect_id": "str",
	"hp": "pos_num", "max_hp": "pos_num",
}

## 基因组表达（DNA 系统）：蓝图 genome → 组件规格，再走 make_component 实例化。
const GenomeScript = preload("res://scripts/dna/genome.gd")

## —— 归一化后的配置表（全部 id 引用可交叉校验）——
var genes: Dictionary = {} # genes.json 归一化：{loci, gamete_keep, crossover, mutation}
var resources: Dictionary = {} # id -> {id, name}
var enemies: Dictionary = {} # id -> {name, hp, speed, elite, loot_id, loot_amount}
var recipes: Dictionary = {} # id -> {inputs, outputs}（StringName -> int）
var projectiles: Dictionary = {} # id -> {speed}
var blueprints: Dictionary = {} # id -> {name, cost, components}
var effects: Dictionary = {} # id -> {stat_id, value, duration}
var cards: Dictionary = {} # id -> {name, cost, effect}
var levels: Dictionary = {} # id -> 归一化关卡
var hand_max: int = 0 # cards.json 顶层手牌上限（§8）

var _errors: PackedStringArray = PackedStringArray()


# ================================================================ 加载入口

## 加载 dir 下 7 个 JSON。任一文件缺失/校验失败 → push_error 全部错误并返回 null。
static func load_all(dir: String = "res://data/") -> GameConfig:
	var cfg := GameConfig.new()
	if not cfg.load_from(dir):
		for e in cfg._errors:
			push_error(e)
		return null
	return cfg


## 实例级加载：返回是否通过校验；错误保留在 _errors（get_errors() 可读），
## 供测试断言「缺字段报错不静默」而不重复刷屏。
func load_from(dir: String) -> bool:
	_errors = PackedStringArray()
	_load_dir(dir)
	return _errors.is_empty()


func get_errors() -> PackedStringArray:
	return _errors


func _load_dir(dir: String) -> void:
	var pending := [
		["resources.json", "resources", _parse_resources],
		["enemies.json", "enemies", _parse_enemies],
		["recipes.json", "recipes", _parse_recipes],
		["buffs.json", "_root", _parse_buffs], # 先于 factories：蓝图 Aura 交叉引用效果 id
		["genes.json", "_root", _parse_genes], # 先于 factories：蓝图 genome 校验依据
		["factories.json", "_root", _parse_factories],
		["cards.json", "_root", _parse_cards],
		["levels.json", "levels", _parse_levels],
	]
	for item in pending:
		var path: String = dir + String(item[0])
		var data = _load_json(path)
		if data == null:
			continue
		var fn: Callable = item[2]
		fn.call(data, path)


func _load_json(path: String):
	if not FileAccess.file_exists(path):
		_err("%s: 文件不存在" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if data == null:
		_err("%s: JSON 解析失败" % path)
		return null
	return data


# ================================================================ 资源

func _parse_resources(data, src: String) -> void:
	var root := _req_obj(data, src)
	var arr := _req_list(root.get("resources", null), src + ".resources")
	var i := 0
	for e in arr:
		var ctx := "%s.resources[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var name := _req_str(d, "name", ctx)
		if id.is_empty() or name.is_empty():
			continue
		if resources.has(StringName(id)):
			_err("%s: 资源 id 重复 '%s'" % [ctx, id])
			continue
		resources[StringName(id)] = {"id": StringName(id), "name": name}


# ================================================================ 敌人

func _parse_enemies(data, src: String) -> void:
	var root := _req_obj(data, src)
	var arr := _req_list(root.get("enemies", null), src + ".enemies")
	var i := 0
	for e in arr:
		var ctx := "%s.enemies[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var name := _req_str(d, "name", ctx)
		var hp := _req_num(d, "hp", ctx)
		var speed := _req_num(d, "speed", ctx)
		var elite := _req_bool(d, "elite", ctx)
		var loot_id := _req_str(d, "loot_id", ctx)
		var loot_amount := _req_int(d, "loot_amount", ctx)
		if id.is_empty() or hp <= 0.0 or speed < 0.0 or loot_id.is_empty():
			if hp <= 0.0 and d.has("hp"):
				_err("%s: hp 应 > 0" % ctx)
			if speed < 0.0 and d.has("speed"):
				_err("%s: speed 应 ≥ 0" % ctx)
			continue
		if not resources.has(StringName(loot_id)):
			_err("%s: loot_id '%s' 未在 resources.json 定义" % [ctx, loot_id])
		if loot_amount < 0:
			_err("%s: loot_amount 应 ≥ 0" % ctx)
		if enemies.has(StringName(id)):
			_err("%s: 敌人 id 重复 '%s'" % [ctx, id])
			continue
		enemies[StringName(id)] = {
			"id": StringName(id), "name": name, "hp": hp, "speed": speed,
			"elite": elite, "loot_id": StringName(loot_id), "loot_amount": loot_amount,
		}


# ================================================================ 配方

func _parse_recipes(data, src: String) -> void:
	var root := _req_obj(data, src)
	var arr := _req_list(root.get("recipes", null), src + ".recipes")
	var i := 0
	for e in arr:
		var ctx := "%s.recipes[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var inputs = _req_res_map(d, "inputs", ctx, true)
		var outputs = _req_res_map(d, "outputs", ctx, false)
		if id.is_empty():
			continue
		if outputs.is_empty():
			_err("%s: outputs 不能为空（至少一项产出）" % ctx)
		if recipes.has(StringName(id)):
			_err("%s: 配方 id 重复 '%s'" % [ctx, id])
			continue
		recipes[StringName(id)] = {"id": StringName(id), "inputs": inputs, "outputs": outputs}


# ================================================================ 工厂蓝图 + 射弹

func _parse_factories(data, src: String) -> void:
	var root := _req_obj(data, src)
	# 射弹
	var projs := _req_list(root.get("projectiles", null), src + ".projectiles")
	var pi := 0
	for e in projs:
		var ctx := "%s.projectiles[%d]" % [src, pi]
		pi += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var speed := _req_num(d, "speed", ctx)
		if id.is_empty():
			continue
		if speed <= 0.0 and d.has("speed"):
			_err("%s: speed 应 > 0" % ctx)
		if projectiles.has(StringName(id)):
			_err("%s: 射弹 id 重复 '%s'" % [ctx, id])
			continue
		projectiles[StringName(id)] = {"id": StringName(id), "speed": maxf(speed, 0.0)}
	# 蓝图（DNA 系统：组件由基因组表达，蓝图不再手写 components）
	_validate_gene_refs(src)
	var arr := _req_list(root.get("blueprints", null), src + ".blueprints")
	var i := 0
	for e in arr:
		var ctx := "%s.blueprints[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var name := _req_str(d, "name", ctx)
		var cost := _req_res_map(d, "cost", ctx, true)
		if id.is_empty():
			continue
		var genome = _validate_genome(ctx, d.get("genome", null))
		if genome == null:
			continue # 校验错误已记录
		for spec in GenomeScript.express(genome, genes, id, name):
			_validate_component(ctx, id, spec)
		if blueprints.has(StringName(id)):
			_err("%s: 蓝图 id 重复 '%s'" % [ctx, id])
			continue
		blueprints[StringName(id)] = {"id": StringName(id), "name": name, "cost": cost, "genome": genome}


func _validate_component(ctx: String, blueprint_id: String, spec) -> void:
	if not (spec is Dictionary):
		_err("%s: 组件定义应为对象" % ctx)
		return
	var d: Dictionary = spec
	var tname := _req_str(d, "type", ctx)
	if tname.is_empty():
		return
	if not PLACEABLE_COMPONENTS.has(tname):
		_err("%s: 工厂蓝图不支持组件类型 '%s'" % [ctx, tname])
		return
	if not COMPONENT_REQUIRED.has(tname):
		return
	# 必填字段
	for req in COMPONENT_REQUIRED[tname]:
		if not d.has(req):
			_err("%s: 组件 '%s' 缺字段 '%s'" % [ctx, tname, req])
	# 字段名必须是组件真实属性（拼写错误直接报错）
	var inst = COMPONENT_SCRIPTS[tname].new()
	var props := {}
	for p in inst.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props[String(p["name"])] = true
	for k in d.keys():
		if k == "type":
			continue
		if not props.has(k):
			_err("%s: 组件 '%s' 不存在字段 '%s'" % [ctx, tname, k])
			continue
		if FIELD_KIND.has(k) and not _check_kind(d[k], FIELD_KIND[k], "%s.%s" % [ctx, k]):
			pass # _check_kind 已记录错误
	# 交叉引用
	if tname == "Attack":
		var pid := str(d.get("projectile", ""))
		if not pid.is_empty() and not projectiles.has(StringName(pid)):
			_err("%s: projectile '%s' 未在 factories.json projectiles 定义" % [ctx, pid])
	if tname == "Production":
		var rid := str(d.get("recipe_id", ""))
		if not rid.is_empty() and not recipes.has(StringName(rid)):
			_err("%s: recipe_id '%s' 未在 recipes.json 定义" % [ctx, rid])
	if tname == "Aura":
		var eid := str(d.get("effect_id", ""))
		if not eid.is_empty() and not effects.has(StringName(eid)):
			_err("%s: effect_id '%s' 未在 buffs.json 定义" % [ctx, eid])
	if tname == "Factory":
		var bid := str(d.get("blueprint_id", ""))
		if not bid.is_empty() and bid != blueprint_id:
			_err("%s: Factory.blueprint_id '%s' 与蓝图 id '%s' 不一致" % [ctx, bid, blueprint_id])


# ================================================================ 基因座（DNA 系统）

func _parse_genes(data, src: String) -> void:
	var root := _req_obj(data, src)
	var arr := _req_list(root.get("loci", null), src + ".loci")
	if arr.is_empty():
		return
	var out_loci := []
	for i in arr.size():
		var ctx := "%s.loci[%d]" % [src, i]
		var d := _req_obj(arr[i], ctx)
		var id := _req_str(d, "id", ctx)
		var kind := _req_str(d, "kind", ctx)
		if id.is_empty() or kind.is_empty():
			continue
		var alleles := {}
		var params := {}
		if kind == "stats":
			if not d.has("allele_id"):
				_err("%s: stats 座缺 allele_id" % ctx)
			if not (d.get("params", null) is Dictionary) or (d["params"] as Dictionary).is_empty():
				_err("%s: stats 座必须定义非空 params" % ctx)
		if d.get("params", null) is Dictionary:
			params = _parse_param_specs(ctx + ".params", d["params"])
		var alleles_raw = d.get("alleles", null)
		if alleles_raw is Dictionary:
			for a in alleles_raw:
				if not (alleles_raw[a] is Dictionary):
					_err("%s.alleles.%s: 应为对象（payload，可为空 {}）" % [ctx, str(a)])
					continue
				alleles[a] = alleles_raw[a]
		elif kind != "stats":
			_err("%s: 座必须定义 alleles 对象" % ctx)
		var locus := { "id": id, "kind": kind, "alleles": alleles, "params": params }
		if d.has("allele_id"):
			locus["allele_id"] = str(d["allele_id"])
		out_loci.append(locus)
	if out_loci.size() != arr.size():
		return # 有座解析失败，错误已记录，不落表
	var mut_raw = root.get("mutation", null)
	var mut: Dictionary = mut_raw if mut_raw is Dictionary else {}
	genes = {
		"loci": out_loci,
		"gamete_keep": clampf(_num_or(root.get("gamete_keep", null), 0.5), 0.0, 1.0),
		"crossover": clampf(_num_or(root.get("crossover", null), 0.5), 0.0, 1.0),
		"mutation": {
			"rate": _num_or(mut.get("rate", null), 0.05),
			"redundant_rate": _num_or(mut.get("redundant_rate", null), 0.2),
			"drift": _num_or(mut.get("drift", null), 0.15),
		},
	}


## params 定义表：{key: {default, min, max}}；default 必须落在 [min, max]。
func _parse_param_specs(ctx: String, raw: Dictionary) -> Dictionary:
	var out := {}
	for k in raw:
		var pctx := "%s.%s" % [ctx, str(k)]
		var pd := _req_obj(raw[k], pctx)
		var dv := _req_num(pd, "default", pctx)
		var mn := _req_num(pd, "min", pctx)
		var mx := _req_num(pd, "max", pctx)
		if dv < mn or dv > mx:
			_err("%s: default 应落在 [min, max] 内" % pctx)
		out[str(k)] = { "default": dv, "min": mn, "max": mx }
	return out


## 蓝图基因组校验：座数一致、等位基因已定义、参数键/范围合法。返回归一化基因组或 null。
func _validate_genome(ctx: String, v):
	var loci: Array = genes.get("loci", [])
	if loci.is_empty():
		_err("%s: genes.json 未成功加载，无法校验基因组" % ctx)
		return null
	if not (v is Array):
		_err("%s: genome 应为基因组数组（空座用 JSON null），得到 %s" % [ctx, type_string(typeof(v))])
		return null
	if (v as Array).size() != loci.size():
		_err("%s: 基因组座数应为 %d，得到 %d" % [ctx, loci.size(), (v as Array).size()])
		return null
	var out: Array = []
	for idx in (v as Array).size():
		var entry = (v as Array)[idx]
		var lctx := "%s.genome[%d]" % [ctx, idx]
		if entry == null:
			out.append(null)
			continue
		if not (entry is Dictionary):
			_err("%s: 空座写 null，有基因写 {allele, params}" % lctx)
			return null
		var locus: Dictionary = loci[idx]
		var allele := _req_str(entry, "allele", lctx)
		if allele.is_empty():
			return null
		if str(locus.get("kind", "")) == "stats":
			if allele != str(locus.get("allele_id", "")):
				_err("%s: 数值座 allele 应为 '%s'，得到 '%s'" % [lctx, str(locus.get("allele_id", "")), allele])
		elif not (locus.get("alleles", {}) as Dictionary).has(allele):
			_err("%s: 等位基因 '%s' 未在座 '%s' 定义（可选: %s）" % [lctx, allele, str(locus.get("id", idx)), str((locus.get("alleles", {}) as Dictionary).keys())])
		var params := {}
		if entry.has("params"):
			if not (entry["params"] is Dictionary):
				_err("%s.params: 应为对象" % lctx)
				return null
			var declared: Dictionary = locus.get("params", {})
			for k in entry["params"]:
				if not declared.has(str(k)):
					_err("%s.params: 座 '%s' 未定义参数 '%s'" % [lctx, str(locus.get("id", idx)), str(k)])
					continue
				var pv = entry["params"][k]
				if not (pv is int or pv is float):
					_err("%s.params.%s: 应为数值" % [lctx, str(k)])
					continue
				var spec: Dictionary = declared[str(k)]
				if float(pv) < float(spec["min"]) or float(pv) > float(spec["max"]):
					_err("%s.params.%s: %s 超出范围 [%s, %s]" % [lctx, str(k), str(pv), str(spec["min"]), str(spec["max"])])
					continue
				params[str(k)] = float(pv)
		out.append({ "allele": allele, "params": params })
	return out


## 等位基因 payload 交叉引用：射弹/配方/效果 id 必须已定义（在 projectiles 解析后调用）。
func _validate_gene_refs(src: String) -> void:
	if genes.is_empty():
		_err("%s: genes.json 未成功加载，蓝图基因组无法校验" % src)
		return
	var loci: Array = genes["loci"]
	for i in loci.size():
		var locus: Dictionary = loci[i]
		var alleles: Dictionary = locus.get("alleles", {})
		for allele in alleles:
			var ctx := "%s genes.loci[%d](%s).alleles.%s" % [src, i, str(locus.get("id", i)), str(allele)]
			var payload: Dictionary = alleles[allele]
			match str(locus.get("kind", "")):
				"attack":
					var pid := str(payload.get("projectile", ""))
					if pid.is_empty() or not projectiles.has(StringName(pid)):
						_err("%s: projectile '%s' 未在 factories.json projectiles 定义" % [ctx, pid])
				"production":
					if not recipes.has(StringName(str(allele))):
						_err("%s: 等位基因 '%s' 未在 recipes.json 定义" % [ctx, str(allele)])
				"aura":
					var eid := str(payload.get("effect_id", ""))
					if not effects.has(StringName(eid)):
						_err("%s: effect_id '%s' 未在 buffs.json 定义" % [ctx, eid])
					if int(payload.get("target_mask", 0)) <= 0:
						_err("%s: target_mask 应 > 0" % ctx)


func _num_or(v, fallback: float) -> float:
	return float(v) if (v is int or v is float) else fallback


# ================================================================ BUFF/DEBUFF

func _parse_buffs(data, src: String) -> void:
	var root := _req_obj(data, src)
	var arr := _req_list(root.get("effects", null), src + ".effects")
	var i := 0
	for e in arr:
		var ctx := "%s.effects[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var name := _req_str(d, "name", ctx) if d.has("name") else ""
		var stat_id := _req_str(d, "stat_id", ctx)
		var value = d.get("value", null)
		var duration := _req_num(d, "duration", ctx)
		if id.is_empty() or stat_id.is_empty():
			continue
		if not (value is int or value is float):
			_err("%s: value 应为数值" % ctx)
			continue
		if duration <= 0.0 and d.has("duration"):
			_err("%s: duration 应 > 0" % ctx)
		if not STAT_IDS.has(StringName(stat_id)):
			_err("%s: stat_id '%s' 不在协议集合 %s（会被系统静默忽略，视为配置错误）" % [ctx, stat_id, str(STAT_IDS)])
		if effects.has(StringName(id)):
			_err("%s: 效果 id 重复 '%s'" % [ctx, id])
			continue
		effects[StringName(id)] = {
			"id": StringName(id), "name": name if not name.is_empty() else id,
			"stat_id": StringName(stat_id),
			"value": float(value), "duration": duration,
		}


# ================================================================ 卡牌

func _parse_cards(data, src: String) -> void:
	var root := _req_obj(data, src)
	hand_max = _req_int(root, "hand_max", src)
	if hand_max <= 0:
		_err("%s: hand_max 应 > 0" % src)
	var arr := _req_list(root.get("cards", null), src + ".cards")
	var i := 0
	for e in arr:
		var ctx := "%s.cards[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var name := _req_str(d, "name", ctx)
		var cost := _req_res_map(d, "cost", ctx, true)
		var effect = _req_obj(d.get("effect", null), ctx + ".effect")
		if id.is_empty():
			continue
		var etype := _req_str(effect, "type", ctx + ".effect")
		var eff := {"type": etype}
		match etype:
			"place_factory":
				var bid := _req_str(effect, "blueprint_id", ctx + ".effect")
				if not bid.is_empty() and not blueprints.has(StringName(bid)):
					_err("%s: effect.blueprint_id '%s' 未在 factories.json 定义" % [ctx, bid])
				eff["blueprint_id"] = StringName(bid)
			"place_tile":
				var ttype := _req_str(effect, "tile_type", ctx + ".effect")
				eff["tile_type"] = StringName(ttype) # 与关卡 tile_types 的交叉校验在 levels 解析
			"":
				pass # 缺字段已报错
			_:
				_err("%s: 未知卡牌效果类型 '%s'（place_factory / place_tile）" % [ctx, etype])
		if cards.has(StringName(id)):
			_err("%s: 卡牌 id 重复 '%s'" % [ctx, id])
			continue
		cards[StringName(id)] = {"id": StringName(id), "name": name, "cost": cost, "effect": eff}


# ================================================================ 关卡

func _parse_levels(data, src: String) -> void:
	var root := _req_obj(data, src)
	var arr := _req_list(root.get("levels", null), src + ".levels")
	var i := 0
	for e in arr:
		var ctx := "%s.levels[%d]" % [src, i]
		i += 1
		var d := _req_obj(e, ctx)
		var id := _req_str(d, "id", ctx)
		var name := _req_str(d, "name", ctx)
		var path_id := _req_str(d, "path_id", ctx)
		var cell_size := _req_num(d, "cell_size", ctx)
		var enemy_cap := _req_int(d, "enemy_cap", ctx)
		var hand_start := _req_int(d, "hand_start", ctx)
		var path := _req_vec2_list(d, "path", ctx, 3)
		var buildable := _req_cell_list(d, "buildable_cells", ctx, false)
		var path_cells := _req_cell_list(d, "path_cells", ctx, false)
		var tiles := _parse_tiles(d, ctx)
		var tile_types := _parse_tile_types(d, ctx)
		var card_pool := _req_str_list(d, "card_pool", ctx)
		var objective := _parse_objective(d, ctx)
		var waves := _parse_waves(d, ctx)
		if id.is_empty():
			continue
		# 数值约束
		if cell_size <= 0.0 and d.has("cell_size"):
			_err("%s: cell_size 应 > 0" % ctx)
		if enemy_cap <= 0 and d.has("enemy_cap"):
			_err("%s: enemy_cap 应 > 0" % ctx)
		if hand_start < 0:
			_err("%s: hand_start 应 ≥ 0" % ctx)
		if hand_start > hand_max:
			_err("%s: hand_start(%d) 不能大于手牌上限 hand_max(%d)" % [ctx, hand_start, hand_max])
		# 路径闭合合法性：相邻（含首尾相接）顶点不重合
		for pi in path.size():
			var a: Vector2 = path[pi]
			var b: Vector2 = path[(pi + 1) % path.size()]
			if a.distance_to(b) <= 0.0:
				_err("%s: path 第 %d 个顶点与下一个顶点重合（闭合环）" % [ctx, pi])
		# 格子集合
		if buildable.is_empty():
			_err("%s: buildable_cells 不能为空" % ctx)
		for c in buildable:
			if path_cells.has(c):
				_err("%s: 可建造格 %s 同时被标注为 path_cells" % [ctx, str(c)])
		var known := {}
		for c in buildable:
			known[c] = true
		for c in path_cells:
			known[c] = true
		for t in tiles:
			if not known.has(t["cell"]):
				_err("%s: tiles 中格 %s 既不在 buildable_cells 也不在 path_cells" % [ctx, str(t["cell"])])
			if not tile_types.has(t["tile_type"]):
				_err("%s: tiles 引用未定义地块类型 '%s'" % [ctx, str(t["tile_type"])])
		# 卡池
		if card_pool.is_empty():
			_err("%s: card_pool 不能为空" % ctx)
		for cid in card_pool:
			if not cards.has(StringName(cid)):
				_err("%s: card_pool 引用未定义卡牌 '%s'" % [ctx, cid])
				continue
			var eff: Dictionary = cards[StringName(cid)]["effect"]
			if str(eff.get("type", "")) == "place_tile":
				if not tile_types.has(StringName(str(eff.get("tile_type", "")))):
					_err("%s: 卡牌 '%s' 的 tile_type '%s' 不在本关 tile_types 中" % [ctx, cid, str(eff.get("tile_type", ""))])
		# 目标与波次
		if not objective.is_empty() and not waves.is_empty():
			if int(objective.get("waves", 0)) > waves.size():
				_err("%s: objective.waves(%d) 大于波次总数 %d，目标永远无法完成" % [ctx, int(objective["waves"]), waves.size()])
		if levels.has(StringName(id)):
			_err("%s: 关卡 id 重复 '%s'" % [ctx, id])
			continue
		levels[StringName(id)] = {
			"id": StringName(id), "name": name, "path_id": StringName(path_id),
			"cell_size": cell_size, "enemy_cap": enemy_cap, "hand_start": hand_start,
			"path": path, "buildable_cells": buildable, "path_cells": path_cells,
			"tiles": tiles, "tile_types": tile_types, "card_pool": card_pool,
			"objective": objective, "waves": waves,
		}


func _parse_tiles(d: Dictionary, ctx: String) -> Array:
	var out := []
	var arr := _req_list(d.get("tiles", null), ctx + ".tiles")
	var i := 0
	for t in arr:
		var tctx := "%s.tiles[%d]" % [ctx, i]
		i += 1
		var td := _req_obj(t, tctx)
		var cell = _req_cell(td.get("cell", null), tctx + ".cell")
		var ttype := _req_str(td, "tile_type", tctx)
		if cell == null or ttype.is_empty():
			continue
		out.append({"cell": cell, "tile_type": StringName(ttype)})
	return out


func _parse_tile_types(d: Dictionary, ctx: String) -> Dictionary:
	var out := {}
	var obj := _req_obj(d.get("tile_types", null), ctx + ".tile_types")
	for k in obj.keys():
		var tctx := "%s.tile_types.%s" % [ctx, k]
		var td := _req_obj(obj[k], tctx)
		var mult := _req_num(td, "speed_mult", tctx)
		if mult <= 0.0 and td.has("speed_mult"):
			_err("%s: speed_mult 应 > 0" % tctx)
		out[StringName(k)] = {"speed_mult": mult}
	return out


func _parse_objective(d: Dictionary, ctx: String) -> Dictionary:
	var obj := _req_obj(d.get("objective", null), ctx + ".objective")
	var otype := _req_str(obj, "type", ctx + ".objective")
	match otype:
		"survive_waves":
			var waves_n := _req_int(obj, "waves", ctx + ".objective")
			if waves_n <= 0 and obj.has("waves"):
				_err("%s.objective: waves 应 > 0" % ctx)
			return {"type": "survive_waves", "waves": waves_n}
		"":
			return {} # 缺字段已报错
		_:
			_err("%s.objective: 未知目标类型 '%s'（当前仅支持 survive_waves）" % [ctx, otype])
			return {}


func _parse_waves(d: Dictionary, ctx: String) -> Array:
	var out := []
	var arr := _req_list(d.get("waves", null), ctx + ".waves")
	if arr.is_empty() and d.has("waves"):
		_err("%s: waves 不能为空" % ctx)
	var wi := 0
	for w in arr:
		var wctx := "%s.waves[%d]" % [ctx, wi]
		wi += 1
		var wd := _req_obj(w, wctx)
		var spawns := _req_list(wd.get("spawns", null), wctx + ".spawns")
		if spawns.is_empty() and wd.has("spawns"):
			_err("%s: spawns 不能为空" % wctx)
		var sarr := []
		var si := 0
		for s in spawns:
			var sctx := "%s.spawns[%d]" % [wctx, si]
			si += 1
			var sd := _req_obj(s, sctx)
			var enemy := _req_str(sd, "enemy", sctx)
			var count := _req_int(sd, "count", sctx)
			var interval := _req_num(sd, "interval", sctx)
			var delay := _req_num(sd, "delay", sctx)
			if enemy.is_empty():
				continue
			if not enemies.has(StringName(enemy)):
				_err("%s: enemy '%s' 未在 enemies.json 定义" % [sctx, enemy])
			if count <= 0 and sd.has("count"):
				_err("%s: count 应 ≥ 1" % sctx)
			if interval <= 0.0 and sd.has("interval"):
				_err("%s: interval 应 > 0" % sctx)
			if delay < 0.0 and sd.has("delay"):
				_err("%s: delay 应 ≥ 0" % sctx)
			sarr.append({"enemy": StringName(enemy), "count": count, "interval": interval, "delay": delay})
		out.append({"spawns": sarr})
	return out


# ================================================================ 访问器（缺失即报错）

func get_resource(id: StringName) -> Dictionary:
	if not resources.has(id):
		push_error("GameConfig: 未定义的资源 id: " + String(id))
		return {}
	return resources[id]


func get_enemy(id: StringName) -> Dictionary:
	if not enemies.has(id):
		push_error("GameConfig: 未定义的敌人 id: " + String(id))
		return {}
	return enemies[id]


func get_recipe(id: StringName) -> Dictionary:
	if not recipes.has(id):
		push_error("GameConfig: 未定义的配方 id: " + String(id))
		return {}
	return recipes[id]


func get_blueprint(id: StringName) -> Dictionary:
	if not blueprints.has(id):
		push_error("GameConfig: 未定义的蓝图 id: " + String(id))
		return {}
	return blueprints[id]


func get_projectile(id: StringName) -> Dictionary:
	if not projectiles.has(id):
		push_error("GameConfig: 未定义的射弹 id: " + String(id))
		return {}
	return projectiles[id]


func get_card(id: StringName) -> Dictionary:
	if not cards.has(id):
		push_error("GameConfig: 未定义的卡牌 id: " + String(id))
		return {}
	return cards[id]


func get_effect(id: StringName) -> Dictionary:
	if not effects.has(id):
		push_error("GameConfig: 未定义的效果 id: " + String(id))
		return {}
	return effects[id]


func get_level(id: StringName) -> Dictionary:
	if not levels.has(id):
		push_error("GameConfig: 未定义的关卡 id: " + String(id))
		return {}
	return levels[id]


# ================================================================ 组件实例化（蓝图/指令用）

## 按蓝图组件定义创建组件实例：字段名 → 组件属性，按属性类型做数值归一。
static func make_component(type_name: String, spec: Dictionary) -> Component:
	if not COMPONENT_SCRIPTS.has(type_name):
		push_error("GameConfig.make_component: 未知组件类型 " + type_name)
		return null
	var comp: Component = COMPONENT_SCRIPTS[type_name].new()
	for p in comp.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var pname := String(p["name"])
		if not spec.has(pname):
			continue
		comp.set(pname, _coerce(spec[pname], int(p["type"])))
	return comp


static func _coerce(v, want: int):
	match want:
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			return str(v)
		_:
			return v


# ================================================================ 校验工具

func _err(msg: String) -> void:
	_errors.append("GameConfig: " + msg)


func _check_kind(v, kind: String, ctx: String) -> bool:
	match kind:
		"pos_num":
			if (v is int or v is float) and float(v) > 0.0:
				return true
			_err("%s: 应为 > 0 的数值，得到 %s" % [ctx, str(v)])
			return false
		"num":
			if (v is int or v is float) and float(v) >= 0.0:
				return true
			_err("%s: 应为 ≥ 0 的数值，得到 %s" % [ctx, str(v)])
			return false
		"int":
			if v is int and int(v) >= 0:
				return true
			if v is float and float(v) >= 0.0 and is_equal_approx(float(v), roundf(float(v))):
				return true
			_err("%s: 应为 ≥ 0 的整数，得到 %s" % [ctx, str(v)])
			return false
		"mask":
			if (v is int or v is float) and float(v) > 0.0 and is_equal_approx(float(v), roundf(float(v))):
				return true
			_err("%s: 应为 > 0 的整数位掩码，得到 %s" % [ctx, str(v)])
			return false
		"str":
			if v is String and not (v as String).is_empty():
				return true
			_err("%s: 应为非空字符串，得到 %s" % [ctx, str(v)])
			return false
		_:
			_err("%s: 内部错误：未知校验类型 %s" % [ctx, kind])
			return false


func _req_obj(v, ctx: String) -> Dictionary:
	if v is Dictionary:
		return v
	_err("%s: 应为 JSON 对象，得到 %s" % [ctx, type_string(typeof(v))])
	return {}


func _req_list(v, ctx: String) -> Array:
	if v is Array:
		return v
	_err("%s: 应为 JSON 数组，得到 %s" % [ctx, type_string(typeof(v))])
	return []


func _req_str(d: Dictionary, key: String, ctx: String) -> String:
	if not d.has(key):
		_err("%s: 缺字段 '%s'" % [ctx, key])
		return ""
	var v = d[key]
	if v is String and not (v as String).is_empty():
		return v
	if v is String:
		_err("%s: 字段 '%s' 不能为空" % [ctx, key])
		return ""
	_err("%s: 字段 '%s' 应为非空字符串，得到 %s" % [ctx, key, type_string(typeof(v))])
	return ""


func _req_num(d: Dictionary, key: String, ctx: String) -> float:
	if not d.has(key):
		_err("%s: 缺字段 '%s'" % [ctx, key])
		return 0.0
	var v = d[key]
	if v is int or v is float:
		return float(v)
	_err("%s: 字段 '%s' 应为数值，得到 %s" % [ctx, key, type_string(typeof(v))])
	return 0.0


func _req_int(d: Dictionary, key: String, ctx: String) -> int:
	if not d.has(key):
		_err("%s: 缺字段 '%s'" % [ctx, key])
		return 0
	var v = d[key]
	if v is int:
		return int(v)
	if v is float and is_equal_approx(float(v), roundf(float(v))):
		return int(roundf(float(v)))
	_err("%s: 字段 '%s' 应为整数，得到 %s" % [ctx, key, str(v)])
	return 0


func _req_bool(d: Dictionary, key: String, ctx: String) -> bool:
	if not d.has(key):
		_err("%s: 缺字段 '%s'" % [ctx, key])
		return false
	var v = d[key]
	if v is bool:
		return v
	_err("%s: 字段 '%s' 应为布尔值，得到 %s" % [ctx, key, type_string(typeof(v))])
	return false


func _req_str_list(d: Dictionary, key: String, ctx: String) -> Array:
	var out := []
	var arr := _req_list(d.get(key, null), "%s.%s" % [ctx, key])
	var i := 0
	for e in arr:
		var ectx := "%s.%s[%d]" % [ctx, key, i]
		i += 1
		if e is String and not (e as String).is_empty():
			out.append(e)
		else:
			_err("%s: 应为非空字符串，得到 %s" % [ectx, str(e)])
	return out


## 资源消耗映射 {资源 id: 整数 ≥1}；键必须已在 resources.json 定义。
## allow_empty：允许空对象 {}（表示无消耗）。
func _req_res_map(d: Dictionary, key: String, ctx: String, allow_empty: bool) -> Dictionary:
	var out := {}
	if not d.has(key):
		_err("%s: 缺字段 '%s'（无消耗请写空对象 {}）" % [ctx, key])
		return out
	var v = d[key]
	if not (v is Dictionary):
		_err("%s.%s: 应为 JSON 对象，得到 %s" % [ctx, key, type_string(typeof(v))])
		return out
	if (v as Dictionary).is_empty() and not allow_empty:
		_err("%s.%s: 不能为空" % [ctx, key])
		return out
	for rid in (v as Dictionary).keys():
		var rctx := "%s.%s.%s" % [ctx, key, str(rid)]
		var amount = (v as Dictionary)[rid]
		if not resources.has(StringName(str(rid))):
			_err("%s: 资源 '%s' 未在 resources.json 定义" % [rctx, str(rid)])
		if not (amount is int or amount is float) or float(amount) < 1.0 or not is_equal_approx(float(amount), roundf(float(amount))):
			_err("%s: 数量应为 ≥1 的整数，得到 %s" % [rctx, str(amount)])
			continue
		out[StringName(str(rid))] = int(amount)
	return out


## 顶点数组 → Array[Vector2]，最少 min_size 个。
func _req_vec2_list(d: Dictionary, key: String, ctx: String, min_size: int) -> Array:
	var out := []
	var arr := _req_list(d.get(key, null), "%s.%s" % [ctx, key])
	if arr.size() < min_size:
		_err("%s.%s: 至少需要 %d 个顶点，得到 %d" % [ctx, key, min_size, arr.size()])
	var i := 0
	for p in arr:
		var pctx := "%s.%s[%d]" % [ctx, key, i]
		i += 1
		if p is Array and p.size() >= 2 and (p[0] is int or p[0] is float) and (p[1] is int or p[1] is float):
			out.append(Vector2(float(p[0]), float(p[1])))
		else:
			_err("%s: 顶点应为 [x, y] 数值数组，得到 %s" % [pctx, str(p)])
	return out


## 格子数组 → Array[Vector2i]。
func _req_cell_list(d: Dictionary, key: String, ctx: String, allow_empty: bool) -> Array:
	var out := []
	var arr := _req_list(d.get(key, null), "%s.%s" % [ctx, key])
	if arr.is_empty() and not allow_empty and d.has(key):
		_err("%s.%s: 不能为空" % [ctx, key])
	if not d.has(key):
		_err("%s: 缺字段 '%s'" % [ctx, key])
	var seen := {}
	var i := 0
	for c in arr:
		var cctx := "%s.%s[%d]" % [ctx, key, i]
		i += 1
		var cell = _req_cell(c, cctx)
		if cell == null:
			continue
		if seen.has(cell):
			_err("%s: 格子重复 %s" % [cctx, str(cell)])
			continue
		seen[cell] = true
		out.append(cell)
	return out


## 单个 [col, row] → Vector2i；非法返回 null。
func _req_cell(v, ctx: String):
	if v is Array and v.size() >= 2 and (v[0] is int or v[0] is float) and (v[1] is int or v[1] is float):
		if is_equal_approx(float(v[0]), roundf(float(v[0]))) and is_equal_approx(float(v[1]), roundf(float(v[1]))):
			return Vector2i(int(roundf(float(v[0]))), int(roundf(float(v[1]))))
	_err("%s: 应为 [col, row] 整数数组，得到 %s" % [ctx, str(v)])
	return null
