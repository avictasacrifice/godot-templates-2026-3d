extends Node
## UIKit — минималистичный автолоад для быстрой сборки UI из кода.
##
## Пример (главное меню):
##   UIKit.create_screen()
##   UIKit.vbox()                              # центрированная коробка, пушится в стек
##   UIKit.title("ГЛАВНОЕ МЕНЮ")
##   UIKit.spacer(30)
##   UIKit.button("Играть", _on_play, true, true)   # accent, фокус по умолчанию
##   UIKit.button("Выход", _on_quit)
##   UIKit.pop_parent()                        # вышли из vbox
##   UIKit.dim("v1.0", UIKit.Align.BOTTOM_RIGHT)
##   UIKit.fade_in()
##
## Меню паузы:
##   UIKit.create_screen(true, true)           # освободить мышь + поставить игру на паузу
##   ...                                       # close_screen() вернёт мышь и снимет паузу
##
## Стек родителей: каждая фабрика кладёт себя в текущего родителя.
## vbox() / hbox() / panel() / margin() пушат себя в стек — не забудь pop_parent(),
## либо create_screen() сам почистит стек.
##
## Внутри контейнера (vbox, hbox, panel...) текст ложится как обычный элемент.
## На корне экрана текст растягивается на весь экран и выравнивается по Align.
##
## Автолоад Audio необязателен: если он есть, кнопки играют "ui_click" / "ui_hover".

signal screen_closed(layer: CanvasLayer)

# ---------- Палитра ----------
const C_BG        := Color("#17181b")
const C_PANEL     := Color("#1e2024")
const C_TEXT      := Color("#e0e0e0")
const C_TEXT_DIM  := Color("#8a8a8a")
const C_ACCENT    := Color("#ff2e2e")
const C_ACCENT_H  := Color("#ff5a5a")  # hover
const C_ACCENT_P  := Color("#c82222")  # pressed

# ---------- Метрики ----------
const FONT_TITLE    := 48
const FONT_BODY     := 20
const FONT_BTN      := 20
const BTN_SIZE      := Vector2(250, 50)
const SCREEN_MARGIN := 40
const GAP           := 15
const PANEL_PAD     := 20
const SCREEN_LAYER  := 100

enum Align { CENTER, TOP_LEFT, TOP_CENTER, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_CENTER, BOTTOM_RIGHT, FULL }

# ---------- Состояние ----------
var _stack: Array[Control] = []
var _layer: CanvasLayer = null

var _restore_mouse_mode: int = -1
var _restore_pause: bool = false
var _paused_by_screen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# =====================================================================
# Стек родителей
# =====================================================================
func _parent() -> Control:
	if _stack.is_empty():
		push_error("UIKit: сначала вызови create_screen()")
		return null
	return _stack.back()


## Безопасно добавляет узел в текущего родителя.
func _add(node: Node) -> void:
	var p := _parent()
	if p:
		p.add_child(node)
	else:
		node.queue_free()


func push_parent(node: Control) -> void:
	if node == null:
		push_warning("UIKit: push_parent(null) — игнор")
		return
	_stack.push_back(node)


func pop_parent() -> void:
	if _stack.size() <= 1:
		push_warning("UIKit: нельзя pop корневого экрана")
		return
	_stack.pop_back()


# =====================================================================
# Экран
# =====================================================================

## release_mouse — показать курсор (и вернуть прежний режим при close_screen).
## pause_game    — поставить игру на паузу и приглушить звук (если есть Audio).
func create_screen(release_mouse := false, pause_game := false) -> Control:
	close_screen()

	_layer = CanvasLayer.new()
	_layer.layer = SCREEN_LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS   # UI живёт и на паузе

	var screen := Control.new()
	screen.name = "UIKitScreen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_PASS
	_layer.add_child(screen)

	# call_deferred — чтобы не ловить "Parent node is busy" при вызове из _ready()
	get_tree().root.add_child.call_deferred(_layer)

	_stack.clear()
	_stack.push_back(screen)

	if release_mouse:
		_restore_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_game:
		_restore_pause = get_tree().paused
		_paused_by_screen = true
		get_tree().paused = true
		_audio_muffle(true)
	return screen


func close_screen() -> void:
	if is_instance_valid(_layer):
		var old := _layer
		old.queue_free()
		screen_closed.emit(old)
	_layer = null
	_stack.clear()

	if _restore_mouse_mode != -1:
		Input.mouse_mode = _restore_mouse_mode as Input.MouseMode
		_restore_mouse_mode = -1
	if _paused_by_screen:
		get_tree().paused = _restore_pause
		_paused_by_screen = false
		_audio_muffle(false)


func is_open() -> bool:
	return is_instance_valid(_layer)


# =====================================================================
# Стили
# =====================================================================
func _style(bg: Color, border := Color.TRANSPARENT, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	if border != Color.TRANSPARENT:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb


func _style_button(btn: Button, accent: bool) -> void:
	if accent:
		btn.add_theme_stylebox_override("normal",  _style(C_ACCENT, C_ACCENT_H))
		btn.add_theme_stylebox_override("hover",   _style(C_ACCENT_H, C_ACCENT_H))
		btn.add_theme_stylebox_override("pressed", _style(C_ACCENT_P, C_ACCENT))
		btn.add_theme_stylebox_override("focus",   _style(C_ACCENT_P, C_TEXT))
		btn.add_theme_color_override("font_color",         C_BG)
		btn.add_theme_color_override("font_hover_color",   C_BG)
		btn.add_theme_color_override("font_pressed_color", C_BG)
		btn.add_theme_color_override("font_focus_color",   C_BG)
	else:
		btn.add_theme_stylebox_override("normal",  _style(C_PANEL, C_ACCENT))
		btn.add_theme_stylebox_override("hover",   _style(C_PANEL.lightened(0.08), C_ACCENT_H))
		btn.add_theme_stylebox_override("pressed", _style(C_ACCENT_P, C_ACCENT))
		btn.add_theme_stylebox_override("focus",   _style(C_PANEL.lightened(0.08), C_ACCENT_H))
		btn.add_theme_color_override("font_color",         C_TEXT)
		btn.add_theme_color_override("font_hover_color",   C_ACCENT_H)
		btn.add_theme_color_override("font_pressed_color", C_TEXT)
		btn.add_theme_color_override("font_focus_color",   C_ACCENT_H)
	btn.add_theme_font_size_override("font_size", FONT_BTN)


# =====================================================================
# Фабрики: текст
# =====================================================================
func text(txt: String, size: int = FONT_BODY, color: Color = C_TEXT, align: Align = Align.FULL) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var p := _parent()
	if p == null:
		lbl.queue_free()
		return lbl
	if p is Container:
		# Внутри контейнера — обычный элемент, только горизонтальное выравнивание.
		lbl.horizontal_alignment = _h_align(align)
	else:
		_apply_overlay_align(lbl, align)
	p.add_child(lbl)
	return lbl


func title(txt: String, color: Color = C_ACCENT) -> Label:
	return text(txt, FONT_TITLE, color, Align.CENTER)


## Приглушённый текст. Внимание: порядок аргументов (txt, align, size).
func dim(txt: String, align: Align = Align.FULL, size: int = FONT_BODY) -> Label:
	return text(txt, size, C_TEXT_DIM, align)


func rich_text(bbcode: String, size: int = FONT_BODY, color: Color = C_TEXT) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.text = bbcode
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_color_override("default_color", color)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(rt)
	return rt


func _h_align(align: Align) -> HorizontalAlignment:
	match align:
		Align.CENTER, Align.TOP_CENTER, Align.BOTTOM_CENTER:
			return HORIZONTAL_ALIGNMENT_CENTER
		Align.TOP_RIGHT, Align.BOTTOM_RIGHT:
			return HORIZONTAL_ALIGNMENT_RIGHT
	return HORIZONTAL_ALIGNMENT_LEFT


func _v_align(align: Align) -> VerticalAlignment:
	match align:
		Align.CENTER:
			return VERTICAL_ALIGNMENT_CENTER
		Align.BOTTOM_LEFT, Align.BOTTOM_CENTER, Align.BOTTOM_RIGHT:
			return VERTICAL_ALIGNMENT_BOTTOM
	return VERTICAL_ALIGNMENT_TOP


func _apply_overlay_align(lbl: Label, align: Align) -> void:
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left   =  SCREEN_MARGIN
	lbl.offset_top    =  SCREEN_MARGIN
	lbl.offset_right  = -SCREEN_MARGIN
	lbl.offset_bottom = -SCREEN_MARGIN
	lbl.horizontal_alignment = _h_align(align)
	lbl.vertical_alignment   = _v_align(align)


# =====================================================================
# Фабрики: контейнеры
# =====================================================================
func vbox(centered := true, sep: int = GAP) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if centered:
		var wrap := CenterContainer.new()
		wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(box)
		_add(wrap)
	else:
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left   =  SCREEN_MARGIN
		box.offset_top    =  SCREEN_MARGIN
		box.offset_right  = -SCREEN_MARGIN
		box.offset_bottom = -SCREEN_MARGIN
		_add(box)
	push_parent(box)
	return box


func hbox(sep: int = GAP) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_add(box)
	push_parent(box)
	return box


func margin(px: int = PANEL_PAD) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, px)
	_add(m)
	push_parent(m)
	return m


## Панель с фоном и рамкой. Возвращает внутренний VBox и пушит ТОЛЬКО его —
## один pop_parent() выходит из панели целиком.
func panel(bg: Color = C_PANEL, border: Color = C_ACCENT) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(bg, border))

	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, PANEL_PAD)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", GAP)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	pc.add_child(m)
	m.add_child(v)
	_add(pc)
	push_parent(v)
	return v


func spacer(h: int = GAP) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(s)
	return s


func separator() -> HSeparator:
	var sep := HSeparator.new()
	_add(sep)
	return sep


# =====================================================================
# Фабрики: кнопки и поля
# =====================================================================

## focus — отдать этой кнопке фокус (для управления с клавиатуры / геймпада).
func button(txt: String, callback: Callable = Callable(), accent := false, focus := false) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = BTN_SIZE
	_style_button(btn, accent)
	if callback.is_valid():
		btn.pressed.connect(callback)
	btn.pressed.connect(_on_button_pressed)
	btn.mouse_entered.connect(_on_button_hover)
	_add(btn)
	if focus:
		btn.grab_focus.call_deferred()   # узел ещё может быть вне дерева
	return btn


func input_field(placeholder: String = "") -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(250, 44)
	le.add_theme_stylebox_override("normal", _style(C_BG, C_ACCENT))
	le.add_theme_stylebox_override("focus",  _style(C_BG, C_ACCENT_H))
	le.add_theme_color_override("font_color",             C_TEXT)
	le.add_theme_color_override("font_placeholder_color", C_TEXT_DIM)
	le.add_theme_color_override("caret_color",            C_ACCENT)
	le.add_theme_font_size_override("font_size", FONT_BODY)
	_add(le)
	return le


## Строка "подпись + слайдер". callback получает значение слайдера.
func slider(label: String, value: float, callback: Callable, min_v := 0.0, max_v := 1.0, step := 0.01) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.add_theme_font_size_override("font_size", FONT_BODY)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", _slider_box(C_PANEL.lightened(0.12)))
	s.add_theme_stylebox_override("grabber_area", _slider_box(C_ACCENT))
	s.add_theme_stylebox_override("grabber_area_highlight", _slider_box(C_ACCENT_H))
	if callback.is_valid():
		s.value_changed.connect(callback)
	row.add_child(s)

	_add(row)
	return s


## Готовый слайдер громкости шины (нужен автолоад Audio).
func volume_slider(label: String, bus: StringName) -> HSlider:
	var audio := _audio()
	var start: float = audio.get_volume(bus) if audio else 1.0
	var cb := func(v: float) -> void:
		var a := _audio()
		if a:
			a.set_volume(bus, v)
	return slider(label, start, cb)


func _slider_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# =====================================================================
# Анимация
# =====================================================================
func fade_in(duration: float = 0.25) -> void:
	if _stack.is_empty():
		return
	var screen := _stack[0]
	if not is_instance_valid(screen):
		return
	screen.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(screen, "modulate:a", 1.0, duration)


# =====================================================================
# Интеграция с Audio (необязательная)
# =====================================================================
func _audio() -> Node:
	return get_node_or_null("/root/Audio")


func _on_button_pressed() -> void:
	var a := _audio()
	if a and a.has_method("play") and a.has_method("has_sound") and a.has_sound(&"ui_click"):
		a.play(&"ui_click")


func _on_button_hover() -> void:
	var a := _audio()
	if a and a.has_method("play") and a.has_method("has_sound") and a.has_sound(&"ui_hover"):
		a.play(&"ui_hover")


func _audio_muffle(enabled: bool) -> void:
	var a := _audio()
	if a and a.has_method("muffle"):
		a.muffle(enabled)
