extends Control
## Экран поражения на базе автолоада UIKit.
##
## Вешается на корневой Control сцены game_over.tscn (или открывается
## как оверлей поверх игры — тогда добавь его в CanvasLayer и вызови show()).
##
## Использование:
##   * если это отдельная сцена — просто переключись на неё при смерти игрока;
##   * если оверлей — вызови build() из места, где зафиксирована смерть.
##
## Игра ставится на паузу и курсор показывается автоматически.
## Escape / «В главное меню» / «Заново» корректно снимут паузу.

signal retry_requested
signal menu_requested
signal quit_requested

@export_file("*.tscn") var game_scene: String = ""    # куда вернуться по «Заново»
@export_file("*.tscn") var menu_scene: String = ""    # куда вернуться в главное меню

## Причина поражения (опционально) — выводится под заголовком.
var reason: String = ""
## Статистика (пары «подпись → значение»), отображается строками.
var stats: Dictionary = {}

var _shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _exit_tree() -> void:
	# Страховка: UIKit-слой живёт в /root, а не в сцене.
	if UIKit.is_open():
		UIKit.close_screen()


# =====================================================================
# Публичный API
# =====================================================================
## Показать экран. Можно вызвать повторно — перерисует содержимое.
func build(p_reason := "", p_stats := {}) -> void:
	if p_reason != "":
		reason = p_reason
	if not p_stats.is_empty():
		stats = p_stats

	_shown = true
	# release_mouse = true, pause_game = true → курсор + пауза
	UIKit.create_screen(true, true)

	UIKit.vbox()
	UIKit.title("ПОРАЖЕНИЕ", UIKit.C_ACCENT)
	if reason != "":
		UIKit.dim(reason, UIKit.Align.CENTER)
	UIKit.spacer(20)

	if not stats.is_empty():
		UIKit.panel()
		_build_stats()
		UIKit.pop_parent()          # выйти из панели целиком
		UIKit.spacer(10)

	UIKit.spacer(20)
	UIKit.button("Заново",         _on_retry, true, true)   # accent + фокус
	UIKit.button("В главное меню", _on_menu)
	UIKit.button("Выход",          _on_quit)
	UIKit.pop_parent()

	UIKit.dim("Esc — заново", UIKit.Align.BOTTOM_LEFT)
	UIKit.fade_in()


func hide_screen() -> void:
	_shown = false
	if UIKit.is_open():
		UIKit.close_screen()


# =====================================================================
# Внутреннее
# =====================================================================
func _build_stats() -> void:
	for key in stats.keys():
		UIKit.text("%s: %s" % [str(key), str(stats[key])], UIKit.FONT_BODY, UIKit.C_TEXT)


# =====================================================================
# Действия
# =====================================================================
func _on_retry() -> void:
	_shown = false
	UIKit.close_screen()
	retry_requested.emit()
	if game_scene != "" and ResourceLoader.exists(game_scene):
		# deferred — чтобы сигнальные обработчики успели отработать
		get_tree().change_scene_to_file.call_deferred(game_scene)


func _on_menu() -> void:
	_shown = false
	UIKit.close_screen()
	menu_requested.emit()
	if menu_scene != "" and ResourceLoader.exists(menu_scene):
		get_tree().change_scene_to_file.call_deferred(menu_scene)


func _on_quit() -> void:
	_shown = false
	UIKit.close_screen()
	quit_requested.emit()
	get_tree().quit.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not _shown:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_retry()
