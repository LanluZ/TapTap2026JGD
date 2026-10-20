extends Node
## 全局 BGM 单例（autoload 名 Bgm）：按场景切曲，两首 OGG 都在文件元数据里带了循环标签。
##   title.ogg       → 菜单 / 选关（menu_camera.gd 进场景时 play_title）
##   battle_loop.ogg → 关卡战场（game.gd 进场景时 play_battle）
##
## 循环点来自文件元数据（导入后在 stream.tags 里可见），48kHz 单位为帧：
##   title.ogg:       LOOPSTART=1675826、LOOPLENGTH=3351095 → 34.913s → 104.728s（末尾约 35s 尾奏不进循环）
##   battle_loop.ogg: LOOPSTART=45000、  LOOPLENGTH=2879921 →  0.938s →  60.936s
## Godot 4 的 Ogg 循环只有 loop + loop_offset（起点），终点靠"beat_count 拍 × 60/bpm"定义，
## 所以 bpm 用 LOOPEND 反推（bpm/beat_count 在本项目里只作时间换算用，不做节拍同步）。
## 循环点在运行时写到流上而不是改 .import：手改 .import 不保证触发重导入，代码里写死常量可被测试断言。

const RATE := 48000.0
const BEATS_FOR_END := 100 # 任意整数，只参与 bpm 反推
const TRACKS := {
	&"title": {"path": "res://sounds/title.ogg", "loop_start": 1675826, "loop_end": 5026921},
	&"battle": {"path": "res://sounds/battle_loop.ogg", "loop_start": 45000, "loop_end": 2924921},
}

var _player: AudioStreamPlayer
var _streams := {} # track id -> AudioStreamOggVorbis（循环点已写好的缓存实例）
var _current: StringName = &""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	add_child(_player)
	play(&"title")


func play_title() -> void:
	play(&"title")


func play_battle() -> void:
	play(&"battle")


## 切曲。同一首正在播时不打断（回菜单不会把 title 从头重放）。
func play(id: StringName) -> void:
	var stream := _stream_of(id)
	if stream == null:
		return
	if id == _current and _player.playing:
		return
	_current = id
	_player.stream = stream
	_player.play()


func _stream_of(id: StringName) -> AudioStreamOggVorbis:
	if _streams.has(id):
		return _streams[id]
	var cfg: Dictionary = TRACKS.get(id, {})
	if cfg.is_empty():
		push_warning("[BGM] 未知曲目: " + String(id))
		return null
	var stream := load(String(cfg["path"])) as AudioStreamOggVorbis
	if stream == null:
		push_warning("[BGM] 无法加载: " + String(cfg["path"]))
		return null
	var end_sec := float(cfg["loop_end"]) / RATE
	stream.loop = true
	stream.loop_offset = float(cfg["loop_start"]) / RATE
	stream.beat_count = BEATS_FOR_END
	stream.bpm = BEATS_FOR_END * 60.0 / end_sec
	_streams[id] = stream
	return stream
