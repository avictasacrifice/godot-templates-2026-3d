extends CharacterBody3D

# ============================================================
#  ПАРАМЕТРЫ
# ============================================================

# --- Основа ---
var health: int = 10
const SPEED := 10.0
const MAX_SPEED := 50.0
const GRAVITY := 20.0
const JUMP_VELOCITY := 7.5

# --- Земля ---
const GROUND_ACCEL := 18.0
const FRICTION := 12.0
const STOP_SPEED := 1.8

# --- Воздух (подстроено под уворачивание) ---
const AIR_ACCEL := 12.0              # ↑ можно резко менять направление в прыжке
const AIR_TURN_RATE := 5.5           # ↑ лучше руление на скорости

# --- Бхоп ---
const BHOP_SOFT_CAP := 16.0          # выше этой скорости каждый прыжок слегка "съедает" излишек
const BHOP_EXCESS_KEEP := 0.88       # какую долю излишка сохраняем за прыжок
const JUMP_CUT := 0.55               # отпустил пробел раньше -> прыжок ниже (быстрые мелкие уклонения)

# --- Jump feel ---
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.15

@export var auto_bhop := true

# --- Мышь ---
const MOUSE_SENSITIVITY := 0.0026
const PITCH_LIMIT := deg_to_rad(88.0)

# --- Compress / Launch ---
const COMPRESS_DECEL := 2.0
const COMPRESS_STEER := 22.0
const COMPRESS_AIR_STEER := 14.0
const COMPRESS_AIR_DECEL_MULT := 0.35
const COMPRESS_WINDOW_MIN := 0.12
const COMPRESS_WINDOW_MAX := 0.40
const COMPRESS_OVERHOLD := 0.75
const LAUNCH_IMPULSE := 28.0
const LAUNCH_UP_POP := 5.5
const LAUNCH_MIN_CHARGE := 0.25
const LAUNCH_COOLDOWN := 0.25
const TUCK_DURATION := 0.22

# --- Dash window ---
const DASH_WINDOW := 0.40
const DASH_AIR_ACCEL_MULT := 1.8
const DASH_FRICTION_MULT := 0.15
const DASH_FOV_KICK := 18.0
const DASH_TURN_RATE := 7.0

# --- Отбрасывание от оружия (сильно уменьшено) ---
const WEAPON_KNOCKBACK := 1.0        # было 3.5
const WEAPON_KNOCKBACK_UP_MULT := 0.5 # было 1.6
const WEAPON_KNOCKBACK_MAX := 2.5    # потолок прироста скорости за выстрел

# --- Прицеливание (рейкаст + помощь прицела) ---
const AIM_RANGE := 200.0
const AIM_ASSIST_RADIUS := 0.6       # "примерно попал" — радиус сферы вокруг линии прицела

## Слои, по которым стреляем лучом (по умолчанию всё).
@export_flags_3d_physics var aim_mask: int = 0xFFFFFFFF
## Слой(и) врагов для aim-assist. Поставь сюда физический слой врагов.
## Если 0 — помощь прицела отключена, работает только точный луч.
@export_flags_3d_physics var assist_mask: int = 2

@export var BulletScene : PackedScene

@export var gameover: Control 
@onready var camera: Camera3D = $Camera3D
@onready var muzzle: Marker3D = $Camera3D/Muzzle


# ============================================================
#  СОСТОЯНИЕ
# ============================================================
var _pitch := 0.0

var _is_compressing := false
var _compress_time := 0.0
var _tuck_timer := 0.0
var _jump_buffer_timer := 0.0
var _coyote_timer := 0.0
var _dash_timer := 0.0
var _launch_cooldown := 0.0
var _jump_cut_ready := false

var _col: CollisionShape3D
var _col_orig_height := 0.0
var _col_orig_center_y := 0.0
var _col_ready := false
var _base_fov := 0.0


# ============================================================
#  LIFECYCLE
# ============================================================
func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_base_fov = camera.fov
	_col = find_child("CollisionShape3D", true, false) as CollisionShape3D
	if _col and _col.shape is CapsuleShape3D:
		var cap := _col.shape as CapsuleShape3D
		_col_orig_height = cap.height
		_col_orig_center_y = _col.position.y
		_col_ready = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		camera.rotation.x = _pitch

	if event.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()


# ============================================================
#  ГЛАВНЫЙ ЦИКЛ
# ============================================================
func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# --- Coyote ---
	if on_floor:
		_coyote_timer = COYOTE_TIME
	elif _coyote_timer > 0.0:
		_coyote_timer -= delta

	# --- Таймеры ---
	if _dash_timer > 0.0:
		_dash_timer -= delta
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta
	if _launch_cooldown > 0.0:
		_launch_cooldown -= delta

	# --- Jump buffer + auto-bhop ---
	if Input.is_action_just_pressed("space"):
		_jump_buffer_timer = JUMP_BUFFER
	if auto_bhop and Input.is_action_pressed("space") and on_floor:
		_jump_buffer_timer = JUMP_BUFFER

	# --- Гравитация ---
	if not on_floor:
		velocity.y -= GRAVITY * delta

	# --- Прыжок ---
	var jumped := false
	if _jump_buffer_timer > 0.0 and (on_floor or _coyote_timer > 0.0):
		if _is_compressing:
			_end_compress(false)
		velocity.y = JUMP_VELOCITY
		_apply_bhop_soft_cap()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_cut_ready = true
		jumped = true

	# --- Короткий прыжок при раннем отпускании пробела ---
	if _jump_cut_ready:
		if velocity.y <= 0.0:
			_jump_cut_ready = false
		elif not Input.is_action_pressed("space"):
			velocity.y *= JUMP_CUT
			_jump_cut_ready = false

	# --- Tuck / Launch ---
	var shift_held := Input.is_action_pressed("compress")
	var shift_just := Input.is_action_just_pressed("compress")
	var tuck_just := Input.is_action_just_pressed("tuck")

	if shift_just and not _is_compressing and _launch_cooldown <= 0.0:
		_start_compress()

	if _is_compressing and not shift_held:
		_end_compress(true)

	if tuck_just and on_floor and not _is_compressing and not jumped:
		_tuck_timer = TUCK_DURATION
		_set_crouch_shape(true)
	if _tuck_timer > 0.0:
		_tuck_timer -= delta
		if _tuck_timer <= 0.0 and not _is_compressing:
			_set_crouch_shape(false)

	# --- Ввод ---
	var input_dir := Input.get_vector("a", "d", "w", "s")
	var wish_dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized() if wish_dir.length_squared() > 0.01 else Vector3.ZERO

	# --- Движение ---
	if not on_floor:
		if _is_compressing:
			_process_compress(delta, wish_dir, true)
		else:
			_process_air(delta, wish_dir)
	else:
		if jumped:
			pass
		elif _is_compressing:
			_process_compress(delta, wish_dir, false)
		else:
			_process_ground(delta, wish_dir)

	_clamp_horizontal()
	move_and_slide()

	# --- FOV kick ---
	var target_fov := _base_fov + (DASH_FOV_KICK if _dash_timer > 0.0 else 0.0)
	camera.fov = move_toward(camera.fov, target_fov, 400.0 * delta)

	if _is_compressing:
		_compress_time += delta


# ============================================================
#  ДВИЖЕНИЕ
# ============================================================
func _accelerate(vel: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var current_speed := vel.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return vel
	var accel_speed := minf(accel * wish_speed * delta, add_speed)
	return vel + wish_dir * accel_speed


func _rotate_horizontal_toward(vel: Vector3, target_dir: Vector3, max_radians: float) -> Vector3:
	var hv := Vector3(vel.x, 0.0, vel.z)
	var hs := hv.length()
	if hs < 0.5 or target_dir.length_squared() < 0.01:
		return vel
	var cur_dir := hv / hs
	var ang := cur_dir.signed_angle_to(target_dir, Vector3.UP)
	var step := clampf(ang, -max_radians, max_radians)
	var new_dir := cur_dir.rotated(Vector3.UP, step)
	vel.x = new_dir.x * hs
	vel.z = new_dir.z * hs
	return vel


## Мягкий потолок бхопа: излишек скорости над BHOP_SOFT_CAP слегка гасится
## при каждом прыжке. Во время дэша от лонча не трогаем.
func _apply_bhop_soft_cap() -> void:
	if _dash_timer > 0.0:
		return
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs <= BHOP_SOFT_CAP:
		return
	var new_hs := BHOP_SOFT_CAP + (hs - BHOP_SOFT_CAP) * BHOP_EXCESS_KEEP
	var r := new_hs / hs
	velocity.x *= r
	velocity.z *= r


func _process_ground(delta: float, wish_dir: Vector3) -> void:
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := h_vel.length()
	if speed > 0.01:
		var f_mult := DASH_FRICTION_MULT if _dash_timer > 0.0 else 1.0
		var control := maxf(speed, STOP_SPEED)
		var drop := control * FRICTION * f_mult * delta
		var new_speed := maxf(speed - drop, 0.0)
		if new_speed < 0.01:
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			var ratio := new_speed / speed
			velocity.x *= ratio
			velocity.z *= ratio

	if wish_dir != Vector3.ZERO:
		velocity = _accelerate(velocity, wish_dir, SPEED, GROUND_ACCEL, delta)


func _process_air(delta: float, wish_dir: Vector3) -> void:
	if wish_dir == Vector3.ZERO:
		return

	var accel := AIR_ACCEL
	if _dash_timer > 0.0:
		accel *= DASH_AIR_ACCEL_MULT
	velocity = _accelerate(velocity, wish_dir, SPEED, accel, delta)

	var hs := Vector3(velocity.x, 0.0, velocity.z).length()
	if hs > SPEED * 1.2:
		var rate := AIR_TURN_RATE
		if _dash_timer > 0.0:
			rate = maxf(rate, DASH_TURN_RATE)
		velocity = _rotate_horizontal_toward(velocity, wish_dir, rate * delta)


func _process_compress(delta: float, wish_dir: Vector3, airborne: bool) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs > 0.05:
		var mult := COMPRESS_AIR_DECEL_MULT if airborne else 1.0
		var decel := minf(COMPRESS_DECEL * mult * delta, hs)
		velocity.x -= (hv.x / hs) * decel
		velocity.z -= (hv.z / hs) * decel

	if wish_dir != Vector3.ZERO:
		var steer := COMPRESS_AIR_STEER if airborne else COMPRESS_STEER
		var target_speed := SPEED * (0.9 if airborne else 0.7)
		velocity = _accelerate(velocity, wish_dir, target_speed, steer, delta)

		if airborne:
			var hs2 := Vector3(velocity.x, 0.0, velocity.z).length()
			if hs2 > SPEED * 1.2:
				velocity = _rotate_horizontal_toward(velocity, wish_dir, steer * 0.5 * delta)


func _clamp_horizontal() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs > MAX_SPEED:
		var r := MAX_SPEED / hs
		velocity.x *= r
		velocity.z *= r


# ============================================================
#  COMPRESS / LAUNCH
# ============================================================
func _start_compress() -> void:
	_is_compressing = true
	_compress_time = 0.0
	_set_crouch_shape(true)


func _end_compress(do_launch: bool) -> void:
	_is_compressing = false
	_set_crouch_shape(_tuck_timer > 0.0)

	if do_launch:
		var charge := _compute_charge(_compress_time)
		if charge > 0.0:
			var launch_dir := -transform.basis.z
			launch_dir.y = 0.0
			launch_dir = launch_dir.normalized()

			velocity.x += launch_dir.x * LAUNCH_IMPULSE * charge
			velocity.z += launch_dir.z * LAUNCH_IMPULSE * charge

			var up := LAUNCH_UP_POP * maxf(charge, 0.5)
			if velocity.y < up:
				velocity.y = up

			_jump_cut_ready = false # поп от лонча не должен обрезаться
			_dash_timer = DASH_WINDOW
			_launch_cooldown = LAUNCH_COOLDOWN
			Shaker.play(0.18, 0.3, Tween.TRANS_EXPO)

	_compress_time = 0.0


func _compute_charge(t: float) -> float:
	if t < COMPRESS_WINDOW_MIN:
		return lerpf(LAUNCH_MIN_CHARGE, 0.4, t / COMPRESS_WINDOW_MIN)
	elif t <= COMPRESS_WINDOW_MAX:
		return lerpf(0.4, 1.0, (t - COMPRESS_WINDOW_MIN) / (COMPRESS_WINDOW_MAX - COMPRESS_WINDOW_MIN))
	elif t <= COMPRESS_OVERHOLD:
		return lerpf(1.0, LAUNCH_MIN_CHARGE, (t - COMPRESS_WINDOW_MAX) / (COMPRESS_OVERHOLD - COMPRESS_WINDOW_MAX))
	else:
		return LAUNCH_MIN_CHARGE


func _set_crouch_shape(crouched: bool) -> void:
	if not _col_ready:
		return
	var cap := _col.shape as CapsuleShape3D
	if crouched:
		cap.height = _col_orig_height * 0.5
		_col.position.y = _col_orig_center_y - _col_orig_height * 0.25
	else:
		cap.height = _col_orig_height
		_col.position.y = _col_orig_center_y


# ============================================================
#  ПРИЦЕЛИВАНИЕ
# ============================================================
## Возвращает { "point": Vector3, "collider": Object или null }.
## 1) Точный луч из центра камеры.
## 2) Если луч промахнулся — сферический свип (aim-assist) по врагам.
func _find_aim_target() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := _aim_origin()
	var dir := -camera.global_transform.basis.z
	var to := from + dir * AIM_RANGE
	var self_rid := get_rid()

	# --- 1. Точный луч ---
	var ray := PhysicsRayQueryParameters3D.create(from, to, aim_mask, [self_rid])
	ray.collide_with_areas = true
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		return {"point": hit.position, "collider": hit.collider}

	# --- 2. Помощь прицела ---
	if assist_mask != 0:
		var sphere := SphereShape3D.new()
		sphere.radius = AIM_ASSIST_RADIUS

		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sphere
		q.transform = Transform3D(Basis.IDENTITY, from)
		q.motion = dir * AIM_RANGE
		q.collision_mask = assist_mask
		q.exclude = [self_rid]
		q.collide_with_areas = true

		var motion := space.cast_motion(q)
		if motion.size() == 2 and motion[1] < 1.0:
			# Сфера в точке касания -> узнаём, кого и где задели.
			q.transform = Transform3D(Basis.IDENTITY, from + dir * AIM_RANGE * motion[1])
			q.motion = Vector3.ZERO
			q.margin = 0.05
			var rest := space.get_rest_info(q)
			if not rest.is_empty():
				var target_point: Vector3 = rest.point
				var target_collider := instance_from_id(rest.collider_id)

				# Проверка прямой видимости: стены между нами и врагом не пропускаем.
				var los := PhysicsRayQueryParameters3D.create(from, target_point, aim_mask, [self_rid])
				los.collide_with_areas = true
				var los_hit := space.intersect_ray(los)
				if los_hit.is_empty() or los_hit.collider == target_collider:
					return {"point": target_point, "collider": target_collider}

	# --- Промах: летим вдоль линии прицела ---
	return {"point": to, "collider": null}


# ============================================================
#  ОРУЖИЕ
# ============================================================
## Реальная точка, из которой камера "видит" мир: Shaker двигает камеру
## через h_offset/v_offset, а global_position при этом не меняется.
func _aim_origin() -> Vector3:
	var b := camera.global_transform.basis
	return camera.global_position + b.x * camera.h_offset + b.y * camera.v_offset


func shoot() -> void:
	# Сначала считаем цель (до тряски камеры), потом эффекты.
	var target := _find_aim_target()
	var target_point: Vector3 = target.point

	Audio.play(&"shot")
	Shaker.play(0.15, 0.25, Tween.TRANS_EXPO)

	var bullet := BulletScene.instantiate() as Node3D
	get_tree().current_scene.add_child(bullet)
	# Старт на линии прицела, чуть впереди камеры (а не из смещённого дула).
	var origin := _aim_origin() - camera.global_transform.basis.z * 0.5
	bullet.global_transform = Transform3D(camera.global_transform.basis, origin)

	# Разворачиваем пулю к точке попадания (пуля летит по -Z).
	var to_target: Vector3 = target_point - bullet.global_position
	if to_target.length() > 0.1:
		var up := Vector3.UP
		if absf(to_target.normalized().dot(Vector3.UP)) > 0.999:
			up = Vector3.RIGHT
		bullet.look_at(target_point, up)

	# Необязательно: пуля может узнать цель (например, чтобы гарантированно попасть).
	if bullet.has_method("set_target"):
		bullet.set_target(target_point, target.collider)

	_apply_weapon_knockback()


func _apply_weapon_knockback() -> void:
	var aim := -camera.global_transform.basis.z
	var knock := -aim * WEAPON_KNOCKBACK
	if knock.y > 0.0:
		knock.y *= WEAPON_KNOCKBACK_UP_MULT
	knock = knock.limit_length(WEAPON_KNOCKBACK_MAX)
	velocity += knock


func take_damage(amount: int) -> void:
	health -= amount
	print("Игрок: ", health)
	if health <= 0:
		gameover.build("пососи")
