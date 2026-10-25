extends Node
## Audio — универсальный аудио-движок (autoload "Audio").
##
## Что умеет:
##  - шины микшера Music / SFX / UI / Ambience / Voice создаются сами;
##  - play() / play_3d() — одноразовые звуки из пула, с вариациями и рандомом питча;
##  - play_music() / play_ambience() — кроссфейд между треками;
##  - set_volume() / set_muted() + сохранение настроек в user://;
##  - duck() — временно приглушить шину (музыка тише во время взрыва/диалога);
##  - muffle() — "под водой" / пауза: low-pass на всех игровых шинах.
##
## Звуки подхватываются автоматически из папок res://_Game/Audio/<папка>/:
##   sfx/ ui/ voice/  -> одноразовые звуки (шины SFX / UI / Voice)
##   music/           -> музыка (шина Music), зацикливается сама
##   ambience/        -> фоновые лупы (шина Ambience), зацикливаются сами
## Имя звука = имя файла без расширения. Файлы shot_1.ogg, shot_2.ogg, shot_3.ogg
## склеиваются в один звук "shot" и играются в случайном порядке.

signal volume_changed(bus: StringName, linear: float)

const AUDIO_DIR := "res://_Game/Audio"
const SETTINGS_PATH := "user://audio_settings.cfg"
const AUDIO_EXTENSIONS := ["ogg", "wav", "mp3"]

const POOL_SIZE_2D := 24
const POOL_SIZE_3D := 24
const SILENT_DB := -80.0
const MUFFLE_OPEN_HZ := 20500.0
const MUFFLE_CLOSED_HZ := 900.0

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const BUS_AMBIENCE := &"Ambience"
const BUS_VOICE := &"Voice"

const MIX_BUSES: Array[StringName] = [BUS_MUSIC, BUS_SFX, BUS_UI, BUS_AMBIENCE, BUS_VOICE]
const MUFFLED_BUSES: Array[StringName] = [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_VOICE]
const SOUND_FOLDERS := {"sfx": BUS_SFX, "ui": BUS_UI, "voice": BUS_VOICE}


# ---------------------------------------------------------------------------
# Кроссфейдер: два плеера, один плавно гаснет, второй плавно нарастает.
# Используется и для музыки, и для эмбиента.
# ---------------------------------------------------------------------------
class Crossfader extends Node:
	const SILENT := -80.0

	var _a := AudioStreamPlayer.new()
	var _b := AudioStreamPlayer.new()
	var _cur: AudioStreamPlayer
	var _tween: Tween
	var current_stream: AudioStream:
		get: return _cur.stream if _cur.playing else null

	func _init(bus: StringName) -> void:
		_a.bus = bus
		_b.bus = bus
		add_child(_a)
		add_child(_b)
		_cur = _a

	func play(stream: AudioStream, fade: float, volume_db: float) -> void:
		if stream == null:
			return
		if _cur.playing and _cur.stream == stream:
			return
		if _tween:
			_tween.kill()
		var old := _cur
		_cur = _b if old == _a else _a
		_cur.stop()
		_cur.stream = stream
		_cur.volume_db = SILENT if fade > 0.0 else volume_db
		_cur.play()
		if fade <= 0.0:
			old.stop()
			return
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_cur, "volume_db", volume_db, fade)
		if old.playing:
			_tween.tween_property(old, "volume_db", SILENT, fade)
		_tween.chain().tween_callback(old.stop)

	func stop(fade: float) -> void:
		if _tween:
			_tween.kill()
		if fade <= 0.0 or not _cur.playing:
			_a.stop()
			_b.stop()
			return
		_tween = create_tween().set_parallel(true)
		for p in [_a, _b]:
			if p.playing:
				_tween.tween_property(p, "volume_db", SILENT, fade)
		_tween.chain().tween_callback(func(): _a.stop(); _b.stop())

	func is_playing() -> bool:
		return _cur.playing


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------
var _sounds: Dictionary = {}          # StringName -> описание звука (Dictionary)
var _music_tracks: Dictionary = {}    # StringName -> AudioStream
var _ambience_tracks: Dictionary = {} # StringName -> AudioStream

var _pool_2d: Array = []
var _pool_3d: Array = []
var _active: Dictionary = {}          # StringName -> сколько голосов сейчас играет

var _music: Crossfader
var _ambience: Crossfader

var _user_vol: Dictionary = {}        # bus -> линейная громкость 0..1
var _duck_db: Dictionary = {}         # bus -> текущий сдвиг дакинга в dB
var _duck_tweens: Dictionary = {}

var _muffle_fx: Dictionary = {}       # bus -> AudioEffectLowPassFilter
var _muffle_idx: Dictionary = {}      # bus -> индекс эффекта на шине
var _muffle_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # звук и твины живут во время паузы
	_setup_buses()
	_build_pools()

	_music = Crossfader.new(BUS_MUSIC)
	_music.name = "MusicChannel"
	add_child(_music)
	_ambience = Crossfader.new(BUS_AMBIENCE)
	_ambience.name = "AmbienceChannel"
	add_child(_ambience)

	_scan_library()
	_register_placeholders()
	load_settings()


# ---------------------------------------------------------------------------
# Одноразовые звуки
# ---------------------------------------------------------------------------

## Зарегистрировать звук вручную (если не хочешь класть файлы в папки).
## options: volume_db, pitch_min, pitch_max, max_voices, max_distance, unit_size
func register(sound: StringName, streams: Array, bus: StringName = BUS_SFX, options: Dictionary = {}) -> void:
	var def := {
		"streams": streams,
		"bus": bus,
		"volume_db": 0.0,
		"pitch_min": 0.95,
		"pitch_max": 1.05,
		"max_voices": 8,
		"max_distance": 60.0,
		"unit_size": 10.0,
		"last": -1,
	}
	def.merge(options, true)
	_sounds[sound] = def


## Поменять параметры уже существующего звука: Audio.configure(&"hit", {"volume_db": -4})
func configure(sound: StringName, options: Dictionary) -> void:
	if _sounds.has(sound):
		_sounds[sound].merge(options, true)


func has_sound(sound: StringName) -> bool:
	return _sounds.has(sound)


## Обычный (не позиционный) звук: выстрел игрока, UI, голос.
func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var def := _prepare(sound)
	if def.is_empty():
		return null
	var p := _free_voice(_pool_2d) as AudioStreamPlayer
	if p == null:
		return null
	p.stream = _pick_stream(def)
	p.bus = def.bus
	p.volume_db = def.volume_db + volume_db
	p.pitch_scale = randf_range(def.pitch_min, def.pitch_max) * pitch
	_claim(p, sound)
	p.play()
	return p


## Звук в точке мира. Слушатель — текущая Camera3D (у тебя это камера игрока).
func play_3d(sound: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var def := _prepare(sound)
	if def.is_empty():
		return null
	var p := _free_voice(_pool_3d) as AudioStreamPlayer3D
	if p == null:
		return null
	p.stream = _pick_stream(def)
	p.bus = def.bus
	p.volume_db = def.volume_db + volume_db
	p.pitch_scale = randf_range(def.pitch_min, def.pitch_max) * pitch
	p.max_distance = def.max_distance
	p.unit_size = def.unit_size
	p.global_position = position
	_claim(p, sound)
	p.play()
	return p


func stop_all_sfx() -> void:
	for p in _pool_2d + _pool_3d:
		p.stop()
	_active.clear()


# ---------------------------------------------------------------------------
# Музыка и эмбиент
# ---------------------------------------------------------------------------

## track — имя из папки music/ или готовый AudioStream.
func play_music(track: Variant, fade: float = 1.5, volume_db: float = 0.0) -> void:
	_music.play(_resolve(track, _music_tracks), fade, volume_db)


func stop_music(fade: float = 1.5) -> void:
	_music.stop(fade)


func is_music_playing() -> bool:
	return _music.is_playing()


## track — имя из папки ambience/ или готовый AudioStream.
func play_ambience(track: Variant, fade: float = 2.0, volume_db: float = 0.0) -> void:
	_ambience.play(_resolve(track, _ambience_tracks), fade, volume_db)


func stop_ambience(fade: float = 2.0) -> void:
	_ambience.stop(fade)


# ---------------------------------------------------------------------------
# Микшер
# ---------------------------------------------------------------------------

## Громкость шины, 0.0 .. 1.0 (для слайдеров в меню настроек).
func set_volume(bus: StringName, linear: float) -> void:
	_user_vol[bus] = clampf(linear, 0.0, 1.0)
	_apply_bus(bus)
	volume_changed.emit(bus, _user_vol[bus])


func get_volume(bus: StringName) -> float:
	return _user_vol.get(bus, 1.0)


func set_muted(bus: StringName, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx != -1:
		AudioServer.set_bus_mute(idx, muted)


func is_muted(bus: StringName) -> bool:
	var idx := AudioServer.get_bus_index(bus)
	return idx != -1 and AudioServer.is_bus_mute(idx)


## Текущий пик шины в dB (для индикаторов уровня).
func get_peak_db(bus: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return SILENT_DB
	return maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))


## Временно приглушить шину и плавно вернуть. Пример: Audio.duck(&"Music", -10.0)
func duck(bus: StringName, amount_db: float = -8.0, attack: float = 0.1, hold: float = 0.5, release: float = 0.8) -> void:
	if _duck_tweens.has(bus) and _duck_tweens[bus]:
		_duck_tweens[bus].kill()
	var start: float = _duck_db.get(bus, 0.0)
	var t := create_tween()
	t.tween_method(_set_duck.bind(bus), start, amount_db, attack)
	t.tween_interval(hold)
	t.tween_method(_set_duck.bind(bus), amount_db, 0.0, release)
	_duck_tweens[bus] = t


## "Глухой" звук: low-pass на музыке, SFX, эмбиенте и голосе. UI не трогаем.
func muffle(enabled: bool, time: float = 0.4) -> void:
	if _muffle_tween:
		_muffle_tween.kill()
	var target := MUFFLE_CLOSED_HZ if enabled else MUFFLE_OPEN_HZ
	_muffle_tween = create_tween().set_parallel(true)
	for bus in _muffle_fx:
		if enabled:
			AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(bus), _muffle_idx[bus], true)
		_muffle_tween.tween_property(_muffle_fx[bus], "cutoff_hz", target, time)
	if not enabled:
		_muffle_tween.chain().tween_callback(_disable_muffle)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus in [BUS_MASTER] + MIX_BUSES:
		cfg.set_value("volume", bus, get_volume(bus))
		cfg.set_value("mute", bus, is_muted(bus))
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SETTINGS_PATH) == OK
	for bus in [BUS_MASTER] + MIX_BUSES:
		set_volume(bus, cfg.get_value("volume", bus, 1.0) if loaded else 1.0)
		set_muted(bus, cfg.get_value("mute", bus, false) if loaded else false)


# ---------------------------------------------------------------------------
# Внутренности
# ---------------------------------------------------------------------------
func _setup_buses() -> void:
	for bus in MIX_BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var new_idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(new_idx, bus)
			AudioServer.set_bus_send(new_idx, BUS_MASTER)

	# Лимитер на мастере: много одновременных звуков не уйдут в клиппинг.
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_MASTER), limiter)

	# Low-pass для muffle() — выключен, пока не вызван.
	for bus in MUFFLED_BUSES:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = MUFFLE_OPEN_HZ
		var bus_idx := AudioServer.get_bus_index(bus)
		AudioServer.add_bus_effect(bus_idx, lp)
		var fx_idx := AudioServer.get_bus_effect_count(bus_idx) - 1
		AudioServer.set_bus_effect_enabled(bus_idx, fx_idx, false)
		_muffle_fx[bus] = lp
		_muffle_idx[bus] = fx_idx


func _build_pools() -> void:
	for i in POOL_SIZE_2D:
		var p := AudioStreamPlayer.new()
		p.finished.connect(_on_voice_finished.bind(p))
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_SIZE_3D:
		var p := AudioStreamPlayer3D.new()
		p.finished.connect(_on_voice_finished.bind(p))
		add_child(p)
		_pool_3d.append(p)


func _prepare(sound: StringName) -> Dictionary:
	if not _sounds.has(sound):
		push_warning("Audio: звук '%s' не найден" % sound)
		return {}
	var def: Dictionary = _sounds[sound]
	if _active.get(sound, 0) >= def.max_voices:
		return {}
	return def


func _free_voice(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return null


func _claim(p: Node, sound: StringName) -> void:
	p.set_meta(&"sound", sound)
	_active[sound] = _active.get(sound, 0) + 1


func _on_voice_finished(p: Node) -> void:
	var sound: StringName = p.get_meta(&"sound", &"")
	_active[sound] = maxi(0, _active.get(sound, 0) - 1)


func _pick_stream(def: Dictionary) -> AudioStream:
	var streams: Array = def.streams
	var i := 0
	if streams.size() > 1:
		i = randi() % streams.size()
		if i == def.last:
			i = (i + 1) % streams.size()
	def.last = i
	return streams[i]


func _resolve(track: Variant, table: Dictionary) -> AudioStream:
	if track is AudioStream:
		return track
	var key := StringName(track)
	if not table.has(key):
		push_warning("Audio: трек '%s' не найден" % key)
		return null
	return table[key]


func _apply_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	var v: float = _user_vol.get(bus, 1.0)
	var db := linear_to_db(v) if v > 0.0001 else SILENT_DB
	AudioServer.set_bus_volume_db(idx, db + _duck_db.get(bus, 0.0))


func _set_duck(value: float, bus: StringName) -> void:
	_duck_db[bus] = value
	_apply_bus(bus)


func _disable_muffle() -> void:
	for bus in _muffle_fx:
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(bus), _muffle_idx[bus], false)


# --- Автоподхват файлов из папок -------------------------------------------

func _scan_library() -> void:
	for folder in SOUND_FOLDERS:
		var groups := _scan_folder("%s/%s" % [AUDIO_DIR, folder], true)
		for sound in groups:
			register(sound, groups[sound], SOUND_FOLDERS[folder])
	var music := _scan_folder(AUDIO_DIR + "/music", false)
	for sound in music:
		_music_tracks[sound] = music[sound][0]
	var ambience := _scan_folder(AUDIO_DIR + "/ambience", false)
	for sound in ambience:
		_ambience_tracks[sound] = ambience[sound][0]
	for track in _music_tracks.values() + _ambience_tracks.values():
		_enable_loop(track)


## Возвращает { имя: [потоки] }. group_variants — склеивать shot_1/shot_2 в "shot".
func _scan_folder(path: String, group_variants: bool) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	var seen := {}
	var rx := RegEx.create_from_string("[_-]?\\d+$")
	for file in dir.get_files():
		# В экспортированной игре файлы видны как *.import / *.remap
		var fname := file.trim_suffix(".import").trim_suffix(".remap")
		if fname.get_extension().to_lower() not in AUDIO_EXTENSIONS or seen.has(fname):
			continue
		seen[fname] = true
		var stream := load(path.path_join(fname)) as AudioStream
		if stream == null:
			continue
		var base := fname.get_basename()
		if group_variants:
			var stripped := rx.sub(base, "")
			if not stripped.is_empty():
				base = stripped
		var key := StringName(base)
		if not out.has(key):
			out[key] = []
		out[key].append(stream)
	return out


func _enable_loop(stream: AudioStream) -> void:
	# WAV-луп настраивается в Import-панели; ogg/mp3 включаем здесь.
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true


# --- Заглушки: синтез простых звуков, пока нет своих файлов -----------------

func _register_placeholders() -> void:
	if not has_sound(&"shoot"):
		register(&"shoot", [_synth(900.0, 150.0, 0.12, 0.15, true)], BUS_SFX, {"volume_db": -10.0})
	if not has_sound(&"hit"):
		register(&"hit", [_synth(320.0, 120.0, 0.10, 0.6, false)], BUS_SFX, {"volume_db": -4.0})
	if not has_sound(&"die"):
		register(&"die", [_synth(240.0, 40.0, 0.45, 0.4, true)], BUS_SFX, {"volume_db": -6.0})
	if not has_sound(&"jump"):
		register(&"jump", [_synth(250.0, 620.0, 0.12, 0.0, false)], BUS_SFX, {"volume_db": -8.0})


func _synth(f_start: float, f_end: float, duration: float, noise: float, square: bool) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += TAU * lerpf(f_start, f_end, t) / rate
		var s: float = signf(sin(phase)) if square else sin(phase)
		s = lerpf(s, randf() * 2.0 - 1.0, noise)
		s *= pow(1.0 - t, 2.0) * 0.4
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
