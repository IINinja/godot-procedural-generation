# Generates a dungeon using RigidBody2D physics and Minimum Spanning Tree (MST).
#
# The algorithm works like so:
#
# 1. Spawns and spreads collision shapes around the game world using the physics engine.
# 2. Waits for the rooms to be in a more or less resting state.
# 3. Selects some main rooms for the level based on the average room size.
# 4. Creates a Minimum Spanning Tree graph that connects the rooms.
# 5. Adds back some connections after calculating the MST so the player doesn't need to backtrack.
extends Node2D


signal rooms_placed

const Room := preload("Room.tscn")

export var max_rooms := 60
export var reconnection_factor := 0.025

var _rng := RandomNumberGenerator.new()
var _data := {}
var _path: AStar2D = null
var _sleeping_rooms := 0
var _mean_room_size := Vector2.ZERO
var _draw_extra := []

onready var rooms: Node2D = $Rooms
onready var level: TileMap = $Level


func _ready() -> void:
	_rng.randomize()
	_generate()


func _on_Room_sleeping_state_changed(room: MSTDungeonRoom) -> void:
	room.modulate = Color.yellow
	_sleeping_rooms += 1
	if _sleeping_rooms < max_rooms:
		return

	var main_rooms := []
	var main_rooms_positions := []
	for room in rooms.get_children():
		if _is_main_room(room):
			main_rooms.push_back(room)
			main_rooms_positions.push_back(room.position)
			room.modulate = Color.red

	_path = MSTDungeonUtils.mst(main_rooms_positions)

	update()
	yield(get_tree().create_timer(1), "timeout")

	for point1_id in _path.get_points():
		for point2_id in _path.get_points():
			if (
				point1_id != point2_id
				and not _path.are_points_connected(point1_id, point2_id)
				and _rng.randf() < reconnection_factor
			):
				_path.connect_points(point1_id, point2_id)
				_draw_extra.push_back(
					[_path.get_point_position(point1_id), _path.get_point_position(point2_id)]
				)

	update()

	for room in main_rooms:
		_add_room(room)
	_add_corridors()

	set_process(false)
	emit_signal("rooms_placed")


func _process(delta: float) -> void:
	level.clear()
	for room in rooms.get_children():
		for offset in room:
			level.set_cellv(offset, 0)


func _draw() -> void:
	if _path == null:
		return

	for point1_id in _path.get_points():
		var point1_position := _path.get_point_position(point1_id)
		for point2_id in _path.get_point_connections(point1_id):
			var point2_position := _path.get_point_position(point2_id)
			draw_line(point1_position, point2_position, Color.red, 20)

	if not _draw_extra.empty():
		for pair in _draw_extra:
			draw_line(pair[0], pair[1], Color.green, 20)


func _generate() -> void:
	for _i in range(max_rooms):
		var room := Room.instance()
		room.connect("sleeping_state_changed", self, "_on_Room_sleeping_state_changed", [room])
		room.setup(_rng, level)
		rooms.add_child(room)

		_mean_room_size += room.size
	_mean_room_size /= rooms.get_child_count()

	yield(self, "rooms_placed")

	rooms.queue_free()
	level.clear()
	for point in _data:
		level.set_cellv(point, 0)


func _add_room(room: MSTDungeonRoom) -> void:
	for offset in room:
		_data[offset] = null


func _add_corridors():
	var connected := {}
	for point1_id in _path.get_points():
		for point2_id in _path.get_point_connections(point1_id):
			var point1 := _path.get_point_position(point1_id)
			var point2 := _path.get_point_position(point2_id)
			if Vector2(point1_id, point2_id) in connected:
				continue

			point1 = level.world_to_map(point1)
			point2 = level.world_to_map(point2)
			_add_corridor(point1.x, point2.x, point1.y, Vector2.AXIS_X)
			_add_corridor(point1.y, point2.y, point2.x, Vector2.AXIS_Y)

			connected[Vector2(point1_id, point2_id)] = null
			connected[Vector2(point2_id, point1_id)] = null


func _add_corridor(start: int, end: int, constant: int, axis: int) -> void:
	var t := min(start, end)
	while t <= max(start, end):
		var point := Vector2.ZERO
		match axis:
			Vector2.AXIS_X:
				point = Vector2(t, constant)
			Vector2.AXIS_Y:
				point = Vector2(constant, t)

		t += 1
		for room in rooms.get_children():
			if _is_main_room(room):
				continue

			var top_left: Vector2 = level.world_to_map(room.position) - room.size / 2
			var bottom_right: Vector2 = level.world_to_map(room.position) + room.size / 2
			if (
				top_left.x <= point.x
				and point.x < bottom_right.x
				and top_left.y <= point.y
				and point.y < bottom_right.y
			):
				_add_room(room)
				t = bottom_right[axis]
		_data[point] = null


func _is_main_room(room: MSTDungeonRoom) -> bool:
	return room.size.x > _mean_room_size.x and room.size.y > _mean_room_size.y
