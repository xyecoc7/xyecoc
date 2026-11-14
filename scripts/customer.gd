extends Node3D
## Посетитель: идёт к месту, делает заказ, ждёт, уходит.

var main
var seat_id := 0
var order := ""
var path: Array = []
var state := "in"  # in -> wait -> leave
var patience := 70.0
var max_patience := 70.0
var speed := 2.6
var label: Label3D


func _ready() -> void:
	add_to_group("customers")
	var color := Color.from_hsv(randf(), 0.45, 0.5)

	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.3
	body.mesh = cm
	body.position.y = 0.65
	body.material_override = main.mat(color)
	add_child(body)

	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	head.mesh = sm
	head.position.y = 1.5
	head.material_override = main.mat(Color(0.75, 0.65, 0.55))
	add_child(head)

	# Тело для луча игрока (слой 2 — игрок сквозь гостей проходит).
	var sb := StaticBody3D.new()
	sb.collision_layer = 2
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	sb.add_child(cs)
	sb.set_meta("iid", "customer")
	sb.set_meta("ref", self)
	add_child(sb)

	label = Label3D.new()
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.005
	label.outline_size = 8
	add_child(label)


func _process(delta: float) -> void:
	if not path.is_empty():
		var target: Vector3 = path[0]
		var to := target - position
		to.y = 0.0
		if to.length() < 0.1:
			path.pop_front()
		else:
			position += to.normalized() * minf(speed * delta, to.length())
			rotation.y = atan2(to.x, to.z)
	elif state == "in":
		state = "wait"
	elif state == "leave":
		queue_free()
		return

	if state == "wait":
		patience -= delta
		label.text = "%s\n%d с" % [order, int(maxf(patience, 0.0))]
		label.modulate = Color(1, 1, 1).lerp(Color(1, 0.3, 0.2), 1.0 - patience / max_patience)
		if patience <= 0.0:
			main.customer_failed(self)
			leave()
	elif state == "in":
		label.text = order
	else:
		label.text = ""


func leave() -> void:
	if state == "leave":
		return
	state = "leave"
	main.free_seat(seat_id)
	path = main.leave_path(seat_id)
