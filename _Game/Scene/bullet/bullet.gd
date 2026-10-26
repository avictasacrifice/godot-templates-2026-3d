extends Area3D

const SPEED := 120.0      
const LIFETIME := 2.0   

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	
	global_position += -global_transform.basis.z * SPEED * delta

func _on_body_entered(body: Node) -> void:
	Audio.play(&"hit")
	if body.has_method("take_damage"):
		body.take_damage(1)
	queue_free()   
