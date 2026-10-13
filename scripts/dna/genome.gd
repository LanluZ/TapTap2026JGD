class_name Genome
extends RefCounted
## DNA 基因组（规格 docs/superpowers/specs/2026-10-13-dna-fusion-design.md）。
## 基因组 = Array，长度 = genes.json loci 数（7），每座为 null（无基因）
## 或 {"allele": String, "params": Dictionary}。
## 本类是纯数据+纯函数：表达（基因型→组件规格）、减数分裂（breed）、命名，
## 无世界/Node 依赖，可 headless 单测。

static var _next_child: int = 0 # 动态子代蓝图 id 计数器


# ================================================================ 表达

## 基因组 → 组件规格数组（GameConfig.make_component 可直接实例化的 spec）。
## 无非法组合约束：座上有基因即表达，缺的数值用 genes.json 默认值补。
static func express(genome: Array, genes: Dictionary, blueprint_id: String, display_name: String) -> Array:
	var loci: Array = genes.get("loci", [])
	var specs: Array = [{
		"type": "Factory", "blueprint_id": blueprint_id,
		"genome": genome.duplicate(true), "display_name": display_name,
	}, { "type": "GridPosition" }]
	var stats := _params_of(_at(genome, 1), loci, 1)
	# 座0 攻击类型 + 座1 数值
	var attack = _at(genome, 0)
	if attack != null:
		var payload: Dictionary = _allele_payload(loci, 0, str(attack["allele"]))
		specs.append({
			"type": "Attack",
			"range": float(stats.get("range", _default_param(loci, 1, "range"))),
			"damage": float(stats.get("damage", _default_param(loci, 1, "damage"))),
			"cooldown": float(stats.get("cooldown", _default_param(loci, 1, "cooldown"))),
			"target_mask": 1, "projectile": str(payload.get("projectile", "")),
		})
	# 座2 生产（Production 必配 ResourceBuffer，架构 §4 约束）
	var prod = _at(genome, 2)
	var buffer_flush := 1.0 # buffer 座缺省时的兜底汇入周期
	var buffer = _at(genome, 4)
	if buffer != null:
		buffer_flush = float(_allele_payload(loci, 4, str(buffer["allele"])).get("flush_interval", 1.0))
	if prod != null:
		var iparams := _params_of(prod, loci, 2)
		specs.append({
			"type": "Production", "recipe_id": str(prod["allele"]),
			"interval": float(iparams.get("interval", _default_param(loci, 2, "interval"))),
		})
		specs.append({ "type": "ResourceBuffer", "flush_interval": buffer_flush })
	elif buffer != null:
		specs.append({ "type": "ResourceBuffer", "flush_interval": buffer_flush })
	# 座3 光环
	var aura = _at(genome, 3)
	if aura != null:
		var apayload := _allele_payload(loci, 3, str(aura["allele"]))
		var aparams := _params_of(aura, loci, 3)
		specs.append({
			"type": "Aura",
			"radius": float(aparams.get("radius", _default_param(loci, 3, "radius"))),
			"effect_id": str(apayload.get("effect_id", "")),
			"target_mask": int(apayload.get("target_mask", 0)),
		})
	return specs


## 基因组 → 简短人读摘要（UI 卡面 desc 用）。
static func summary(genome: Array, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var parts: Array = []
	for i in genome.size():
		var g = _at(genome, i)
		if g == null or i >= loci.size():
			continue
		parts.append("%s:%s" % [str((loci[i] as Dictionary).get("id", i)), str(g["allele"])])
	if parts.is_empty():
		return "空基因组"
	return " · ".join(parts)


# ================================================================ 减数分裂

## 配子形成(每座50%保留) → 交叉互换(50%概率切段) → 受精(同座随机取一) → 突变。
## rng 由调用方提供（带种子 = 可复现）。纯函数，无副作用。
static func breed(a: Array, b: Array, genes: Dictionary, rng: RandomNumberGenerator) -> Array:
	var n: int = genes.get("loci", []).size()
	var ga := _gamete(a, genes, rng)
	var gb := _gamete(b, genes, rng)
	if n > 1 and rng.randf() < float(genes.get("crossover", 0.5)):
		var cut := rng.randi_range(1, n - 1)
		for i in range(cut, n):
			var tmp = ga[i]
			ga[i] = gb[i]
			gb[i] = tmp
	var child: Array = []
	for i in n:
		var pick = ga[i] if rng.randf() < 0.5 else gb[i]
		child.append(_mutate(pick, i, genes, rng))
	return child


## 配子：每座以 gamete_keep 概率保留（深拷贝，不共享引用）。
static func _gamete(genome: Array, genes: Dictionary, rng: RandomNumberGenerator) -> Array:
	var keep := float(genes.get("gamete_keep", 0.5))
	var out: Array = []
	for g in genome:
		out.append((g as Dictionary).duplicate(true) if (g != null and rng.randf() < keep) else null)
	return out


## 突变：数值座按 ±drift 浮动并钳回 [min,max]；其余座换成同组随机等位基因。
static func _mutate(entry, idx: int, genes: Dictionary, rng: RandomNumberGenerator):
	if entry == null:
		return null # 空座无基因可突变
	var loci: Array = genes.get("loci", [])
	if idx >= loci.size():
		return entry
	var locus: Dictionary = loci[idx]
	var mut: Dictionary = genes.get("mutation", {})
	var rate := float(mut.get("redundant_rate", 0.2)) if str(locus.get("kind", "")) == "redundant" \
		else float(mut.get("rate", 0.05))
	if rng.randf() >= rate:
		return entry
	var out: Dictionary = (entry as Dictionary).duplicate(true)
	if str(locus.get("kind", "")) == "stats":
		var drift := float(mut.get("drift", 0.15))
		var params: Dictionary = out.get("params", {})
		var new_params := {}
		for k in params:
			var spec: Dictionary = (locus.get("params", {}) as Dictionary).get(k, {})
			var v := float(params[k]) * (1.0 + rng.randf_range(-drift, drift))
			params[k] = clampf(v, float(spec.get("min", 0.0)), float(spec.get("max", INF)))
		out["params"] = params
	else:
		var alleles: Dictionary = locus.get("alleles", {})
		if not alleles.is_empty():
			var keys := alleles.keys()
			out["allele"] = str(keys[rng.randi_range(0, keys.size() - 1)])
	return out


# ================================================================ 表型命名与碱基编码

## 表型命名（策划案 15.6/15.9）：按表达出的功能段拼接中文标签，顺序 = 光环→生产→攻击。
## 标签来自 genes.json 等位基因 payload 的 label 字段，代码零硬编码；无标签时为"空机"。
const NAME_ORDER := [3, 2, 0] # 座位索引：光环、生产、攻击（示例："采矿轻炮""缓速矿机""发电重炮"）

static func phenotype_name(genome: Array, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var parts: Array = []
	for idx in NAME_ORDER:
		var g = _at(genome, idx)
		if g == null or idx >= loci.size():
			continue
		var label := str(_allele_payload(loci, idx, str((g as Dictionary).get("allele", ""))).get("label", ""))
		if not label.is_empty():
			parts.append(label)
	if parts.is_empty():
		return "空机"
	return "".join(parts)


## 基因组 → 碱基链（DNA 检视玩家视图用，策划案 15.8）：
## 每座一个碱基字母（A/T/C/G，等位基因名确定性哈希）；空座为 "—"。
const BASES := "ATCG"

static func base_letters(genome: Array, genes: Dictionary) -> Array:
	var loci: Array = genes.get("loci", [])
	var out: Array = []
	for i in loci.size():
		var g = _at(genome, i)
		if g == null:
			out.append("—")
			continue
		out.append(BASES[_djb2(str((g as Dictionary).get("allele", ""))) % 4])
	return out


## 碱基互补（A↔T、C↔G）；非碱基字符原样返回。
static func complement(base: String) -> String:
	match base:
		"A": return "T"
		"T": return "A"
		"C": return "G"
		"G": return "C"
		_: return base


## djb2 变体：确定性哈希（同等位基因跨运行同碱基，不依赖 String.hash 的版本稳定性）。
static func _djb2(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = (h * 33 + s.unicode_at(i)) & 0x7FFFFFFF
	return h


# ================================================================ 动态子代注册

## 注册融合子代：动态蓝图（genome 表达）+ 对应卡牌写入 config，返回子代卡 id。
## 放置走既有 place_factory 通道，校验/实例化零改动。
static func register_child(config, genome: Array, display_name: String) -> StringName:
	_next_child += 1
	var bid := "fusion_%d" % _next_child
	config.blueprints[StringName(bid)] = {
		"id": StringName(bid), "name": display_name, "cost": {},
		"genome": genome.duplicate(true),
	}
	var cid := "card_" + bid
	config.cards[StringName(cid)] = {
		"id": StringName(cid), "name": display_name, "cost": {},
		"effect": { "type": "place_factory", "blueprint_id": StringName(bid) },
	}
	return StringName(cid)


# ================================================================ 文本生成（UI 卡面用）

## 基因组 → DNA 序列多行文本（每座一行：序号 座名: 等位基因 (参数)）。
static func sequence_text(genome: Array, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var lines: Array = []
	for i in loci.size():
		var lid := str((loci[i] as Dictionary).get("id", i))
		var g = _at(genome, i)
		if g == null:
			lines.append("%d. %s: —" % [i + 1, lid])
			continue
		var s := "%d. %s: %s" % [i + 1, lid, str((g as Dictionary).get("allele", ""))]
		var params: Dictionary = (g as Dictionary).get("params", {})
		if not params.is_empty():
			var kv: Array = []
			for k in params:
				kv.append("%s=%s" % [k, str(params[k])])
			s += "（%s）" % ", ".join(kv)
		lines.append(s)
	return "\n".join(lines)


## 基因组 → 人话效果描述（悬停 tooltip 用）：按表达出的组件逐行描述。
static func effect_text(genome: Array, genes: Dictionary, config) -> String:
	var lines: Array = []
	for spec in express(genome, genes, "", ""):
		match str((spec as Dictionary).get("type", "")):
			"Attack":
				var pid := str(spec.get("projectile", ""))
				var pnote := ("，弹: " + pid) if not pid.is_empty() else ""
				lines.append("攻击: 伤害%.1f 射程%.0f 冷却%.1fs%s" % [
					float(spec["damage"]), float(spec["range"]), float(spec["cooldown"]), pnote])
			"Production":
				var r: Dictionary = config.get_recipe(StringName(str(spec.get("recipe_id", ""))))
				var outs: Array = []
				for k in r.get("outputs", {}):
					outs.append("%s×%d" % [_res_name(config, k), int(r["outputs"][k])])
				var ins: Array = []
				for k in r.get("inputs", {}):
					ins.append("%s×%d" % [_res_name(config, k), int(r["inputs"][k])])
				var line := "生产: %s / 每%.1fs" % [", ".join(outs), float(spec["interval"])]
				if not ins.is_empty():
					line += "（输入 %s）" % ", ".join(ins)
				lines.append(line)
			"Aura":
				var eid := StringName(str(spec.get("effect_id", "")))
				var ename := str((config.get_effect(eid) as Dictionary).get("name", eid))
				lines.append("光环: %s，半径%.0f" % [ename, float(spec["radius"])])
			"ResourceBuffer":
				lines.append("缓冲: 每%.1fs 汇出" % float(spec["flush_interval"]))
	if lines.is_empty():
		lines.append("无功能组件（空基因组）")
	return "\n".join(lines)


static func _res_name(config, rid) -> String:
	var r: Dictionary = config.get_resource(rid)
	return str(r.get("name", rid))


# ================================================================ 工具

static func _at(genome: Array, idx: int):
	return genome[idx] if idx < genome.size() else null


static func _allele_payload(loci: Array, idx: int, allele: String) -> Dictionary:
	if idx >= loci.size():
		return {}
	return ((loci[idx] as Dictionary).get("alleles", {}) as Dictionary).get(allele, {})


static func _params_of(entry, loci: Array, idx: int) -> Dictionary:
	if entry == null or idx >= loci.size():
		return {}
	var declared: Dictionary = (loci[idx] as Dictionary).get("params", {})
	var out := {}
	for k in declared:
		var v = (entry as Dictionary).get("params", {}).get(k, null)
		if v != null:
			out[k] = float(v)
	return out


static func _default_param(loci: Array, idx: int, key: String) -> float:
	if idx >= loci.size():
		return 0.0
	var spec: Dictionary = ((loci[idx] as Dictionary).get("params", {}) as Dictionary).get(key, {})
	return float(spec.get("default", 0.0))
