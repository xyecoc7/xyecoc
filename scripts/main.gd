extends Node3D
## «Таверна» — прототип из простых фигур.
## Весь мир строится кодом: таверна, двор, Поля роботов, Сумеречный лес.

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const CUSTOMER_SCRIPT = preload("res://scripts/customer.gd")
const ENEMY_SCRIPT = preload("res://scripts/enemy.gd")

# Локации разнесены далеко друг от друга, переход — через порталы.
const FIELD := Vector3(300, 0, 0)
const FOREST := Vector3(-300, 0, 0)
const HOME_SPAWN := Vector3(0, 0.2, 16)
const CUSTOMER_SPAWN := Vector3(0, 0, 30)
const DOOR_OUT := Vector3(0, 0, 7.5)
const DOOR_IN := Vector3(0, 0, 4.5)

const WOOD := Color(0.33, 0.22, 0.13)
const DARK_WOOD := Color(0.2, 0.13, 0.08)
const STONE := Color(0.3, 0.3, 0.33)
const COPPER := Color(0.72, 0.42, 0.2)

const PRICES := {"самогон": 5, "рагу": 8, "грибной суп": 15}

const ITEM_COLORS := {
	"продукты": Color(0.55, 0.35, 0.2),
	"нарезка": Color(0.9, 0.55, 0.5),
	"рагу": Color(0.85, 0.45, 0.1),
	"грибной суп": Color(0.2, 0.8, 0.7),
	"самогон": Color(0.9, 0.9, 0.8),
	"разбитый фонарь": Color(0.4, 0.4, 0.45),
	"синий огонь": Color(0.2, 0.4, 1.0),
	"медная вытяжка": COPPER,
	"змеевик": COPPER,
	"тиски": Color(0.5, 0.5, 0.55),
	"синяя лампа": Color(0.3, 0.5, 1.0),
}

# Украшение -> какой верстак оно улучшает (как в Valheim: ставишь рядом — уровень растёт).
const DECOR_FOR := {
	"медная вытяжка": "stove",
	"змеевик": "still",
	"тиски": "tools_bench",
	"синяя лампа": "inv_bench",
}

const STATION_NAMES := {
	"cutting": "Стол для разделки",
	"stove": "Плитка",
	"still": "Самогонный аппарат",
	"tools_bench": "Верстак инструментов",
	"inv_bench": "Верстак изобретений",
}

# kind: tool — остаётся у игрока навсегда; held — предмет в руки; build — ставится в таверне.
# req: "" — сразу; lvl2 — верстак улучшен; fire / lantern — этапы квеста Шампика.
const RECIPES := {
	"tools_bench": [
		{"name": "метла", "cost": {"монеты": 5}, "kind": "tool", "req": ""},
		{"name": "медная вытяжка", "cost": {"шестерёнка": 2}, "kind": "held", "req": ""},
		{"name": "змеевик", "cost": {"шестерёнка": 2}, "kind": "held", "req": ""},
		{"name": "тиски", "cost": {"шестерёнка": 1, "светогриб": 1}, "kind": "held", "req": ""},
		{"name": "молоток", "cost": {"монеты": 15, "шестерёнка": 1}, "kind": "tool", "req": "lvl2"},
	],
	"inv_bench": [
		{"name": "синий огонь", "cost": {"шестерёнка": 2}, "kind": "held", "req": "fire"},
		{"name": "фонарь", "cost": {"шестерёнка": 1, "монеты": 10}, "kind": "tool", "req": "lantern"},
		{"name": "синяя лампа", "cost": {"шестерёнка": 2, "светогриб": 2}, "kind": "held", "req": ""},
		{"name": "слот-машина", "cost": {"шестерёнка": 3, "монеты": 30}, "kind": "build", "req": "lvl2"},
	],
}

var rng := RandomNumberGenerator.new()
var player

# Состояние игры
var money := 20
var rep := 0
var hp := 100.0
var held := ""
var mats := {"шестерёнка": 0, "светогриб": 0}
var tools := {}
var flags := {}
var quest_stage := 0
var houses := 0

var stations := {}
var station_nodes := {}
var bench_index := {"tools_bench": 0, "inv_bench": 0}
var seats: Array = []
var vip_seats: Array = []
var concert_seats: Array = []
var vip_doors: Array = []
var concert_door: Node3D
var stairs_gate: Node3D
var lost_lantern: Node3D
var shampik_light: OmniLight3D
var plots: Array = []

var spawn_t := 3.0
var slot_t := 6.0
var rent_t := 20.0
var attack_cd := 0.0
var msg_t := 0.0

var info_label: Label
var quest_label: Label
var msg_label: Label
var hint_label: Label
var help_label: Label
var cross_label: Label


func _ready() -> void:
	rng.seed = 7
	setup_input()
	build_environment()
	build_tavern()
	build_yard()
	build_field()
	build_forest()
	build_ui()
	player = PLAYER_SCRIPT.new()
	player.main = self
	add_child(player)
	player.global_position = HOME_SPAWN
	msg("Вы пришли к старой полуразрушенной таверне. Поговорите с Шампиком во дворе.", 8.0)


# ---------------------------------------------------------------- ввод

func setup_input() -> void:
	var keys := {
		"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"jump": KEY_SPACE, "interact": KEY_E, "cycle": KEY_R,
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


# ---------------------------------------------------------------- простые фигуры

func mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## Коробка. pos — центр. С collide=true возвращает StaticBody3D (по нему попадает луч).
func box(pos: Vector3, size: Vector3, color: Color, collide := true, iid := "", parent: Node = null, glow := 0.0) -> Node3D:
	if parent == null:
		parent = self
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color, glow)
	if not collide:
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.add_child(mi)
	if iid != "":
		body.set_meta("iid", iid)
	parent.add_child(body)
	return body


func shape(mesh: Mesh, pos: Vector3, color: Color, parent: Node = null, glow := 0.0) -> MeshInstance3D:
	if parent == null:
		parent = self
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, glow)
	mi.position = pos
	parent.add_child(mi)
	return mi


func cylinder(r_top: float, r_bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	return c


func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func label3d(text: String, pos: Vector3, parent: Node = null, size := 36) -> Label3D:
	if parent == null:
		parent = self
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 8
	parent.add_child(l)
	return l


func light(pos: Vector3, color: Color, rng_m := 8.0, energy := 1.2, parent: Node = null) -> OmniLight3D:
	if parent == null:
		parent = self
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.omni_range = rng_m
	o.light_energy = energy
	parent.add_child(o)
	return o


func set_active(body, on: bool) -> void:
	body.visible = on
	if body is CollisionObject3D:
		body.collision_layer = 1 if on else 0


## Стена вдоль X на линии z, с проёмами gaps = [[x0, x1], ...]. ruined — неровный верх.
func wall_z(z: float, x0: float, x1: float, gaps: Array = [], ruined := true) -> void:
	var cuts: Array = [x0]
	for g in gaps:
		cuts.append(g[0])
		cuts.append(g[1])
	cuts.append(x1)
	for i in range(0, cuts.size(), 2):
		_wall_run(Vector3(cuts[i], 0, z), Vector3(cuts[i + 1], 0, z), ruined)


func wall_x(x: float, z0: float, z1: float, gaps: Array = [], ruined := true) -> void:
	var cuts: Array = [z0]
	for g in gaps:
		cuts.append(g[0])
		cuts.append(g[1])
	cuts.append(z1)
	for i in range(0, cuts.size(), 2):
		_wall_run(Vector3(x, 0, cuts[i]), Vector3(x, 0, cuts[i + 1]), ruined)


func _wall_run(a: Vector3, b: Vector3, ruined: bool) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var pieces := maxi(1, int(ceil(length / 2.0)))
	for p in range(pieces):
		var t0 := float(p) / pieces
		var t1 := float(p + 1) / pieces
		var pa := a.lerp(b, t0)
		var pb := a.lerp(b, t1)
		var h := 3.0
		if ruined:
			h = rng.randf_range(1.6, 3.0)
		var c := (pa + pb) / 2.0
		var size := Vector3(absf(pb.x - pa.x), h, absf(pb.z - pa.z))
		size.x = maxf(size.x, 0.3)
		size.z = maxf(size.z, 0.3)
		box(Vector3(c.x, h / 2.0, c.z), size, WOOD.lerp(STONE, rng.randf_range(0.0, 0.5)))


# ---------------------------------------------------------------- мир

func build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.5)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.1, 0.16)
	env.fog_density = 0.02
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.light_color = Color(0.6, 0.65, 0.95)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	add_child(moon)


func add_seat(pos: Vector3, kind: String, active: bool, mult := 1.0, via: Array = []) -> int:
	seats.append({"pos": pos, "kind": kind, "active": active, "taken": false, "mult": mult, "via": via})
	return seats.size() - 1


func table(pos: Vector3) -> void:
	box(pos + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 1.0), DARK_WOOD)
	shape(cylinder(0.2, 0.2, 0.5), pos + Vector3(0, 0.25, 1.0), WOOD)
	shape(sphere(0.12), pos + Vector3(0.3, 0.95, 0), Color(1, 0.7, 0.3), null, 2.0)


func build_tavern() -> void:
	# Земля и пол
	box(Vector3(0, -0.1, 8), Vector3(90, 0.2, 90), Color(0.1, 0.14, 0.09))
	box(Vector3(0, 0.01, -3), Vector3(28, 0.02, 18), Color(0.24, 0.17, 0.11), false)

	# Стены. Главный зал x -8..8, z -6..6; кухня и подсобка x 8..14; ВИП x -14..-8; концертный зал z -12..-6.
	wall_z(6, -14, 14, [[-1, 1]])
	wall_z(-6, -14, -8)
	wall_z(-6, -8, 8, [[-1, 1]], false)
	wall_z(-6, 8, 14)
	wall_z(-12, -8, 8)
	wall_x(-8, -12, -6)
	wall_x(8, -12, -6)
	wall_x(-14, -6, 6)
	wall_x(-8, -6, 6, [[-3.8, -2.2], [2.2, 3.8]], false)
	wall_z(0, -14, -8, [], false)
	wall_x(8, -6, 6, [[-4.0, -2.4], [2.0, 3.6]], false)
	wall_x(14, -6, 6)
	wall_z(0, 8, 14, [[10.0, 11.6]], false)

	label3d("ТАВЕРНА", Vector3(0, 3.6, 6.3), null, 96)
	light(Vector3(0, 2.6, 0), Color(1, 0.7, 0.4), 11.0, 1.4)
	light(Vector3(11, 2.5, -3), Color(1, 0.65, 0.35), 7.0, 1.2)
	light(Vector3(11, 2.5, 3), Color(1, 0.65, 0.35), 7.0, 1.0)

	# --- Главный зал: барная стойка и столы
	box(Vector3(6, 0.55, -2.5), Vector3(0.8, 1.1, 5), DARK_WOOD, true, "bar")
	label3d("Барная стойка", Vector3(6, 1.6, -2.5))
	for z in [-4.0, -2.5, -1.0]:
		add_seat(Vector3(5, 0, z), "bar", true)
		shape(cylinder(0.22, 0.22, 0.7), Vector3(5.2, 0.35, z), WOOD)

	var table_pos := [Vector3(-5, 0, -3), Vector3(-1, 0, -3), Vector3(-5, 0, 2), Vector3(-1, 0, 2), Vector3(3, 0, 2)]
	var table_seats := []
	for i in range(table_pos.size()):
		table(table_pos[i])
		table_seats.append(add_seat(table_pos[i] + Vector3(0, 0, 1.0), "table", i < 2))

	# Завалы мусора закрывают три стола, пока их не расчистят метлой.
	for i in [2, 3, 4]:
		var p: Vector3 = table_pos[i] + Vector3(0.4, 0, -0.1)
		var d := box(p + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 2.0), Color(0.18, 0.16, 0.14), true, "debris")
		d.set_meta("seat", table_seats[i])
		var plank := shape(cylinder(0.1, 0.1, 2.0), Vector3(0.3, 0.3, 0.2), WOOD, d)
		plank.rotation_degrees = Vector3(0, 30, 80)
		label3d("Завал", Vector3(0, 1.0, 0), d)

	# --- Кухня
	station(Vector3(9.6, 0.45, -5.4), Vector3(1.4, 0.9, 0.7), Color(0.45, 0.32, 0.2), "cutting")
	station(Vector3(11.6, 0.45, -5.4), Vector3(1.0, 0.9, 0.8), Color(0.15, 0.15, 0.17), "stove")
	shape(cylinder(0.2, 0.2, 0.05), Vector3(11.6, 0.93, -5.4), Color(1, 0.3, 0.1), null, 2.5)
	station(Vector3(13.3, 0.7, -2.0), Vector3(0.9, 1.4, 0.9), COPPER, "still")
	box(Vector3(13.3, 0.4, -5.2), Vector3(1.0, 0.8, 1.0), Color(0.5, 0.36, 0.2), true, "pantry")
	label3d("Ящик с продуктами", Vector3(13.3, 1.3, -5.2))
	box(Vector3(9.0, 0.3, -0.7), Vector3(0.5, 0.6, 0.5), Color(0.25, 0.25, 0.25), true, "trash")
	label3d("Мусор", Vector3(9.0, 0.9, -0.7))

	# --- Подсобка с верстаками
	station(Vector3(13.2, 0.5, 2.0), Vector3(1.0, 1.0, 2.0), Color(0.45, 0.3, 0.18), "tools_bench")
	station(Vector3(11.0, 0.5, 5.3), Vector3(2.0, 1.0, 0.8), Color(0.25, 0.3, 0.4), "inv_bench")

	# --- ВИП-комнаты (закрыты до репутации 5)
	for z in [-3.0, 3.0]:
		table(Vector3(-11.5, 0, z))
		vip_seats.append(add_seat(Vector3(-10.4, 0, z), "table", false, 2.0, [Vector3(-6, 0, z), Vector3(-9.5, 0, z)]))
		var door := box(Vector3(-8, 1.5, z), Vector3(0.35, 3, 1.6), Color(0.35, 0.08, 0.08), true, "door_vip")
		vip_doors.append(door)
	label3d("ВИП-комнаты\n(репутация 5)", Vector3(-8.3, 3.4, 0))

	# --- Концертный зал (закрыт до репутации 10)
	box(Vector3(0, 0.3, -11), Vector3(6, 0.6, 1.6), Color(0.3, 0.15, 0.35))
	light(Vector3(0, 2.5, -10), Color(0.8, 0.4, 1.0), 8.0, 1.0)
	for x in [-4.0, 4.0]:
		table(Vector3(x, 0, -8.6))
		concert_seats.append(add_seat(Vector3(x, 0, -7.6), "table", false, 1.5, [Vector3(0, 0, -4.5), Vector3(0, 0, -7.4)]))
	concert_door = box(Vector3(0, 1.5, -6), Vector3(2, 3, 0.35), Color(0.35, 0.08, 0.08), true, "door_concert")
	label3d("Концертный зал (репутация 10)", Vector3(0, 3.4, -5.7))

	# --- Второй этаж: пандус снаружи и комнаты на крыше кухни (закрыт до репутации 15)
	box(Vector3(11, 3.15, 0), Vector3(6.2, 0.3, 12.2), DARK_WOOD)
	for z in [-4.0, 0.0, 4.0]:
		box(Vector3(10, 3.5, z), Vector3(1.0, 0.4, 2.0), Color(0.6, 0.2, 0.2))
	label3d("Комнаты для гостей", Vector3(11, 4.8, 0))
	# Пока лестница разрушена — только обломки.
	stairs_gate = box(Vector3(15.1, 0.4, 7.5), Vector3(1.8, 0.8, 1.6), Color(0.25, 0.2, 0.15), true, "stairs")
	label3d("Разрушенная лестница\nвторой этаж (репутация 15)", Vector3(0, 1.3, 0), stairs_gate)


func build_stairs() -> void:
	var rise := 3.3
	var run := 12.4
	var ramp := box(Vector3(15.1, 1.47, 2.0), Vector3(1.8, 0.3, run), WOOD)
	ramp.rotation.x = atan2(rise, run)
	box(Vector3(15.1, 3.15, -5.0), Vector3(2.0, 0.3, 2.2), WOOD)


func station(pos: Vector3, size: Vector3, color: Color, id: String) -> void:
	var n := box(pos, size, color, true, id)
	station_nodes[id] = n
	stations[id] = {"level": 1, "busy": false, "t": 0.0, "pending": "", "ready": "", "mode": "рагу"}
	var l := label3d(STATION_NAMES[id], Vector3(0, size.y / 2.0 + 0.5, 0), n)
	n.set_meta("label", l)


func build_yard() -> void:
	# Шампик — человек-гриб
	var s := box(Vector3(5, 0.8, 12), Vector3(0.8, 1.6, 0.8), Color(0, 0, 0), true, "shampik")
	var helper_mesh := s.get_child(1) as Node3D
	helper_mesh.visible = false  # прячем служебную коробку, видны только фигуры
	shape(cylinder(0.22, 0.28, 1.0), Vector3(0, -0.3, 0), Color(0.9, 0.85, 0.75), s)
	shape(cylinder(0.15, 0.75, 0.5), Vector3(0, 0.45, 0), Color(0.55, 0.2, 0.15), s)
	shape(sphere(0.05), Vector3(-0.1, -0.05, 0.25), Color(0, 0, 0), s)
	shape(sphere(0.05), Vector3(0.1, -0.05, 0.25), Color(0, 0, 0), s)
	label3d("Шампик", Vector3(0, 1.1, 0), s)
	shampik_light = light(Vector3(0.5, 0, 0.3), Color(0.3, 0.5, 1.0), 5.0, 1.5, s)
	shampik_light.visible = false

	portal(Vector3(-10, 0, 24), "portal_robots", "Поля роботов", Color(0.9, 0.5, 0.2))
	portal(Vector3(10, 0, 24), "portal_forest", "Сумеречный лес", Color(0.4, 0.3, 0.9))

	for p in [Vector3(-13, 0, 13), Vector3(-13, 0, 19), Vector3(15, 0, 17)]:
		var plot := box(p + Vector3(0, 0.05, 0), Vector3(4, 0.1, 4), Color(0.3, 0.25, 0.15), true, "plot")
		plot.set_meta("label", label3d("Участок под дом\n(молоток + 40 монет)", p + Vector3(0, 1.2, 0)))
		plots.append(plot)

	# Пара фонарных столбов во дворе
	for p in [Vector3(-2.5, 0, 9), Vector3(2.5, 0, 9)]:
		box(p + Vector3(0, 1.2, 0), Vector3(0.15, 2.4, 0.15), DARK_WOOD)
		shape(sphere(0.18), p + Vector3(0, 2.5, 0), Color(1, 0.7, 0.3), null, 3.0)
		light(p + Vector3(0, 2.5, 0), Color(1, 0.7, 0.4), 7.0, 1.0)


func portal(pos: Vector3, iid: String, title: String, color: Color) -> void:
	box(pos + Vector3(-1.2, 1.5, 0), Vector3(0.4, 3, 0.4), STONE)
	box(pos + Vector3(1.2, 1.5, 0), Vector3(0.4, 3, 0.4), STONE)
	box(pos + Vector3(0, 3.1, 0), Vector3(2.8, 0.4, 0.4), STONE)
	box(pos + Vector3(0, 1.45, 0), Vector3(2.0, 2.9, 0.1), color, true, iid, null, 1.5)
	light(pos + Vector3(0, 1.5, 0.8), color, 5.0, 1.0)
	label3d(title, pos + Vector3(0, 3.8, 0), null, 48)


func build_field() -> void:
	var f := FIELD
	box(f + Vector3(0, -0.1, 0), Vector3(70, 0.2, 70), Color(0.32, 0.3, 0.16))
	light(f + Vector3(0, 8, 0), Color(1, 0.8, 0.6), 40.0, 0.8)
	for i in range(18):
		var p := f + Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 15))
		var sz := Vector3(rng.randf_range(0.6, 2.0), rng.randf_range(0.4, 1.5), rng.randf_range(0.6, 2.0))
		box(p + Vector3(0, sz.y / 2.0, 0), sz, Color(0.35, 0.33, 0.3))
	# Обломки старых роботов
	for i in range(6):
		var p := f + Vector3(rng.randf_range(-25, 25), 0.3, rng.randf_range(-25, 10))
		var junk := box(p, Vector3(0.6, 0.6, 0.6), Color(0.4, 0.4, 0.45), false)
		junk.rotation_degrees = Vector3(20, rng.randf_range(0, 90), 30)
	for i in range(6):
		var p := f + Vector3(rng.randf_range(-22, 22), 0.2, rng.randf_range(-25, 8))
		spawn_enemy(p, Color(0.5, 0.52, 0.58), Color(1, 0.25, 0.1), true, 3)

	lost_lantern = box(f + Vector3(18, 0.25, -22), Vector3(0.3, 0.5, 0.3), Color(0.5, 0.5, 0.6), true, "lost_lantern")
	lost_lantern.set_meta("label", label3d("Фонарь Шампика", Vector3(0, 0.8, 0), lost_lantern))
	set_active(lost_lantern, false)

	portal(f + Vector3(0, 0, 26), "portal_home", "Домой, в таверну", Color(1, 0.7, 0.3))
	label3d("ПОЛЯ РОБОТОВ", f + Vector3(0, 4, 18), null, 96)


func build_forest() -> void:
	var g := FOREST
	box(g + Vector3(0, -0.1, 0), Vector3(70, 0.2, 70), Color(0.05, 0.07, 0.06))
	for i in range(55):
		var p := g + Vector3(rng.randf_range(-32, 32), 0, rng.randf_range(-32, 32))
		if absf(p.x - g.x) < 3.0 and p.z - g.z > 10.0:
			continue  # тропинка от портала
		var h := rng.randf_range(3.0, 6.0)
		box(p + Vector3(0, h / 2.0, 0), Vector3(0.4, h, 0.4), Color(0.12, 0.09, 0.08))
		shape(cylinder(0.0, rng.randf_range(1.2, 2.0), h * 0.8), p + Vector3(0, h, 0), Color(0.06, 0.12, 0.1))
	for i in range(10):
		var p := g + Vector3(rng.randf_range(-28, 28), 0, rng.randf_range(-28, 15))
		var m := box(p + Vector3(0, 0.25, 0), Vector3(0.4, 0.5, 0.4), Color(0.2, 0.9, 0.9), true, "mushroom", null, 2.5)
		light(Vector3(0, 0.5, 0), Color(0.2, 0.9, 0.9), 3.5, 1.0, m)
	for i in range(4):
		var p := g + Vector3(rng.randf_range(-20, 20), 0.2, rng.randf_range(-25, 5))
		spawn_enemy(p, Color(0.06, 0.05, 0.08), Color(0.7, 0.2, 1.0), false, 4)
	portal(g + Vector3(0, 0, 26), "portal_home", "Домой, в таверну", Color(1, 0.7, 0.3))
	label3d("СУМЕРЕЧНЫЙ ЛЕС", g + Vector3(0, 4, 18), null, 96)


func spawn_enemy(pos: Vector3, color: Color, eye: Color, gear: bool, hp_max: int) -> void:
	var e = ENEMY_SCRIPT.new()
	e.main = self
	e.color = color
	e.eye_color = eye
	e.drops_gear = gear
	e.max_hp = hp_max
	e.position = pos
	add_child(e)


# ---------------------------------------------------------------- интерфейс

func make_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	info_label = make_label(cl, Vector2(16, 12), 18)
	quest_label = make_label(cl, Vector2(16, 150), 18)
	quest_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	msg_label = make_label(cl, Vector2(0, 40), 22)
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	hint_label = make_label(cl, Vector2(0, 0), 20)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label = make_label(cl, Vector2(16, 0), 15)
	help_label.text = "WASD — ходить   Пробел — прыжок   E — действие   R — сменить рецепт   ЛКМ — удар   Esc — курсор"
	cross_label = make_label(cl, Vector2(0, 0), 24)
	cross_label.text = "+"


func msg(text: String, seconds := 4.0) -> void:
	msg_label.text = text
	msg_label.reset_size()
	msg_t = seconds


func update_ui(delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var tool_list := PackedStringArray()
	for t in tools:
		tool_list.append(t)
	info_label.text = "Монеты: %d    Репутация: %d    Здоровье: %d\nВ руках: %s\nШестерёнки: %d    Светогрибы: %d\nИнструменты: %s\nЖители: %d" % [
		money, rep, int(hp), held if held != "" else "—",
		mats["шестерёнка"], mats["светогриб"],
		", ".join(tool_list) if not tool_list.is_empty() else "—", houses]
	quest_label.text = quest_text()

	msg_t -= delta
	msg_label.visible = msg_t > 0.0
	msg_label.position = Vector2((vs.x - msg_label.size.x) / 2.0, 40)

	hint_label.text = hint_for(player.looked_at())
	hint_label.reset_size()
	hint_label.position = Vector2((vs.x - hint_label.size.x) / 2.0, vs.y * 0.6)
	help_label.position = Vector2(16, vs.y - 32)
	cross_label.reset_size()
	cross_label.position = (vs - cross_label.size) / 2.0
	player.show_held(held, ITEM_COLORS.get(held, Color.WHITE))


func quest_text() -> String:
	match quest_stage:
		0:
			return "Задание: поговорите с Шампиком во дворе"
		1:
			return "Задание: найдите фонарь Шампика в Полях роботов"
		2:
			return "Задание: отнесите фонарь Шампику"
		3:
			return "Задание: сделайте синий огонь (верстак изобретений) и отдайте Шампику"
		4:
			return "Задание: сделайте себе фонарь на верстаке изобретений"
	return "Сумеречный лес открыт. Собирайте светогрибы, улучшайте таверну."


# ---------------------------------------------------------------- игровой цикл

func _process(delta: float) -> void:
	attack_cd -= delta
	if Input.is_action_just_pressed("interact"):
		do_interact(player.looked_at())
	if Input.is_action_just_pressed("cycle"):
		do_cycle(player.looked_at())
	if Input.is_action_just_pressed("attack"):
		do_attack(player.looked_at())

	for id in stations:
		var s = stations[id]
		if s["busy"]:
			s["t"] -= delta
			if s["t"] <= 0.0:
				s["busy"] = false
				s["ready"] = s["pending"]

	if at_home():
		hp = minf(100.0, hp + 5.0 * delta)
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = maxf(5.0, 13.0 - houses * 2.0)
			try_spawn_customer()

	slot_t -= delta
	if slot_t <= 0.0:
		slot_t = 6.0
		if flags.has("слот-машина") and get_tree().get_nodes_in_group("customers").size() > 0:
			money += 2
	rent_t -= delta
	if rent_t <= 0.0:
		rent_t = 20.0
		if flags.has("rooms"):
			money += 5

	update_ui(delta)


func at_home() -> bool:
	return absf(player.global_position.x) < 100.0


func iid_of(target: Object) -> String:
	if target == null or not target.has_meta("iid"):
		return ""
	return target.get_meta("iid")


func do_interact(target_obj: Object) -> void:
	var iid := iid_of(target_obj)
	var target = target_obj
	match iid:
		"pantry":
			if held != "":
				msg("Руки заняты")
			elif money < 1:
				msg("Нет денег даже на продукты")
			else:
				money -= 1
				held = "продукты"
		"cutting", "stove", "still":
			use_station(iid)
		"tools_bench", "inv_bench":
			use_bench(iid)
		"trash":
			if held != "":
				msg("Выброшено: " + held)
				held = ""
		"bar":
			msg("Напитки выдаются гостям у стойки. Подойдите к гостю с самогоном.")
		"customer":
			serve(target.get_meta("ref"))
		"debris":
			if tools.has("метла"):
				seats[target.get_meta("seat")]["active"] = true
				target.queue_free()
				msg("Завал расчищен! Теперь за этим столом могут сидеть гости.")
			else:
				msg("Нужна метла — её можно сделать на верстаке инструментов в подсобке.")
		"shampik":
			talk_shampik()
		"lost_lantern":
			if held != "":
				msg("Руки заняты")
			else:
				held = "разбитый фонарь"
				quest_stage = 2
				set_active(lost_lantern, false)
				msg("Вы нашли фонарь Шампика. Кажется, он разбит...")
		"portal_robots":
			if quest_stage >= 1:
				teleport(FIELD + Vector3(0, 0.2, 22))
			else:
				msg("Портал не горит. Поговорите с Шампиком.")
		"portal_forest":
			if tools.has("фонарь"):
				teleport(FOREST + Vector3(0, 0.2, 22))
			else:
				msg("Без фонаря в Сумеречный лес не пройти.")
		"portal_home":
			teleport(HOME_SPAWN)
		"mushroom":
			mats["светогриб"] += 1
			set_active(target, false)
			msg("+1 светогриб")
			get_tree().create_timer(45.0).timeout.connect(func(): set_active(target, true))
		"plot":
			build_house(target)
		"door_vip":
			msg("ВИП-комнаты откроются при репутации 5")
		"door_concert":
			msg("Концертный зал откроется при репутации 10")
		"stairs":
			msg("Второй этаж откроется при репутации 15")


func do_cycle(target: Object) -> void:
	var iid := iid_of(target)
	if iid == "stove":
		if stations["stove"]["level"] < 2:
			msg("Улучшите плитку (медная вытяжка), чтобы открыть новые рецепты")
		else:
			var s = stations["stove"]
			s["mode"] = "грибной суп" if s["mode"] == "рагу" else "рагу"
			msg("Плитка готовит: " + s["mode"])
	elif iid == "tools_bench" or iid == "inv_bench":
		bench_index[iid] += 1


func do_attack(target_obj: Object) -> void:
	if attack_cd > 0.0:
		return
	attack_cd = 0.4
	var target = target_obj
	if iid_of(target_obj) == "enemy":
		target.hit()


func teleport(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0


func respawn() -> void:
	teleport(HOME_SPAWN)


func damage(n: int) -> void:
	hp -= n
	if hp <= 0.0:
		hp = 100.0
		money = int(money * 0.75)
		teleport(HOME_SPAWN)
		msg("Вы потеряли сознание и очнулись у таверны. Часть монет пропала.", 6.0)


func enemy_killed(e) -> void:
	if e.drops_gear:
		mats["шестерёнка"] += 1
		msg("+1 шестерёнка")


# ---------------------------------------------------------------- кухня и верстаки

func station_recipe(id: String) -> Array:
	match id:
		"cutting":
			return ["продукты", "нарезка", 1.5]
		"still":
			return ["продукты", "самогон", 5.0]
		"stove":
			if stations["stove"]["mode"] == "грибной суп":
				return ["нарезка", "грибной суп", 7.0]
			return ["нарезка", "рагу", 6.0]
	return []


func use_station(id: String) -> void:
	var s = stations[id]
	if held != "" and DECOR_FOR.get(held, "") == id:
		upgrade(id)
		return
	if s["ready"] != "":
		if held != "":
			msg("Руки заняты")
		else:
			held = s["ready"]
			s["ready"] = ""
		return
	if s["busy"]:
		msg("Ещё готовится...")
		return
	var r := station_recipe(id)
	if held != r[0]:
		msg("Нужно: " + r[0])
		return
	if r[1] == "грибной суп":
		if mats["светогриб"] < 1:
			msg("Для супа нужен светогриб из Сумеречного леса")
			return
		mats["светогриб"] -= 1
	held = ""
	s["busy"] = true
	s["t"] = r[2] / s["level"]
	s["pending"] = r[1]


func upgrade(id: String) -> void:
	var s = stations[id]
	if s["level"] >= 2:
		msg("Уже улучшено")
		return
	s["level"] = 2
	var node: Node3D = station_nodes[id]
	box(node.position + Vector3(0, 1.0, 0.6), Vector3(0.4, 0.4, 0.4), ITEM_COLORS[held], false, "", null, 1.5)
	held = ""
	var label: Label3D = node.get_meta("label")
	label.text = STATION_NAMES[id] + " ур.2"
	match id:
		"stove":
			msg("Плитка улучшена: готовит вдвое быстрее, открыт грибной суп (R — сменить рецепт)", 6.0)
		"still":
			msg("Самогонный аппарат улучшен: гонит вдвое быстрее")
		"tools_bench":
			msg("Верстак инструментов улучшен: открыт молоток")
		"inv_bench":
			msg("Верстак изобретений улучшен: открыта слот-машина")


func bench_recipes(id: String) -> Array:
	var out := []
	for r in RECIPES[id]:
		if recipe_unlocked(id, r):
			out.append(r)
	return out


func recipe_unlocked(id: String, r: Dictionary) -> bool:
	match r["req"]:
		"":
			return true
		"lvl2":
			return stations[id]["level"] >= 2
		"fire":
			return quest_stage >= 3
		"lantern":
			return quest_stage >= 4
	return false


func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append("%s %d" % [k, cost[k]])
	return ", ".join(parts)


func can_pay(cost: Dictionary) -> bool:
	for k in cost:
		if k == "монеты":
			if money < cost[k]:
				return false
		elif mats.get(k, 0) < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost:
		if k == "монеты":
			money -= cost[k]
		else:
			mats[k] -= cost[k]


func current_recipe(id: String):
	var list := bench_recipes(id)
	if list.is_empty():
		return null
	return list[bench_index[id] % list.size()]


func use_bench(id: String) -> void:
	if held != "" and DECOR_FOR.get(held, "") == id:
		upgrade(id)
		return
	var r = current_recipe(id)
	if r == null:
		return
	var n: String = r["name"]
	if r["kind"] == "tool" and tools.has(n):
		msg("Уже есть: " + n)
		return
	if r["kind"] == "held" and held != "":
		msg("Руки заняты")
		return
	if r["kind"] == "build" and flags.has(n):
		msg("Уже построено")
		return
	if not can_pay(r["cost"]):
		msg("Не хватает: " + cost_text(r["cost"]))
		return
	pay(r["cost"])
	match r["kind"]:
		"tool":
			tools[n] = true
			if n == "фонарь":
				quest_stage = maxi(quest_stage, 5)
				player.lantern_light.visible = true
				msg("Фонарь готов! Теперь можно пройти в Сумеречный лес.", 6.0)
				return
		"held":
			held = n
		"build":
			flags[n] = true
			box(Vector3(-6.5, 0.9, 5.0), Vector3(0.9, 1.8, 0.7), Color(0.9, 0.7, 0.2), true, "", null, 0.8)
			label3d("Слот-машина", Vector3(-6.5, 2.1, 5.0))
	msg("Сделано: " + n)


# ---------------------------------------------------------------- гости

func try_spawn_customer() -> void:
	var free := []
	for i in range(seats.size()):
		if seats[i]["active"] and not seats[i]["taken"]:
			free.append(i)
	if free.is_empty():
		return
	var i: int = free.pick_random()
	var s = seats[i]
	s["taken"] = true
	var order := "самогон"
	if s["kind"] == "table":
		order = "рагу"
		if stations["stove"]["level"] >= 2 and randf() < 0.4:
			order = "грибной суп"
	var c = CUSTOMER_SCRIPT.new()
	c.main = self
	c.seat_id = i
	c.order = order
	var path: Array = [DOOR_OUT, DOOR_IN]
	path.append_array(s["via"])
	path.append(s["pos"])
	c.path = path
	c.position = CUSTOMER_SPAWN
	add_child(c)


func leave_path(i: int) -> Array:
	var via: Array = seats[i]["via"].duplicate()
	via.reverse()
	via.append_array([DOOR_IN, DOOR_OUT, CUSTOMER_SPAWN])
	return via


func free_seat(i: int) -> void:
	seats[i]["taken"] = false


func serve(c) -> void:
	if c.state != "wait":
		return
	if held != c.order:
		msg("Гость хочет: " + c.order)
		return
	var mult: float = seats[c.seat_id]["mult"]
	if flags.has("concert"):
		mult *= 1.25
	var tip := int(3.0 * c.patience / c.max_patience)
	var earned := int(PRICES[c.order] * mult) + tip
	money += earned
	held = ""
	rep += 1
	msg("Гость доволен! +%d монет (чаевые %d), репутация +1" % [earned, tip])
	c.leave()
	check_unlocks()


func customer_failed(_c) -> void:
	rep = maxi(0, rep - 1)
	msg("Гость не дождался и ушёл. Репутация -1")


func check_unlocks() -> void:
	if rep >= 5 and not flags.has("vip"):
		flags["vip"] = true
		for d in vip_doors:
			d.queue_free()
		for i in vip_seats:
			seats[i]["active"] = true
		msg("Открыты ВИП-комнаты! Там гости платят вдвое больше.", 6.0)
	if rep >= 10 and not flags.has("concert"):
		flags["concert"] = true
		concert_door.queue_free()
		for i in concert_seats:
			seats[i]["active"] = true
		msg("Открыт концертный зал! Все гости платят на 25% больше.", 6.0)
	if rep >= 15 and not flags.has("rooms"):
		flags["rooms"] = true
		stairs_gate.queue_free()
		build_stairs()
		msg("Открыт второй этаж: гости снимают комнаты, +5 монет каждые 20 секунд.", 6.0)


# ---------------------------------------------------------------- квест и поселение

func talk_shampik() -> void:
	match quest_stage:
		0:
			quest_stage = 1
			set_active(lost_lantern, true)
			msg("Шампик: Ох, путник! Я потерял фонарь в Полях роботов. Я открыл туда портал — найдёшь?", 7.0)
		1:
			msg("Шампик: Фонарь где-то в Полях роботов. Осторожно, роботы кусаются!")
		2:
			if held == "разбитый фонарь":
				held = ""
				quest_stage = 3
				msg("Шампик: Нашёл! Но он разбит... Вот рецепт синего огня — сделай его на верстаке изобретений.", 7.0)
			else:
				msg("Шампик: Принеси мой фонарь!")
		3:
			if held == "синий огонь":
				held = ""
				quest_stage = 4
				shampik_light.visible = true
				msg("Шампик: Он снова светит! В благодарность — сделай себе такой же фонарь. С ним пройдёшь в Сумеречный лес.", 8.0)
			else:
				msg("Шампик: Синий огонь делается на верстаке изобретений в подсобке.")
		4:
			msg("Шампик: Сделай фонарь на верстаке изобретений — и в Сумеречный лес!")
		_:
			msg("Шампик: В лесу растут светогрибы. Из них выходит отличный суп!")


func build_house(plot: Node3D) -> void:
	if not tools.has("молоток"):
		msg("Нужен молоток (верстак инструментов, улучшенный тисками)")
		return
	if money < 40:
		msg("Нужно 40 монет")
		return
	money -= 40
	houses += 1
	var p := plot.position
	set_active(plot, false)
	plot.get_meta("label").queue_free()
	box(p + Vector3(0, 1.2, 0), Vector3(3, 2.4, 3), WOOD)
	var roof := box(p + Vector3(0, 2.6, 0), Vector3(2.4, 2.4, 3.2), Color(0.4, 0.15, 0.1), false)
	roof.rotation_degrees = Vector3(0, 0, 45)
	box(p + Vector3(0, 0.8, 1.51), Vector3(0.8, 1.6, 0.05), DARK_WOOD, false)
	light(p + Vector3(0, 1.8, 2.0), Color(1, 0.7, 0.4), 4.0, 0.8)
	var resident := Node3D.new()
	resident.position = p + Vector3(1.0, 0, 2.3)
	add_child(resident)
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.4
	shape(cm, Vector3(0, 0.7, 0), Color.from_hsv(randf(), 0.4, 0.5), resident)
	shape(sphere(0.22), Vector3(0, 1.55, 0), Color(0.75, 0.65, 0.55), resident)
	label3d("Житель", Vector3(0, 2.1, 0), resident)
	msg("Построен дом! В поселении новый житель, гости приходят чаще.", 6.0)


func hint_for(target_obj: Object) -> String:
	var iid := iid_of(target_obj)
	var target = target_obj
	match iid:
		"pantry":
			return "[E] Взять продукты (1 монета)"
		"cutting", "stove", "still":
			return station_hint(iid)
		"tools_bench", "inv_bench":
			return bench_hint(iid)
		"trash":
			return "[E] Выбросить то, что в руках"
		"customer":
			return "Гость хочет: %s   [E] Отдать" % target.get_meta("ref").order
		"debris":
			return "[E] Расчистить завал (нужна метла)"
		"shampik":
			return "[E] Поговорить с Шампиком"
		"lost_lantern":
			return "[E] Подобрать фонарь"
		"portal_robots":
			return "[E] В Поля роботов"
		"portal_forest":
			return "[E] В Сумеречный лес"
		"portal_home":
			return "[E] Вернуться в таверну"
		"mushroom":
			return "[E] Сорвать светогриб"
		"plot":
			return "[E] Построить дом (молоток + 40 монет)"
		"enemy":
			return "[ЛКМ] Ударить"
		"bar":
			return "Барная стойка"
	return ""


func station_hint(id: String) -> String:
	var s = stations[id]
	var t: String = STATION_NAMES[id] + " ур.%d\n" % s["level"]
	if held != "" and DECOR_FOR.get(held, "") == id:
		return t + "[E] Поставить украшение — улучшить"
	if s["ready"] != "":
		return t + "[E] Забрать: " + s["ready"]
	if s["busy"]:
		return t + "Готовится: %d с" % int(ceil(s["t"]))
	var r := station_recipe(id)
	t += "[E] Положить %s → %s" % [r[0], r[1]]
	if id == "stove":
		t += "   [R] сменить рецепт"
	return t


func bench_hint(id: String) -> String:
	var t: String = STATION_NAMES[id] + " ур.%d\n" % stations[id]["level"]
	if held != "" and DECOR_FOR.get(held, "") == id:
		return t + "[E] Поставить украшение — улучшить"
	var list := bench_recipes(id)
	if list.is_empty():
		return t + "Пока нет рецептов"
	var r = current_recipe(id)
	return t + "[E] Сделать: %s (%s)   [R] следующий (%d/%d)" % [r["name"], cost_text(r["cost"]), bench_index[id] % list.size() + 1, list.size()]
