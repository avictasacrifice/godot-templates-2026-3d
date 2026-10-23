extends StaticBody3D

var health: int = 3
var _flash_material: StandardMaterial3D

func _ready() -> void:

	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color.WHITE
	$MeshInstance3D.material_override = _flash_material

func take_damage(amount: int) -> void:
	health -= amount
	print("Враг гандон: ", health)

	_flash_material.albedo_color = Color(1, 0, 0)  
	await get_tree().create_timer(0.1).timeout

	if not is_instance_valid(self):
		return
	_flash_material.albedo_color = Color.WHITE

	if health <= 0:
		die()

func die() -> void:
	print("Враг это гуль э э э ми а!")
	queue_free()
