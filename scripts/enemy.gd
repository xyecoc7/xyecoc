extends CharacterBody3D
## Враг: робот в Полях роботов или тень в Сумеречном лесу.
## Бродит у дома, замечает игрока в радиусе 12 м, бьёт вблизи.

var main
var color := Color(0.5, 0.5, 0.55)
var eye_color := Color(1.0, 0.2, 0.1)
var drops_gear := true
var max_hp := 3
var hp := 3
var damage := 10
var home := Vector3.ZERO
var cd := 0.0
var dead := false
var wander := Vector3.ZERO
var wander_t := 0.0
var flash_t := 0.0
var body_mat: StandardMaterial3D


func _ready() -> void:
	home = position
	hp = max_hp
	set_meta("iid", "enemy")

	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.9, 1.5, 0.9)
	cs.shape = sh
	cs.position.y = 0.75
	add_child(cs)

	body_mat = main.mat(color)
	_part(Vector3(0, 0.5, 0), Vector3(0.9, 0.8, 0.9), body_mat)
	_part(Vector3(0, 1.2, 0), Vector3(0.6, 0.5, 0.6), body_mat)
	var eye_mat: StandardMaterial3D = main.mat(eye_color, 3.0)
	_part(Vector3(-0.15, 1.25, 0.31), Vector3(0.12, 0.08, 0.02), eye_mat)
	_part(Vector3(0.15, 1.25, 0.31), Vector3(0.12, 0.08, 0.02), eye_mat)


func _part(pos: Vector3, size: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _physics_process(delta: float) -> void:
	if dead:
		return
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			body_mat.albedo_color = color
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	var p: Vector3 = main.player.global_position
	var d := p - global_position
	d.y = 0.0
	var dist := d.length()
	var move := Vector3.ZERO
	if dist < 12.0 and absf(p.y - global_position.y) < 3.0:
		if dist > 1.2:
			move = d.normalized() * 2.6
		rotation.y = atan2(d.x, d.z)
		cd -= delta
		if dist < 1.7 and cd <= 0.0:
			cd = 1.0
			main.damage(damage)
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(2.0, 4.0)
			wander = home + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
		var w := wander - global_position
		w.y = 0.0
		if w.length() > 0.5:
			move = w.normalized() * 1.2
			rotation.y = atan2(w.x, w.z)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


func hit() -> void:
	if dead:
		return
	hp -= 1
	body_mat.albedo_color = Color(1, 1, 1)
	flash_t = 0.15
	var back: Vector3 = global_position - main.player.global_position
	back.y = 0.0
	global_position += back.normalized() * 0.7
	if hp <= 0:
		dead = true
		visible = false
		collision_layer = 0
		main.enemy_killed(self)
		get_tree().create_timer(30.0).timeout.connect(_respawn)


func _respawn() -> void:
	dead = false
	hp = max_hp
	position = home
	visible = true
	collision_layer = 1
