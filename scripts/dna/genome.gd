class_name Genome
extends RefCounted
## DNA 基因组（二倍体：每座一对碱基）。
## 基因组 = Array，长度 = genes.json loci 数（9），每座为 null（无基因）
## 或 {"bases": String, "params": Dictionary, "alt_params": Dictionary?}。
##
## 碱基是基因型唯一数据源：座 code→等位基因表在 genes.json，解码统一走 allele_of_letter。
## 一个字母 = 一个等位基因 = 一份特性；两个不同字母 = 两种特性都表达（表达出 "alt" 通道）。
## 作者层（factories.json）可写 {"allele", "params"}，GameConfig._validate_genome
## 校验后归一化为 bases；运行时一律 bases（单字母按纯合补齐）。
## 本类是纯数据+纯函数：表达（基因型→组件规格）、减数分裂（breed）、命名，
## 无世界/Node 依赖，可 headless 单测。

static var _next_child: int = 0 # 动态子代蓝图 id 计数器

const BASES := ["A", "T", "C", "G"]
const NUMERALS := ["①", "②"]


# ================================================================ 碱基解码

## entry 的一对碱基 → 字母数组（单字母旧写法读作 1 个字母，表达时视为纯合）。
static func letters(entry) -> Array:
	if not (entry is Dictionary):
		return []
	var s := str((entry as Dictionary).get("bases", ""))
	var out: Array = []
	for i in s.length():
		var ch := s.substr(i, 1)
		if ch in BASES:
			out.append(ch)
	return out


## 座声明过的碱基码集合（stats 座 = allele_code + alt_code）。
static func base_codes(locus: Dictionary) -> Array:
	var out: Array = []
	if str(locus.get("kind", "")) == "stats":
		for k in ["allele_code", "alt_code"]:
			var c := str(locus.get(k, ""))
			if not c.is_empty() and not (c in out):
				out.append(c)
		return out
	var alleles: Dictionary = locus.get("alleles", {})
	for a in alleles:
		var c := str((alleles[a] as Dictionary).get("code", ""))
		if not c.is_empty():
			out.append(c)
	return out


## 座 + 单个碱基 → 等位基因名；未声明返回 ""。
static func allele_of_letter(locus: Dictionary, letter: String) -> String:
	if letter.is_empty():
		return ""
	if str(locus.get("kind", "")) == "stats":
		if letter == str(locus.get("allele_code", "")):
			return str(locus.get("allele_id", ""))
		if letter == str(locus.get("alt_code", "")):
			return str(locus.get("alt_allele_id", ""))
		return ""
	var alleles: Dictionary = locus.get("alleles", {})
	for a in alleles:
		if str((alleles[a] as Dictionary).get("code", "")) == letter:
			return str(a)
	return ""


## 主字母解码（兼容单等位基因旧调用点）。
static func allele_at(entry, idx: int, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var ls := letters(entry)
	if idx >= loci.size() or ls.is_empty():
		return ""
	return allele_of_letter(loci[idx], str(ls[0]))


## 该座全部字母解码（表现层逐部件用）：杂合返回 2 个，纯合/单字母返回 1 个。
static func alleles_at(entry, idx: int, genes: Dictionary) -> Array:
	var loci: Array = genes.get("loci", [])
	if idx >= loci.size():
		return []
	var out: Array = []
	for letter in letters(entry):
		var a := allele_of_letter(loci[idx], str(letter))
		if not a.is_empty() and not (a in out):
			out.append(a)
	return out


## 兼容包装：bases（1~2 字母）→ 主字母的等位基因名。
static func allele_of_bases(locus: Dictionary, bases: String) -> String:
	var ls := letters({ "bases": bases })
	if ls.is_empty():
		return ""
	return allele_of_letter(locus, str(ls[0]))


## 座 + 等位基因名 → 碱基（未定义返回 ""）。
static func bases_of_allele(locus: Dictionary, allele: String) -> String:
	if str(locus.get("kind", "")) == "stats":
		if allele == str(locus.get("allele_id", "")):
			return str(locus.get("allele_code", ""))
		if allele == str(locus.get("alt_allele_id", "")):
			return str(locus.get("alt_code", ""))
		return ""
	return str(((locus.get("alleles", {}) as Dictionary).get(allele, {}) as Dictionary).get("code", ""))


# ================================================================ 表达

## 亲水座索引（genes.json 座序：aura 3 → hydro 4 → buffer 5 → redundant_a 6 → redundant_b 7
## → targeting 8）。座序再动时改这里一处，并靠 express 里的 kind 断言出声——否则
## kind 不符会静默把所有建筑的亲水效果回落到漠水。
const HYDRO_IDX := 4

## 基因组 → 组件规格数组（GameConfig.make_component 可直接实例化的 spec）。
## 杂合座在 spec 里多输出一个 "alt" 字典（第二条特性）；纯合/空座不输出 alt，组件走单通道原路径。
## 无非法组合约束：座上有基因即表达，缺的数值用 genes.json 默认值补。
static func express(genome: Array, genes: Dictionary, blueprint_id: String, display_name: String) -> Array:
	var loci: Array = genes.get("loci", [])
	var specs: Array = [{
		"type": "Factory", "blueprint_id": blueprint_id,
		"genome": genome.duplicate(true), "display_name": display_name,
	}, { "type": "GridPosition" }]
	# 座1 数值：params 绑第一个字母、alt_params 绑第二个字母（缺失回落主值）
	var stats_main := _params_of(_at(genome, 1), loci, 1, "params")
	var stats_alt := _params_of(_at(genome, 1), loci, 1, "alt_params")
	if stats_alt.is_empty():
		stats_alt = stats_main
	# 座4 亲水：两个字母各带一条水基因（组件级字段，与通道数无关）
	var hydro_pair := hydro_pair_of(genome, genes)
	# 座8 瞄准：两个字母各一条策略（次为空 = 只有一条通道）
	var tgt := targeting_pair_of(genome, genes)
	# 座0 攻击 + 座1 数值 → Attack（杂合时带 alt 通道）
	var att := alleles_at(_at(genome, 0), 0, genes)
	if not att.is_empty():
		var spec := _attack_spec(loci, str(att[0]), stats_main, tgt[0], hydro_pair)
		if att.size() >= 2:
			var second := _attack_spec(loci, str(att[1]), stats_alt, tgt[1], hydro_pair)
			second.erase("type")
			second.erase("target_mask")
			second.erase("hydro")
			second.erase("hydro2")
			spec["alt"] = second
		specs.append(spec)
	# 座2 生产（Production 必配 ResourceBuffer，架构 §4 约束）
	var prod := alleles_at(_at(genome, 2), 2, genes)
	if not prod.is_empty():
		var iparams := _params_of(_at(genome, 2), loci, 2, "params")
		var pspec := {
			"type": "Production", "recipe_id": str(prod[0]),
			"interval": float(iparams.get("interval", _default_param(loci, 2, "interval"))),
			"hydro": hydro_pair[0], "hydro2": hydro_pair[1],
		}
		if prod.size() >= 2:
			var palt := _params_of(_at(genome, 2), loci, 2, "alt_params")
			pspec["alt"] = {
				"recipe_id": str(prod[1]),
				"interval": float(palt.get("interval", _default_param(loci, 2, "interval"))),
			}
		specs.append(pspec)
	# 座5 后勤：有生产或后勤基因才配 ResourceBuffer；杂合取两周期里较快（小）的一个
	var buf := alleles_at(_at(genome, 5), 5, genes)
	if not prod.is_empty() or not buf.is_empty():
		specs.append({ "type": "ResourceBuffer", "flush_interval": _buffer_flush(genome, genes) })
	# 座3 光环（杂合时两个圈同时生效）
	var aura := alleles_at(_at(genome, 3), 3, genes)
	if not aura.is_empty():
		var aparams := _params_of(_at(genome, 3), loci, 3, "params")
		var aspec := _aura_spec(loci, str(aura[0]), aparams)
		if aura.size() >= 2:
			var aalt := _params_of(_at(genome, 3), loci, 3, "alt_params")
			var second := _aura_spec(loci, str(aura[1]), aalt)
			second.erase("type")
			aspec["alt"] = second
		specs.append(aspec)
	return specs


static func _attack_spec(loci: Array, allele: String, stats: Dictionary, targeting: String, hydro_pair: Array) -> Dictionary:
	var payload: Dictionary = _allele_payload(loci, 0, allele)
	return {
		"type": "Attack",
		"range": float(stats.get("range", _default_param(loci, 1, "range"))),
		"damage": float(stats.get("damage", _default_param(loci, 1, "damage"))),
		"cooldown": float(stats.get("cooldown", _default_param(loci, 1, "cooldown"))),
		"target_mask": 1, "targeting": targeting,
		"projectile": str(payload.get("projectile", "")),
		"hydro": hydro_pair[0], "hydro2": hydro_pair[1],
	}


static func _aura_spec(loci: Array, allele: String, params: Dictionary) -> Dictionary:
	var payload: Dictionary = _allele_payload(loci, 3, allele)
	return {
		"type": "Aura",
		"radius": float(params.get("radius", _default_param(loci, 3, "radius"))),
		"effect_id": str(payload.get("effect_id", "")),
		"target_mask": int(payload.get("target_mask", 0)),
	}


## 该座两个字母各自的亲水等位基因：[主, 次]；次为空串 = 只有一条水基因。
static func hydro_pair_of(genome: Array, genes: Dictionary) -> Array:
	var out: Array = [&"hydro_none", &""]
	var loci: Array = genes.get("loci", [])
	if not _hydro_locus_ready(loci):
		return out
	var ls := letters(_at(genome, HYDRO_IDX))
	if ls.size() >= 1:
		var a := allele_of_letter(loci[HYDRO_IDX], str(ls[0]))
		if not a.is_empty():
			out[0] = StringName(a)
	if ls.size() >= 2:
		var b := allele_of_letter(loci[HYDRO_IDX], str(ls[1]))
		if not b.is_empty() and b != str(out[0]):
			out[1] = StringName(b)
	return out


## 瞄准座两字母各自的策略：[主, 次]；空座主策略回落 nearest，次为空 = 无第二通道。
static func targeting_pair_of(genome: Array, genes: Dictionary) -> Array:
	var out: Array = ["nearest", ""]
	var names := alleles_at(_at(genome, 8), 8, genes)
	if names.size() >= 1:
		out[0] = str(names[0])
	if names.size() >= 2:
		out[1] = str(names[1])
	return out


## flush_interval：座空 → 1.0；杂合取两字母周期里较小的那个（同时按两周期汇出等价于短周期）。
static func _buffer_flush(genome: Array, genes: Dictionary) -> float:
	var loci: Array = genes.get("loci", [])
	var best := 1.0 # buffer 座缺省时的兜底汇入周期
	var first := true
	for a in alleles_at(_at(genome, 5), 5, genes):
		var v := float(_allele_payload(loci, 5, str(a)).get("flush_interval", 1.0))
		if first:
			best = v
			first = false
		else:
			best = minf(best, v)
	return best


## 基因组 → 简短人读摘要（UI 卡面 desc 用）。
static func summary(genome: Array, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var parts: Array = []
	for i in genome.size():
		if i >= loci.size() or _at(genome, i) == null:
			continue
		var names := alleles_at(_at(genome, i), i, genes)
		if names.is_empty():
			continue
		parts.append("%s:%s" % [str((loci[i] as Dictionary).get("id", i)), "/".join(names)])
	if parts.is_empty():
		return "空基因组"
	return " · ".join(parts)


# ================================================================ 减数分裂

## 融合：每座一对碱基由双亲各出 1 个凑成（双方都有 → 必然杂合 = 双表达）；
## 一方空 → 有的一方整对搬入（纯合，功能不丢）；双方空 → 空座。最后逐座突变。
## rng 由调用方提供（带种子 = 可复现）。纯函数，无副作用。
static func breed(a: Array, b: Array, genes: Dictionary, rng: RandomNumberGenerator) -> Array:
	var loci: Array = genes.get("loci", [])
	var child: Array = []
	for i in loci.size():
		var ea = _at(a, i)
		var eb = _at(b, i)
		if ea == null and eb == null:
			child.append(null)
		elif eb == null:
			child.append(_mutate((ea as Dictionary).duplicate(true), i, genes, rng))
		elif ea == null:
			child.append(_mutate((eb as Dictionary).duplicate(true), i, genes, rng))
		else:
			child.append(_mutate(_mate_pair(ea, eb, loci[i], rng), i, genes, rng))
	return child


## 双亲都有该座：各出 1 个碱基（自身杂合时随机取一个），父在前母在后。
## 参数搬进 params / alt_params，保证"哪个字母带哪套数值"。
static func _mate_pair(ea, eb, locus: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pa := _pick_letter(ea, rng)
	var pb := _pick_letter(eb, rng)
	var out := { "bases": pa + pb }
	var pm := _params_for_letter(ea, locus, pa)
	var pn := _params_for_letter(eb, locus, pb)
	if not pm.is_empty():
		out["params"] = pm
	if not pn.is_empty():
		out["alt_params"] = pn
	return out


## 从 entry 的一对碱基里随机取一个（纯合只有一个可选）。
static func _pick_letter(entry, rng: RandomNumberGenerator) -> String:
	var ls := letters(entry)
	if ls.is_empty():
		return ""
	if ls.size() == 1:
		return str(ls[0])
	return str(ls[rng.randi_range(0, ls.size() - 1)])


## entry 里绑定某字母的那套参数（第一个字母读 params、第二个字母读 alt_params）。
static func _params_for_letter(entry, locus: Dictionary, letter: String) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var ls := letters(entry)
	if ls.is_empty():
		return {}
	var key := "alt_params" if (ls.size() >= 2 and letter == str(ls[1])) else "params"
	var raw = (entry as Dictionary).get(key, null)
	if not (raw is Dictionary):
		return {}
	var declared: Dictionary = locus.get("params", {})
	var out := {}
	for k in raw:
		if declared.has(str(k)):
			out[str(k)] = float(raw[k])
	return out


## 突变：数值座 params/alt_params 各自 ±drift 浮动并钳回 [min,max]；
## 其它座随机选一对里的 1 个字母换成同座另一个已声明 code（保证是有效突变），
## 被换掉字母那套参数随之作废（回落座默认值）。
static func _mutate(entry, idx: int, genes: Dictionary, rng: RandomNumberGenerator):
	if entry == null:
		return null
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
		for key in ["params", "alt_params"]:
			var raw = out.get(key, null)
			if not (raw is Dictionary):
				continue
			var params: Dictionary = raw
			for k in params:
				var spec: Dictionary = (locus.get("params", {}) as Dictionary).get(k, {})
				var v := float(params[k]) * (1.0 + rng.randf_range(-drift, drift))
				params[k] = clampf(v, float(spec.get("min", 0.0)), float(spec.get("max", INF)))
			out[key] = params
		return out
	var codes := base_codes(locus)
	var ls := letters(out)
	if ls.is_empty() or codes.size() <= 1:
		return out
	var slot: int = rng.randi_range(0, ls.size() - 1)
	var cur := str(ls[slot])
	var pool: Array = []
	for c in codes:
		if str(c) != cur:
			pool.append(str(c))
	if pool.is_empty():
		return out
	ls[slot] = str(pool[rng.randi_range(0, pool.size() - 1)])
	out["bases"] = "".join(ls)
	out.erase("params" if slot == 0 else "alt_params")
	return out


# ================================================================ 表型命名与碱基编码

## 表型命名（策划案 15.6/15.9）：按表达出的功能段拼接中文标签，顺序 = 光环→生产→攻击。
## 杂合座两个字母的 label 都拼（同座去重），代码零硬编码；无标签时为"空机"。
const NAME_ORDER := [3, 2, 0] # 座位索引：光环、生产、攻击（示例："采矿轻炮""轻重炮"）

static func phenotype_name(genome: Array, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var parts: Array = []
	var seen := {}
	for idx in NAME_ORDER:
		var g = _at(genome, idx)
		if g == null or idx >= loci.size():
			continue
		for allele in alleles_at(g, idx, genes):
			var label := str(_allele_payload(loci, idx, str(allele)).get("label", ""))
			if label.is_empty() or seen.has(label):
				continue
			seen[label] = true
			parts.append(label)
	if parts.is_empty():
		return "空机"
	return "".join(parts)


## 基因组 → 碱基链（DNA 检视玩家视图用，策划案 15.8）：
## 每座吐该座两个字母（"A" 视为纯合 → "AA"）；空座为 "—"。
static func base_letters(genome: Array, genes: Dictionary) -> Array:
	var loci: Array = genes.get("loci", [])
	var out: Array = []
	for i in loci.size():
		var ls := letters(_at(genome, i))
		if ls.is_empty():
			out.append("—")
		elif ls.size() == 1:
			out.append(str(ls[0]) + str(ls[0]))
		else:
			out.append(str(ls[0]) + str(ls[1]))
	return out


## 碱基互补（A↔T、C↔G）；非碱基字符原样返回。
static func complement(base: String) -> String:
	match base:
		"A": return "T"
		"T": return "A"
		"C": return "G"
		"G": return "C"
		_: return base


# ================================================================ 动态子代注册

## 注册融合子代：动态蓝图（genome 表达）+ 对应卡牌写入 config，返回子代卡 id。
## 放置走既有 place_factory 通道，校验/实例化零改动。
## 价格 = 各座 price 之和（策划案 §18.2）：价格是基因型的函数，不写在卡牌/蓝图上。
## **每座只计一次价**（取第一个字母；杂合双表达不加价）；同一 DNA 必同价。
static func price_of(genome: Array, genes: Dictionary) -> Dictionary:
	var out := {}
	var loci: Array = genes.get("loci", [])
	for i in mini(genome.size(), loci.size()):
		if genome[i] == null:
			continue
		var allele := allele_at(genome[i], i, genes)
		if allele.is_empty():
			continue
		var price = _allele_payload(loci, i, allele).get("price", null)
		if not (price is Dictionary):
			continue
		for rid in price:
			out[rid] = int(out.get(rid, 0)) + int(price[rid])
	return out


static func register_child(config, genome: Array, display_name: String) -> StringName:
	_next_child += 1
	var bid := "fusion_%d" % _next_child
	var genes: Dictionary = config.get("genes")
	config.blueprints[StringName(bid)] = {
		"id": StringName(bid), "name": display_name, "cost": price_of(genome, genes),
		"genome": genome.duplicate(true),
	}
	var cid := "card_" + bid
	config.cards[StringName(cid)] = {
		"id": StringName(cid), "name": display_name, "cost": {},
		"effect": { "type": "place_factory", "blueprint_id": StringName(bid) },
	}
	return StringName(cid)


# ================================================================ 文本生成（UI 卡面用）

## 基因组 → DNA 序列多行文本（每座一行；杂合两套参数并列）。
static func sequence_text(genome: Array, genes: Dictionary) -> String:
	var loci: Array = genes.get("loci", [])
	var lines: Array = []
	for i in loci.size():
		var lid := str((loci[i] as Dictionary).get("id", i))
		var g = _at(genome, i)
		var names := alleles_at(g, i, genes)
		if names.is_empty():
			lines.append("%d. %s: —" % [i + 1, lid])
			continue
		var s := "%d. %s: %s" % [i + 1, lid, "/".join(names)]
		var kv: Array = []
		var pm = (g as Dictionary).get("params", null)
		var pn = (g as Dictionary).get("alt_params", null)
		if pm is Dictionary:
			for k in pm:
				kv.append("%s=%s" % [k, str(pm[k])])
		if pn is Dictionary:
			for k in pn:
				kv.append("alt_%s=%s" % [k, str(pn[k])])
		if not kv.is_empty():
			s += "（%s）" % ", ".join(kv)
		lines.append(s)
	return "\n".join(lines)


## 基因组 → 人话效果描述（悬停 tooltip 用）：按表达出的组件逐行描述，杂合通道带①②编号。
static func effect_text(genome: Array, genes: Dictionary, config) -> String:
	var lines: Array = []
	for spec in express(genome, genes, "", ""):
		match str((spec as Dictionary).get("type", "")):
			"Attack":
				lines.append(_attack_line(spec, 1))
				if spec.has("alt"):
					lines.append(_attack_line(spec["alt"], 2))
			"Production":
				lines.append(_prod_line(spec, config, 1))
				if spec.has("alt"):
					lines.append(_prod_line(spec["alt"], config, 2))
			"Aura":
				lines.append(_aura_line(spec, config, 1))
				if spec.has("alt"):
					lines.append(_aura_line(spec["alt"], config, 2))
			"ResourceBuffer":
				lines.append("缓冲: 每%.1fs 汇出" % float(spec["flush_interval"]))
	if lines.is_empty():
		lines.append("无功能组件（空基因组）")
	return "\n".join(lines)


static func _attack_line(spec: Dictionary, n: int) -> String:
	var pid := str(spec.get("projectile", ""))
	var pnote := ("，弹: " + pid) if not pid.is_empty() else ""
	return "攻击%s: 伤害%.1f 射程%.0f 冷却%.1fs%s" % [
		_numeral(n), float(spec["damage"]), float(spec["range"]), float(spec["cooldown"]), pnote]


static func _prod_line(spec: Dictionary, config, n: int) -> String:
	var r: Dictionary = config.get_recipe(StringName(str(spec.get("recipe_id", ""))))
	var outs: Array = []
	for k in r.get("outputs", {}):
		outs.append("%s×%d" % [_res_name(config, k), int(r["outputs"][k])])
	var ins: Array = []
	for k in r.get("inputs", {}):
		ins.append("%s×%d" % [_res_name(config, k), int(r["inputs"][k])])
	var line := "生产%s: %s / 每%.1fs" % [_numeral(n), ", ".join(outs), float(spec["interval"])]
	if not ins.is_empty():
		line += "（输入 %s）" % ", ".join(ins)
	return line


static func _aura_line(spec: Dictionary, config, n: int) -> String:
	var eid := StringName(str(spec.get("effect_id", "")))
	var ename := str((config.get_effect(eid) as Dictionary).get("name", eid))
	return "光环%s: %s，半径%.0f" % [_numeral(n), ename, float(spec["radius"])]


static func _numeral(n: int) -> String:
	var i := n - 1
	return str(NUMERALS[i]) if i >= 0 and i < NUMERALS.size() else ""


static func _res_name(config, rid) -> String:
	var r: Dictionary = config.get_resource(rid)
	return str(r.get("name", rid))


# ================================================================ 工具

## 亲水座就绪判定：座存在且 kind == "hydro"。不满足时 push_error 出声（而不是静默回落漠水）——
## 座序是 genes.json 的数据契约，漂移必须报错，否则所有建筑的亲水效果会无声消失（T1-2）。
static func _hydro_locus_ready(loci: Array) -> bool:
	if loci.size() <= HYDRO_IDX:
		push_error("genes.json 亲水座缺失：loci 只有 %d 座，需 > %d（hydro 将回落漠水）"
			% [loci.size(), HYDRO_IDX])
		return false
	var kind := str((loci[HYDRO_IDX] as Dictionary).get("kind", ""))
	if kind != "hydro":
		push_error("genes.json 座 %d 的 kind 应为 \"hydro\"，实际 \"%s\"（hydro 将回落漠水）"
			% [HYDRO_IDX, kind])
		return false
	return true


static func _at(genome: Array, idx: int):
	return genome[idx] if idx < genome.size() else null


static func _allele_payload(loci: Array, idx: int, allele: String) -> Dictionary:
	if idx >= loci.size() or allele.is_empty():
		return {}
	return ((loci[idx] as Dictionary).get("alleles", {}) as Dictionary).get(allele, {})


static func _params_of(entry, loci: Array, idx: int, key: String = "params") -> Dictionary:
	if entry == null or idx >= loci.size():
		return {}
	var declared: Dictionary = (loci[idx] as Dictionary).get("params", {})
	var raw = (entry as Dictionary).get(key, null)
	if not (raw is Dictionary):
		return {}
	var out := {}
	for k in declared:
		if raw.has(k):
			out[k] = float(raw[k])
	return out


static func _default_param(loci: Array, idx: int, key: String) -> float:
	if idx >= loci.size():
		return 0.0
	var spec: Dictionary = ((loci[idx] as Dictionary).get("params", {}) as Dictionary).get(key, {})
	return float(spec.get("default", 0.0))
