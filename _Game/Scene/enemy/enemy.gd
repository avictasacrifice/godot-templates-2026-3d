extends CharacterBody3D
# ↑ ВАЖНО: смени тип корневой ноды с StaticBody3D на CharacterBody3D!

# ============================================================
#  НАСТРОЙКИ
# ============================================================
@export_group("Движение")
@export var move_speed: float = 3.5          # скорость преследования
@export var gravity: float = 20.0
@export var detection_range: float = 25.0    # с какого расстояния замечает игрока
@export var stop_distance: float = 1.0       # ближе не подходит (чтобы не влезать в игрока)
@export var rotation_speed: float = 8.0      # плавность разворота модели

@export_group("Атака")
@export var attack_range: float = 1.3        # радиус, в котором наносит урон
@export var damage: int = 1
@export var damage_cooldown: float = 1.0     # секунды между ударами

@export_group("Прочее")
@export var player_group: StringName = &"player"
@export var blood_scene: PackedScene

# ============================================================
#  СОСТОЯНИЕ
# ============================================================
var health: int = 3

var _flash_material: StandardMaterial3D
var _player: Node3D = null
var _damage_timer: float = 0.0
var _is_dead: bool = false


# ============================================================
#  ЖИЗНЕННЫЙ ЦИКЛ
# ============================================================
func _ready() -> void:
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color.WHITE
	$MeshInstance3D.material_override = _flash_material
	_refresh_player()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	# Кулдаун между ударами
	if _damage_timer > 0.0:
		_damage_timer -= delta

	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_refresh_player()

	# Игрока нет — стоим
	if not _player or not is_instance_valid(_player):
		_brake(delta)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# Преследование
	if dist <= detection_range and dist > stop_distance:
		var dir := to_player / dist
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed

		# Плавный разворот к игроку (модель должна "смотреть" в -Z)
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)
	else:
		_brake(delta)

	move_and_slide()

	# Проверка касания и урон
	_try_hit_player(dist)


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, move_speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, move_speed * 6.0 * delta)


func _refresh_player() -> void:
	if _player and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group(player_group)
	if not players.is_empty():
		_player = players[0] as Node3D


# ============================================================
#  КОНТАКТНЫЙ УРОН
# ============================================================
func _try_hit_player(dist: float) -> void:
	if _damage_timer > 0.0:
		return
	if not _player or not is_instance_valid(_player):
		return

	# Основная проверка — по дистанции
	var touching := dist <= attack_range

	# Страховка — по реальному столкновению после move_and_slide
	if not touching:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == _player:
				touching = true
				break

	if not touching:
		return

	if _player.has_method("take_damage"):
		_player.take_damage(damage)
		_damage_timer = damage_cooldown


# ============================================================
#  ПОЛУЧЕНИЕ УРОНА / СМЕРТЬ
# ============================================================
func take_damage(amount: int) -> void:
	if _is_dead:
		return

	health -= amount
	print("Враг: ", health)

	if health > 0:
		_spawn_blood(false)

	_flash_material.albedo_color = Color(1, 0, 0)
	await get_tree().create_timer(0.1).timeout

	if not is_instance_valid(self) or _is_dead:
		return
	_flash_material.albedo_color = Color.WHITE

	if health <= 0:
		die()


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	print("Враг сдох")

	_spawn_blood(true)
	set_physics_process(false)   # чтобы труп не толкал игрока
	queue_free()


# ============================================================
#  КРОВЬ (без изменений)
# ============================================================
func _spawn_blood(is_death: bool) -> void:
	if not blood_scene:
		return

	var blood = blood_scene.instantiate() as GPUParticles3D
	get_tree().current_scene.add_child(blood)

	blood.global_position = global_position + Vector3(0, 0, 0)

	blood.one_shot = true
	blood.explosiveness = 1.0
	blood.local_coords = false
	blood.emitting = false

	var mat = blood.process_material as ParticleProcessMaterial
	if mat:
		mat.direction = Vector3(0, 1, 0)
		mat.gravity = Vector3(0, -9.8, 0)

		if is_death:
			blood.amount = 200
			blood.lifetime = 4.0
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 12.0
			mat.spread = 180.0
			mat.scale_min = 0.5
			mat.scale_max = 1.5
		else:
			blood.amount = 30
			blood.lifetime = 4.0
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 5.0
			mat.spread = 45.0
			mat.scale_min = 0.2
			mat.scale_max = 0.5

	blood.restart()

	var timer = get_tree().create_timer(blood.lifetime + 0.5)
	timer.timeout.connect(func():
		if is_instance_valid(blood):
			blood.queue_free()
	)
