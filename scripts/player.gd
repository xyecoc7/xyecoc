extends CharacterBody3D
## Игрок от первого лица: ходьба, прыжок, взгляд мышью, луч для взаимодействия.

const SPEED := 5.0
const JUMP := 7.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.003

var main
var cam: Camera3D
var ray: RayCast3D
var hand: MeshInstance3D
var hand_mat: StandardMaterial3D
var lantern_light: OmniLight3D


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)

	cam = Camera3D.new()
	cam.position.y = 1.6
	cam.fov = 75.0
	add_child(cam)
	cam.current = true

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -3.0)
	ray.collision_mask = 3  # слой 1 — мир и предметы, слой 2 — гости
	ray.add_exception(self)
	cam.add_child(ray)

	# Предмет в руках — просто цветной кубик.
	hand = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 0.18)
	hand.mesh = bm
	hand_mat = StandardMaterial3D.new()
	hand.material_override = hand_mat
	hand.position = Vector3(0.35, -0.3, -0.6)
	hand.visible = false
	cam.add_child(hand)

	# Фонарь Шампика освещает путь в Сумеречном лесу.
	lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color(0.45, 0.6, 1.0)
	lantern_light.omni_range = 12.0
	lantern_light.light_energy = 1.6
	lantern_light.position = Vector3(-0.3, -0.2, -0.3)
	lantern_light.visible = false
	cam.add_child(lantern_light)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		cam.rotate_x(-event.relative.y * MOUSE_SENS)
		cam.rotation.x = clampf(cam.rotation.x, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP
	var input := Input.get_vector("left", "right", "forward", "back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	move_and_slide()
	if global_position.y < -20.0:
		main.respawn()


func looked_at() -> Object:
	if ray.is_colliding():
		return ray.get_collider()
	return null


func show_held(item: String, color: Color) -> void:
	hand.visible = item != ""
	hand_mat.albedo_color = color
