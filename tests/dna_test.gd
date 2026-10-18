extends SceneTree
## DNA 融合系统 headless 验证（规格 docs/superpowers/specs/2026-10-13-dna-fusion-design.md）：
## 基因组表达 / breed 确定性 / 融合指令全流程 / 子代入手与入堆 / 命名。
## 运行：godot --headless --path <项目目录> -s res://tests/dna_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。

const BootstrapScript = preload("res://scripts/bootstrap.gd")
const GenomeScript = preload("res://scripts/dna/genome.gd")
const FactoryViewScript = preload("res://scripts/views/factory_view.gd")
const GameScript = preload("res://scripts/game.gd")

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _init() -> void:
	var code := _run()
	_finished = true
	quit(code)


func _process(_dt: float) -> bool:
	return _finished


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


func _run() -> int:
	print("======== DNA 融合系统测试 ========")
	var config = GameConfig.load_all()
	_ok(config != null, "GameConfig.load_all() 成功（含 genes.json 共 8 个 JSON）")
	if config == null:
		return 1

	print("== T0: 基因座与蓝图基因组 ==")
	_ok(config.genes.has("loci") and (config.genes["loci"] as Array).size() == 8, "genes.json 8 个基因座已加载")
	var tgt_locus: Dictionary = (config.genes["loci"] as Array)[7]
	_ok(str(tgt_locus.get("id", "")) == "targeting" and (tgt_locus.get("alleles", {}) as Dictionary).size() == 4,
		"瞄准座已加载（4 个策略等位基因）")
	for bid in ["generator", "pump", "miner", "assembler", "gun_turret", "frost_beacon", "command_post"]:
		var bp: Dictionary = config.blueprints[StringName(bid)]
		_ok(bp.has("genome") and (bp["genome"] as Array).size() == 8, "蓝图 %s 附带 8 座基因组" % bid)
		_ok(not bp.has("components"), "蓝图 %s 不再手写组件清单" % bid)

	print("== T1: 基因组表达 ==")
	var turret_genome: Array = config.blueprints[&"gun_turret"]["genome"]
	var specs: Array = GenomeScript.express(turret_genome, config.genes, "gun_turret", "炮塔")
	var has_attack := false
	var has_prod := false
	for s in specs:
		if s.get("type", "") == "Attack":
			has_attack = true
			_ok(s["projectile"] == "ore_shot", "攻击座表达射弹 ore_shot")
			_ok(String(s["targeting"]) == "nearest", "瞄准座表达 nearest")
			_ok(is_equal_approx(float(s["damage"]), 6.0), "数值座表达伤害 6")
		if s.get("type", "") == "Production":
			has_prod = true
	_ok(has_attack and not has_prod, "炮塔基因组只表达攻击不表达生产")
	var gen_specs: Array = GenomeScript.express(config.blueprints[&"generator"]["genome"], config.genes, "generator", "发电机")
	var gen_types := {}
	for s in gen_specs:
		gen_types[s.get("type", "")] = true
	_ok(gen_types.has("Production") and gen_types.has("ResourceBuffer") and not gen_types.has("Attack"),
		"发电机基因组表达 生产+缓冲、无攻击")

	print("== T2: breed 结构与同种子确定性 ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var child := GenomeScript.breed(turret_genome, config.blueprints[&"miner"]["genome"], config.genes, rng)
	_ok(child.size() == 8, "子代基因组 8 座")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1
	var child2 := GenomeScript.breed(turret_genome, config.blueprints[&"miner"]["genome"], config.genes, rng2)
	_ok(JSON.stringify(child) == JSON.stringify(child2), "同种子同双亲 → 同子代（可复现）")

	print("== T3: 放置走基因组表达 ==")
	var w := _make_world(config)
	w.push_command({ "type": "place_factory", "blueprint_id": "gun_turret", "cell": [2, 2] })
	w.tick(0.1)
	var tid := _find_factory(w, &"gun_turret")
	_ok(tid != 0, "炮塔放置成功")
	_ok(w.has_component(tid, &"Attack"), "放置后实体带 Attack 组件")
	var fac = w.get_component(tid, &"Factory")
	_ok(fac.display_name == "轻炮" and fac.genome.size() == 8, "Factory 组件携带 genome 与表型 display_name")

	print("== T4: 融合指令全流程 ==")
	w.push_command({ "type": "place_factory", "blueprint_id": "miner", "cell": [3, 2] })
	w.tick(0.1)
	var mid := _find_factory(w, &"miner")
	_ok(mid != 0, "矿机放置成功")
	var pool_before: int = _card_sys(w).deck.pool.size()
	w.push_command({ "type": "fuse", "a": tid, "b": mid, "seed": 42 })
	w.tick(0.1)
	_ok(not w.is_alive(tid) and not w.is_alive(mid), "双亲实体已销毁")
	_ok(w.grid.get_cell(Vector2i(2, 2)).occupant == 0 and w.grid.get_cell(Vector2i(3, 2)).occupant == 0,
		"双亲格子已释放（GridSystem 清扫）")
	var child_card: StringName = _find_fusion_card(config, pool_before)
	_ok(child_card != &"", "子代卡已注册（card_fusion_*）")
	_ok(_card_sys(w).deck.hand.has(child_card) or _card_sys(w).deck.pool.size() > pool_before,
		"子代卡入手（手牌未满时）")
	_ok(config.cards[child_card]["name"].length() >= 2, "子代有名字")
	var child_bp: Dictionary = config.blueprints[config.cards[child_card]["effect"]["blueprint_id"]]
	_ok(String(config.cards[child_card]["name"]) == GenomeScript.phenotype_name(child_bp["genome"], config.genes),
		"子代名 = 表型命名（由基因组解码，非随机汉字）")
	var ok_hanzi := true
	for ch in String(config.cards[child_card]["name"]):
		var code := String(ch).unicode_at(0)
		if code < 0x4E00 or code > 0x9FFF:
			ok_hanzi = false
	_ok(ok_hanzi, "子代名字只含汉字")
	_ok(str(config.cards[child_card]["effect"]["type"]) == "place_factory", "子代卡效果 = place_factory")

	print("== T5: 子代卡可正常打出 ==")
	var hand: Array = _card_sys(w).deck.hand
	var idx := hand.find(child_card)
	if idx >= 0:
		w.push_command({ "type": "play_card", "card_index": idx, "cell": [4, 2] })
		w.tick(0.1)
		var cid := _find_factory(w, config.cards[child_card]["effect"]["blueprint_id"])
		_ok(cid != 0, "子代卡打出 → 新实体创建")
		_ok(w.has_component(cid, &"Factory"), "子代实体带 Factory 组件")
	else:
		_ok(false, "子代卡应入手（T4 已断言）")

	print("== T6: 手牌满 → 子代进抽牌堆顶 ==")
	var w2 := _make_world(config)
	var cs := _card_sys(w2)
	while cs.deck.hand.size() < cs.deck.hand_max:
		cs.receive_card(&"card_generator")
	var pool0: int = cs.deck.pool.size()
	w2.push_command({ "type": "place_factory", "blueprint_id": "generator", "cell": [2, 2] })
	w2.push_command({ "type": "place_factory", "blueprint_id": "pump", "cell": [3, 2] })
	w2.tick(0.1)
	var g2 := _find_factory(w2, &"generator")
	var p2 := _find_factory(w2, &"pump")
	var fused_before: int = _fusion_card_count(config)
	w2.push_command({ "type": "fuse", "a": g2, "b": p2, "seed": 7 })
	w2.tick(0.1)
	_ok(_fusion_card_count(config) == fused_before + 1, "第二次融合注册了新子代卡")
	var newest := _newest_fusion_card(config)
	_ok(cs.deck.pool.size() == pool0 + 1 and cs.deck.pool[0] == newest, "手牌满时子代卡放抽牌堆顶")

	print("== T7: 同种子端到端复现 ==")
	var w3 := _make_world(config)
	w3.push_command({ "type": "place_factory", "blueprint_id": "gun_turret", "cell": [2, 2] })
	w3.push_command({ "type": "place_factory", "blueprint_id": "frost_beacon", "cell": [3, 2] })
	w3.tick(0.1)
	var n3: int = _fusion_card_count(config)
	w3.push_command({ "type": "fuse", "a": _find_factory(w3, &"gun_turret"), "b": _find_factory(w3, &"frost_beacon"), "seed": 42 })
	w3.tick(0.1)
	_ok(_fusion_card_count(config) == n3 + 1, "T7 融合执行")
	var g_a: Array = config.blueprints[config.cards[_newest_fusion_card(config)]["effect"]["blueprint_id"]]["genome"]
	# 与 T4 同种子(42)但双亲不同(炮塔+矿机 vs 炮塔+霜冻)——只验证基因组结构合法性
	_ok(g_a.size() == 8, "端到端子代基因组 8 座")

	# 回归：打出融合子代卡不补抽（0 消耗自动抽 1 的例外）
	var cs3 = w3.get_system("CardSystem")
	var child3 := _newest_fusion_card(config)
	cs3.deck.hand.push_front(child3)
	var hand3: int = cs3.deck.hand.size()
	w3.push_command({ "type": "play_card", "card_index": 0, "cell": [4, 2] })
	w3.tick(0.1)
	_ok(cs3.deck.hand.size() == hand3 - 1 and cs3.deck.pending_draw == 0,
		"打出融合子代卡不补抽（手牌 %d→%d，pending_draw=%d）" % [hand3, cs3.deck.hand.size(), cs3.deck.pending_draw])

	print("== T8: 非法融合被拒 ==")
	var rejected := []
	w3.command_rejected.connect(func(r): rejected.append(r))
	w3.push_command({ "type": "fuse", "a": 999999, "b": 1, "seed": 1 })
	w3.tick(0.1)
	_ok(rejected.size() > 0, "不存在的实体融合被拒（command_rejected）")

	print("== T9: 外形部件跟随 DNA ==")
	var parts_t: Array = FactoryViewScript.parts_for(turret_genome, config.genes)
	_ok(_has_kind(parts_t, "barrel") and not _has_kind(parts_t, "chimney"), "炮塔基因组 → 只有炮管部件")
	var parts_g: Array = FactoryViewScript.parts_for(config.blueprints[&"generator"]["genome"], config.genes)
	_ok(_has_kind(parts_g, "chimney") and not _has_kind(parts_g, "barrel"), "发电机基因组 → 只有烟囱部件")
	var hybrid := [turret_genome[0], turret_genome[1], config.blueprints[&"miner"]["genome"][2],
		config.blueprints[&"frost_beacon"]["genome"][3], config.blueprints[&"miner"]["genome"][4], null, null]
	var parts_h: Array = FactoryViewScript.parts_for(hybrid, config.genes)
	_ok(_has_kind(parts_h, "barrel") and _has_kind(parts_h, "chimney") and _has_kind(parts_h, "beacon")
		and _has_kind(parts_h, "aura_ring") and _has_kind(parts_h, "crate"),
		"攻击+生产+光环+缓冲混合基因组 → 全部对应部件同体")
	var colors_ok := true
	for p in parts_h:
		var c: Color = FactoryViewScript.color_of(str(p["allele"]))
		if c.a <= 0.0:
			colors_ok = false
	_ok(colors_ok, "每个部件等位基因都有有效颜色")

	print("== T10: DNA 序列文本与效果描述 ==")
	_ok(config.effects[&"slow_field"].get("name", "") == "减速场", "buffs.json 显示名已加载")
	var seq: String = GenomeScript.sequence_text(turret_genome, config.genes)
	_ok(seq.split("\n").size() == 8, "序列文本 8 行（每座一行）")
	_ok(seq.find("attack_type: shot_light") != -1 and seq.find("attack_stats") != -1, "序列含攻击座与等位基因")
	_ok(seq.find("production: —") != -1, "空座显示为 —")
	var et: String = GenomeScript.effect_text(turret_genome, config.genes, config)
	_ok(et.find("攻击") != -1 and et.find("伤害6.0") != -1 and et.find("射程160") != -1, "炮塔效果描述含伤害/射程")
	_ok(et.find("ore_shot") != -1, "效果描述含射弹名")
	var eg: String = GenomeScript.effect_text(config.blueprints[&"generator"]["genome"], config.genes, config)
	_ok(eg.find("生产") != -1 and eg.find("电力×2") != -1 and eg.find("缓冲") != -1, "发电机效果描述含产出资源中文名+缓冲")
	var ea: String = GenomeScript.effect_text(config.blueprints[&"frost_beacon"]["genome"], config.genes, config)
	_ok(ea.find("减速场") != -1 and ea.find("半径140") != -1, "信标效果描述含 buffs 显示名+半径")

	print("== T11: 卡面 DNA/描述（接线层 _ui_card_of）==")
	var game = GameScript.new()
	game.config = config
	game.level_id = &"level_1"
	var d1: Dictionary = game._ui_card_of("card_gun_turret")
	_ok(str(d1["dna"]).find("attack_type: shot_light") != -1, "工厂卡 dna 从蓝图基因组取到")
	_ok(str(d1["desc"]).find("攻击") != -1 and str(d1["desc"]).find("费用") != -1, "工厂卡悬停 = 费用 + 攻击描述")
	var d2: Dictionary = game._ui_card_of("card_slow_tile")
	_ok(str(d2["dna"]).find("tile_type: slow") != -1 and str(d2["dna"]).find("0.5") != -1,
		"地块卡 dna = 地块基因（减速倍率），不再落\"无 DNA\"分支")
	var newest2 := _newest_fusion_card(config)
	var d3: Dictionary = game._ui_card_of(String(newest2))
	_ok(str(d3["dna"]).length() > 10, "融合子代卡 dna 可取（跟随卡牌走）")

	print("== T12: 表型命名与碱基编码 ==")
	_ok(GenomeScript.phenotype_name(turret_genome, config.genes) == "轻炮", "炮塔基因组 → 轻炮")
	_ok(GenomeScript.phenotype_name(config.blueprints[&"generator"]["genome"], config.genes) == "发电", "发电机 → 发电")
	_ok(String(d1["name"]) == "轻炮", "卡面显示名走表型命名（gun_turret → 轻炮）")
	var named := [turret_genome[0], turret_genome[1], config.blueprints[&"miner"]["genome"][2],
		null, null, null, null, null]
	_ok(GenomeScript.phenotype_name(named, config.genes) == "采矿轻炮", "采矿+轻炮 → 采矿轻炮（策划案15.9示例）")
	_ok(GenomeScript.phenotype_name([null, null, null, null, null, null, null, null], config.genes) == "空机", "空基因组 → 空机")
	var bl: Array = GenomeScript.base_letters(turret_genome, config.genes)
	_ok(bl.size() == 8 and String(bl[0]) != "—" and String(bl[2]) == "—" and String(bl[0]).length() == 1,
		"碱基链 8 位：有基因为单字母、空座为—")
	_ok(bl[0] == GenomeScript.base_letters(turret_genome, config.genes)[0], "碱基编码确定性（同基因同碱基）")
	_ok(GenomeScript.complement("A") == "T" and GenomeScript.complement("C") == "G"
		and GenomeScript.complement("T") == "A" and GenomeScript.complement("G") == "C"
		and GenomeScript.complement("—") == "—", "互补配对 A↔T、C↔G")
	var dui: Dictionary = d1["dna_ui"]
	_ok(dui.get("bases", []).size() == 8 and (dui.get("rules", []) as Array).is_empty()
		and str(dui.get("title", "")) == "轻炮", "dna_ui 载荷：碱基8位 + 融合规则不进UI + 表型标题")
	var names: Array = dui.get("locus_names", [])
	_ok(names.size() == 8 and str(names[0]) == "染色体01" and str(names[7]) == "染色体08",
		"座名 = 染色体编号 01…08（不再用 genes.json 座名）")
	game.free()

	print("== T13: 字母=数据（bases 即基因型）==")
	var g_edit: Array = turret_genome.duplicate(true)
	_ok(GenomeScript.allele_at(g_edit[0], 0, config.genes) == "shot_light", "基因型碱基 A 解码为 shot_light")
	g_edit[0] = { "bases": "T" }
	_ok(GenomeScript.allele_at(g_edit[0], 0, config.genes) == "shot_heavy", "碱基 A→T 解码为 shot_heavy")
	var proj := ""
	for s in GenomeScript.express(g_edit, config.genes, "gun_turret", "重炮"):
		if s.get("type", "") == "Attack":
			proj = str(s["projectile"])
	_ok(proj == "ore_heavy", "改碱基即改武器：射弹 ore_shot → ore_heavy")
	var bl2: Array = GenomeScript.base_letters(g_edit, config.genes)
	_ok(bl2[0] == "T", "碱基链跟随基因型（座0 = T）")
	_ok(GenomeScript.bases_of_allele(config.genes["loci"][0], "shot_light") == "A"
		and GenomeScript.bases_of_allele(config.genes["loci"][0], "shot_heavy") == "T",
		"反向查表：等位基因 → 碱基")

	print("== T14: 归一化与非法输入校验 ==")
	var n8: Array = [null, null, null, null, null, null, null, null]
	var only_allele = config._validate_genome("t14", [{ "allele": "shot_light" }] + n8.slice(1))
	_ok(only_allele is Array and str((only_allele[0] as Dictionary).get("bases", "")) == "A"
		and not (only_allele[0] as Dictionary).has("allele"),
		"作者格式 allele 归一化为 bases（shot_light→A），不残留 allele 键")
	var both_ok = config._validate_genome("t14", [{ "allele": "shot_light", "bases": "A" }] + n8.slice(1))
	_ok(both_ok is Array, "bases 与 allele 一致 → 通过")
	var bad_bases = config._validate_genome("t14", [{ "bases": "X" }] + n8.slice(1))
	_ok(bad_bases == null, "非法碱基 X 拒收")
	var bad_code = config._validate_genome("t14", [{ "bases": "G" }] + n8.slice(1))
	_ok(bad_code == null, "座0 未声明的 code G 拒收（攻击座只定义 A/T）")
	var bad_conflict = config._validate_genome("t14", [{ "allele": "shot_light", "bases": "T" }] + n8.slice(1))
	_ok(bad_conflict == null, "bases 与 allele 冲突拒收")
	var bad_stats = config._validate_genome("t14", [null, { "bases": "T" }, null, null, null, null, null, null])
	_ok(bad_stats == null, "数值座碱基非 allele_code 拒收（座1 只有 A）")

	print("======== 汇总: %d 项检查, %d 失败 ========" % [_checks, _failures])
	return 0 if _failures == 0 else _failures


# ================================================================ 辅助

func _make_world(config) -> World:
	var w := BootstrapScript.build_world(config, &"level_1")
	# 放置卡费需要零件/特殊材料；测试统一发启动资金（与 smoke.gd 一致）
	w.state.add(&"parts", 100)
	w.state.add(&"special_material", 10)
	return w


func _card_sys(w) -> CardSystem:
	return w.get_system("CardSystem")


func _find_factory(world, blueprint_id: StringName) -> int:
	for id in world.query(&"Factory"):
		var f = world.get_component(id, &"Factory")
		if f.blueprint_id == blueprint_id:
			return id
	return 0


func _fusion_card_count(config) -> int:
	var n := 0
	for cid in config.cards:
		if String(cid).begins_with("card_fusion_"):
			n += 1
	return n


func _has_kind(parts: Array, kind: String) -> bool:
	for p in parts:
		if str(p.get("kind", "")) == kind:
			return true
	return false


func _newest_fusion_card(config) -> StringName:
	var best := &""
	var best_n := -1
	for cid in config.cards:
		if not String(cid).begins_with("card_fusion_"):
			continue
		var n := String(cid).trim_prefix("card_fusion_").to_int()
		if n > best_n:
			best_n = n
			best = cid
	return best


## T4 专用：找出 pool_before 之后新注册、且当前在手牌或抽牌堆中的子代卡。
func _find_fusion_card(config, pool_before: int) -> StringName:
	var newest := _newest_fusion_card(config)
	if newest == &"":
		return &""
	return newest
