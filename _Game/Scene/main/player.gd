extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002          # радианы на пиксель — подкрути по вкусу
const PITCH_LIMIT = deg_to_rad(89.0)     # чтобы камера не переворачивалась

@export var BulletScene : PackedScene

@onready var camera: Camera3D = $Camera3D
@onready var muzzle: Marker3D = $Camera3D/Muzzle

var _pitch: float = 0.0   # накопленный наклон камеры по X

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# --- ESC — отпустить/захватить курсор ---
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# --- Поворот мышью ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw — вращаем всё тело вокруг вертикальной оси
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		# Pitch — наклоняем только камеру, с ограничением
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		camera.rotation.x = _pitch

	# --- Выстрел (только когда курсор захвачен) ---
	if event.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("space") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# transform.basis у тела — только yaw, поэтому движение «плоское» и корректное
	var input_dir := Input.get_vector("a", "d", "w", "s")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func shoot() -> void:
	var bullet := BulletScene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = muzzle.global_transform
