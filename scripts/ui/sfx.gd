extends Node
## 全局音效（autoload 名 Sfx）：基础 UI 音效池 + 全项目按钮悬停/点击自动挂接。
##
## 用法：
##   - 按钮音：_ready 里接 node_added，任何 BaseButton 进树即自动挂 悬停/点击，无需逐处接线。
##   - 语义音：调用方 preload 本脚本走静态入口（不依赖全局名解析，-s/headless 下也安全）：
##       const SfxScript = preload("res://scripts/ui/sfx.gd")
##       SfxScript.play_if_exists("成功")
##     入口按 /root/Sfx 找单例，单例不在（异常场景）时静默跳过。
##
## 音效名 → 文件映射见 SOUNDS；缺失文件只警告一次，不伪造播放。

const SOUNDS := {
	"悬停": "res://sounds/基础音效/悬停.ogg",
	"点击": "res://sounds/基础音效/点击.ogg",
	"展开": "res://sounds/基础音效/展开.ogg",
	"收起": "res://sounds/基础音效/收起.ogg",
	"成功": "res://sounds/基础音效/成功.ogg",
	"操作失败、警告": "res://sounds/基础音效/操作失败、警告.ogg",
	"通知": "res://sounds/基础音效/通知.ogg",
}

## 同时发声上限：轮转复用，超出时最老的播放器被顶掉（UI 音效都很短，够用）
const POOL_SIZE := 6

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _round := 0
var _missing_warned: Dictionary = {}


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)


## 静态入口：单例在场才播（headless -s 下 autoload 不实例化 → 静默跳过）
static func play_if_exists(sound: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.play(sound)


func play(sound: String) -> void:
	var stream := _stream_of(sound)
	if stream == null:
		return
	var p := _players[_round]
	_round = (_round + 1) % _players.size()
	p.stream = stream
	p.play()


func _stream_of(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path: String = SOUNDS.get(sound, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		if not _missing_warned.has(sound):
			_missing_warned[sound] = true
			push_warning("[音效] 未定义或文件缺失: " + sound)
		return null
	var s := load(path) as AudioStream
	_streams[sound] = s
	return s


func _on_node_added(node: Node) -> void:
	var btn := node as BaseButton
	if btn == null or btn.has_meta(&"_sfx_hooked"):
		return
	# 重进树（reparent）会再发 node_added，meta 挡重复接线
	btn.set_meta(&"_sfx_hooked", true)
	btn.mouse_entered.connect(_on_btn_hover.bind(btn))
	btn.button_down.connect(_on_btn_down)


func _on_btn_hover(btn: BaseButton) -> void:
	if not btn.disabled:
		play("悬停")


func _on_btn_down() -> void:
	play("点击")