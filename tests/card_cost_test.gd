extends SceneTree
## 卡牌消耗标注验证（docs/卡牌表.md 同口径）：卡牌库行内 + 手牌卡面底部的「消耗: 」行。
## 消耗 = 卡费 + 蓝图费合计（cards.json + factories.json），关卡卡池顺序取 level_1.card_pool。
## 运行：godot --headless --path <项目目录> -s res://tests/card_cost_test.gd
## 退出码 0 = 全部通过；1 = 有失败项。不做视觉观感结论。

const EXPECTED := [
	"消耗: 无", "消耗: 无", "消耗: 无",
	"消耗: 零件×12", "消耗: 零件×14", "消耗: 零件×5", "消耗: 零件×1",
]

var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(ui)

	# 1) 卡牌库：每行有消耗且与卡费+蓝图费合计一致
	var lib := ui.get_node("RightRail/CardLibrary/VBox/Body/List")
	_check(lib.get_child_count() == EXPECTED.size(),
		"卡牌库 %d 行（期望 %d）" % [lib.get_child_count(), EXPECTED.size()])
	for i in mini(lib.get_child_count(), EXPECTED.size()):
		var texts: Array[String] = []
		for c in (lib.get_child(i) as Container).get_children():
			if c is Label:
				texts.append((c as Label).text)
		var cost := _pick(texts, "消耗: ")
		_check(cost == EXPECTED[i], "行%d 消耗=%s（期望 %s）" % [i, cost, EXPECTED[i]])

	# 2) 手牌卡面：每张有卡的按钮都含「消耗: 」标签
	var hand := ui.get_node("HandPanel/VBox/HandArea")
	var shown := 0
	for b in hand.get_children():
		if not (b is Button) or (b as Button).disabled:
			continue
		var texts: Array[String] = []
		_collect_labels(b, texts)
		var cost := _pick(texts, "消耗: ")
		_check(not cost.is_empty(), "手牌卡面含消耗行（%s）" % cost)
		shown += 1
	_check(shown > 0, "手牌至少 1 张有卡槽（实际 %d）" % shown)

	if _fails == 0:
		print("COST_TEST: 全部通过")
	quit(0 if _fails == 0 else 1)


func _collect_labels(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_collect_labels(c, out)


func _pick(texts: Array, prefix: String) -> String:
	for t in texts:
		if t.begins_with(prefix):
			return t
	return ""


func _check(ok: bool, label: String) -> void:
	if ok:
		print("ok   | " + label)
	else:
		_fails += 1
		print("FAIL | " + label)
