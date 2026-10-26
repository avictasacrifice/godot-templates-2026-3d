extends Node

var _current_tween: Tween
var _camera: Camera3D

# Вызывай это из любого скрипта: Shake.play(0.5, 0.2)
func play(intensity: float, duration: float, trans_type: Tween.TransitionType = Tween.TRANS_SINE) -> void:
	_camera = get_viewport().get_camera_3d()
	if not _camera:
		return
		
	# Если предыдущая тряска еще идет — убиваем её, чтобы не было конфликтов
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	# Начальное положение (0, потому что камера ровная, когда нет тряски)
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	
	# Создаем твин
	_current_tween = create_tween()
	
	# Мы делаем несколько быстрых рывков туда-сюда, чтобы создать эффект тряски
	var steps = 5
	for i in range(steps):
		# С каждым шагом сила тряски уменьшается (интерполяция к нулю)
		var current_intensity = lerpf(intensity, 0.0, float(i) / steps)
		
		# Случайное смещение
		var offset = Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)
		
		# Двигаем камеру за короткий промежуток времени
		_current_tween.tween_property(_camera, "h_offset", offset.x, duration / steps).set_trans(trans_type)
		_current_tween.parallel().tween_property(_camera, "v_offset", offset.y, duration / steps).set_trans(trans_type)
	
	# В конце плавно возвращаем в идеальный ноль
	_current_tween.tween_property(_camera, "h_offset", 0.0, 0.05)
	_current_tween.parallel().tween_property(_camera, "v_offset", 0.0, 0.05)
