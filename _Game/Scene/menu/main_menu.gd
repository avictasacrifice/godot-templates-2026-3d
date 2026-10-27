extends Control
## Главное меню на базе автолоада UIKit.
##
## Использование:
##   1. Повесить скрипт на корневой Control сцены main_menu.tscn
##   2. Либо указать game_scene в инспекторе → «Играть» переключит сцену,
##      либо подключиться к сигналу play_requested снаружи.
##
## Escape в настройках возвращает в главное меню.

signal play_requested
signal quit_requested

@export_file("*.tscn") var game_scene: String = ""

var _in_settings := false
var _fs_button: Button


func _ready() -> void:
	# Сам Control ничего не рисует — не мешаем кликам доходить до UI UIKit.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_main_menu()


func _exit_tree() -> void:
	# Страховка: UIKit-слой живёт в /root, а не в сцене,
	# поэтому при смене сцены обязательно закрываем экран.
	if UIKit.is_open():
		UIKit.close_screen()


# =====================================================================
# Главное меню
# =====================================================================
func _build_main_menu() -> void:
	_in_settings = false
	UIKit.create_screen(true, false)   # показать курсор, игру не паузить

	UIKit.vbox()
	UIKit.title("ГЛАВНОЕ МЕНЮ")
	UIKit.spacer(30)
	UIKit.button("Играть",    _on_play,       true, true)   # accent + фокус
	UIKit.button("Настройки", _open_settings)
	UIKit.button("Выход",     _on_quit)
	UIKit.pop_parent()                                      # выйти из vbox

	UIKit.dim("v1.0", UIKit.Align.BOTTOM_RIGHT)
	UIKit.fade_in()
	Audio.play_music(&"menu", 1.0)

# =====================================================================
# Настройки
# =====================================================================
func _open_settings() -> void:
	_in_settings = true
	UIKit.create_screen(true, false)

	UIKit.vbox()
	UIKit.title("НАСТРОЙКИ")
	UIKit.spacer(20)

	# Слайдеры громкости — работают, если в проекте есть автолоад Audio
	# с методами get_volume(bus)/set_volume(bus, v). Иначе просто слайдеры.
	UIKit.volume_slider("Музыка", &"Music")
	UIKit.volume_slider("Звуки",  &"SFX")

	UIKit.spacer(10)
	_fs_button = UIKit.button(_fullscreen_label(), _toggle_fullscreen)

	UIKit.spacer(20)
	UIKit.button("Назад", func(): Audio.save_settings(); _build_main_menu(), false, true)
	UIKit.pop_parent()

	UIKit.fade_in()


func _fullscreen_label() -> String:
	var on := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return "Полный экран: %s" % ("Вкл" if on else "Выкл")


func _toggle_fullscreen() -> void:
	var on := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	if is_instance_valid(_fs_button):
		_fs_button.text = _fullscreen_label()


# =====================================================================
# Действия
# =====================================================================
func _on_play() -> void:
	UIKit.close_screen()
	play_requested.emit()
	if game_scene != "" and ResourceLoader.exists(game_scene):
		# deferred — чтобы сигнальные обработчики успели отработать раньше смены сцены
		get_tree().change_scene_to_file.call_deferred(game_scene)


func _on_quit() -> void:
	UIKit.close_screen()
	quit_requested.emit()
	get_tree().quit.call_deferred()


# =====================================================================
# Escape в настройках = «Назад»
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _in_settings and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_build_main_menu()
