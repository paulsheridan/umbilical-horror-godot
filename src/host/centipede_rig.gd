class_name CentipedeRig
extends RefCounted
## Procedurally-built house-centipede body rig, one node tree per host.
##
## The rig is pure presentation: `build()` creates every node under a single
## `Rig` child of the owning body, `update()` poses the trunk, antennae and 30
## legs, and nothing here ever writes to the owner's state. The owner keeps its
## yaw-only CharacterBody3D rotation while `Rig` carries the full surface
## orientation, so the same body walks floors, walls and ceilings.
##
## Usage:
##   var rig := CentipedeRig.new()
##   rig.build(self)                       # once, in the owner's _ready()
##   # every physics tick:
##   rig.update(delta, up, rotation.y, velocity,
##           get_world_3d().direct_space_state,
##           clearance, fold, hunt, strike)

const PAIRS := 15
const SEGMENTS := 15

## THE SIZE DIAL. Every authored dimension in this rig is written against a
## 1.0-scale body and multiplied by this, so growing the monster is one number.
## Angles, phase frequencies and gait timing are dimensionless and stay as-is.
const BODY_SCALE := 1.5

## Trunk geometry, in Rig-local space. Authored at 1.0 scale and grown here, so
## the build code below never repeats the factor.
const SEG_Z0 := -0.83 * BODY_SCALE
const SEG_STEP := 0.115 * BODY_SCALE
const HEAD_POS := Vector3(0.0, 0.02, -1.02) * BODY_SCALE

## A fixed seed keeps every build identical, so the per-leg step jitter is
## authored once and the body always reads the same.
const JITTER_SEED := 0x5EEDC3A1

## Femur elevation a planted foreleg rests at (radians) and the gain that turns
## a solved leg into the signed pitch reported by `foreleg_pitch()`.
const REST_ELEV := 0.47
const PITCH_GAIN := 4.0

## One leg of the rig. All joint nodes are pre-built; the gait and IK only ever
## write rotations and the planted-foot bookkeeping kept here.
class Leg extends RefCounted:
	var pair := 0
	var side := 1
	var seg: Node3D
	var coxa: Node3D
	var femur: Node3D
	var tibia: Node3D
	var l1 := 0.0
	var l2 := 0.0
	var s := 1.0
	var anchor := Vector3.ZERO
	var planted := Vector3.ZERO
	var has_planted := false
	var swing_t := -1.0
	var swing_from := Vector3.ZERO
	var swing_to := Vector3.ZERO
	var swing_dur := 0.2
	var step_jitter := 1.0
	## World point of the solved knee, refreshed by `_solve_leg`.
	var knee := Vector3.ZERO
	## Femur elevation above the surface, refreshed by `_solve_leg`.
	var elev := 0.0

var root: Node3D
var head: Node3D
var eye_l: CSGSphere3D
var eye_r: CSGSphere3D
var mandible_l: Node3D
var mandible_r: Node3D
var segs: Array = []
var legs: Array = []
## 0..1 smoothed creepy raised-foreleg weight.
var hunt_pose := 0.0
## Surface-up used for foot math, smoothed with the rig orientation.
var up_smooth := Vector3.UP

var _seg_base: Array = []
var _antennae: Array = []
var _phase := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


# ---- Build ----

## Create the whole rig under `parent`. Deterministic and safe to call once.
func build(parent: Node3D) -> void:
	if parent == null or root != null:
		return
	_rng.seed = JITTER_SEED
	root = Node3D.new()
	root.name = "Rig"
	parent.add_child(root)
	_build_head()
	_build_trunk()
	_build_tail()
	_build_legs()
	up_smooth = Vector3.UP


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_POS
	root.add_child(head)

	var plate := _box(head, Vector3(0.26, 0.12, 0.30) * BODY_SCALE,
			Vector3(0.0, 0.0, -0.02) * BODY_SCALE, Mats.bone())
	plate.name = "Plate"

	mandible_l = _pivot(head, "MandibleL",
			Vector3(-0.07, -0.02, -0.16) * BODY_SCALE)
	mandible_r = _pivot(head, "MandibleR",
			Vector3(0.07, -0.02, -0.16) * BODY_SCALE)
	for pivot: Node3D in [mandible_l, mandible_r]:
		var jaw := _cone(pivot, 0.02 * BODY_SCALE, 0.22 * BODY_SCALE,
				Mats.cable(), -PI * 0.5 - 0.45)
		jaw.name = "Jaw"

	eye_l = _sphere(head, 0.045 * BODY_SCALE,
			Vector3(-0.09, 0.05, -0.10) * BODY_SCALE, Mats.amber())
	eye_l.name = "EyeL"
	eye_r = _sphere(head, 0.045 * BODY_SCALE,
			Vector3(0.09, 0.05, -0.10) * BODY_SCALE, Mats.amber())
	eye_r.name = "EyeR"

	var ant_l := _build_antenna(-1.0, "AntL")
	var ant_r := _build_antenna(1.0, "AntR")
	_antennae = [ant_l, ant_r]


func _build_antenna(side: float, node_name: String) -> Array:
	var base := Node3D.new()
	base.name = node_name
	base.position = Vector3(side * 0.05, 0.04, -0.14) * BODY_SCALE
	base.rotation = Vector3(0.45, side * 0.35, 0.0)
	head.add_child(base)

	var lengths := [0.22 * BODY_SCALE, 0.20 * BODY_SCALE, 0.18 * BODY_SCALE]
	var joints: Array = [base]
	var cur := base
	for i in 3:
		var seg_len: float = lengths[i]
		_rod(cur, 0.008 * BODY_SCALE, seg_len, Mats.cable())
		if i < 2:
			var joint := Node3D.new()
			joint.name = "Joint%d" % i
			joint.position = Vector3(0.0, 0.0, -seg_len)
			cur.add_child(joint)
			joints.append(joint)
			cur = joint
	return joints


func _build_trunk() -> void:
	segs.clear()
	_seg_base.clear()
	for j in SEGMENTS:
		var seg := Node3D.new()
		seg.name = "Seg%d" % j
		var base := Vector3(0.0, 0.0, SEG_Z0 + float(j) * SEG_STEP)
		seg.position = base
		root.add_child(seg)
		segs.append(seg)
		_seg_base.append(base)

		var width := 0.26 - float(j) * 0.004
		var plate := _box(seg,
				Vector3(width, 0.09, 0.115) * BODY_SCALE,
				Vector3(0.0, 0.03, 0.0) * BODY_SCALE, Mats.bone())
		plate.name = "Plate"
		var sternite := _box(seg,
				Vector3(0.16, 0.05, 0.10) * BODY_SCALE,
				Vector3(0.0, -0.03, 0.0) * BODY_SCALE, Mats.shadow())
		sternite.name = "Sternite"


func _build_tail() -> void:
	var tail := Node3D.new()
	tail.name = "Tail"
	root.add_child(tail)
	for side: float in [-1.0, 1.0]:
		var pivot := _pivot(tail, "Cercus%s" % ("L" if side < 0.0 else "R"),
				Vector3(side * 0.05, 0.02, 0.88) * BODY_SCALE)
		var cercus := _cone(pivot, 0.02 * BODY_SCALE, 0.24 * BODY_SCALE,
				Mats.cable(), PI * 0.5 - 0.35)
		cercus.name = "CercusMesh"


func _build_legs() -> void:
	legs.clear()
	for j in PAIRS:
		for side: int in [-1, 1]:
			legs.append(_build_leg(j, side))


func _build_leg(j: int, side: int) -> Leg:
	var leg := Leg.new()
	leg.pair = j
	leg.side = side
	leg.seg = segs[j]
	leg.s = (0.72 + 0.05 * float(j)) * BODY_SCALE
	leg.l1 = 0.34 * leg.s
	leg.l2 = 0.50 * leg.s
	leg.anchor = Vector3(float(side) * 0.11, 0.01, 0.0) * BODY_SCALE
	leg.step_jitter = _rng.randf_range(0.85, 1.15)

	var tag := "%s%d" % ["L" if side < 0 else "R", j]
	var coxa := _pivot(leg.seg, "Coxa" + tag, leg.anchor)
	leg.coxa = coxa

	var femur := Node3D.new()
	femur.name = "Femur"
	coxa.add_child(femur)
	leg.femur = femur

	# Pale chitin, not `shadow`. The legs are most of the body's visible
	# surface, and `shadow` is the palette's "almost invisible mass" material:
	# built from it the whole monster vanished in a dark room, where the old
	# pale-boned body read at a glance. Long-legged house centipedes are pale
	# and striped anyway, so bone is also the truer anatomy.
	var radius := maxf(0.024 - float(j) * 0.0006, 0.016) * BODY_SCALE
	var shaft := _cylinder(femur, radius, leg.l1, 5, Mats.bone())
	shaft.name = "FemurMesh"
	var shin_y := -leg.l1 * 0.5
	shaft.position = Vector3(0.0, shin_y, 0.0)
	shaft.rotation = Vector3.ZERO

	var knee := _sphere(femur, 0.03 * BODY_SCALE,
			Vector3(0.0, -leg.l1, 0.0), Mats.bone())
	knee.name = "Knee"

	var tibia := _pivot(femur, "Tibia" + tag, Vector3(0.0, -leg.l1, 0.0))
	leg.tibia = tibia
	var shin_len := leg.l2 - 0.12 * BODY_SCALE
	var shin := _cylinder(tibia, 0.018 * BODY_SCALE, shin_len, 5, Mats.bone())
	shin.name = "TibiaMesh"
	shin.position = Vector3(0.0, -shin_len * 0.5, 0.0)

	var claw := _cone(tibia, 0.012 * BODY_SCALE, 0.12 * BODY_SCALE,
			Mats.cable(), PI)
	claw.name = "Claw"
	claw.position = Vector3(0.0, -(leg.l2 - 0.06 * BODY_SCALE), 0.0)
	return leg


# ---- Primitive helpers ----

func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	parent.add_child(node)
	return node


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = size
	box.position = pos
	box.material = mat
	box.use_collision = false
	parent.add_child(box)
	return box


func _cylinder(parent: Node3D, radius: float, height: float, sides: int,
		mat: Material) -> CSGCylinder3D:
	var cyl := CSGCylinder3D.new()
	cyl.radius = radius
	cyl.height = height
	cyl.sides = sides
	cyl.material = mat
	cyl.use_collision = false
	parent.add_child(cyl)
	return cyl


## A cone whose tip points along its own +Y, rotated by `pitch` about X so it
## aims where the pose wants it (0 = up, -PI/2 = forward, PI/2 = back).
func _cone(parent: Node3D, radius: float, height: float, mat: Material,
		pitch: float) -> CSGCylinder3D:
	var cone := _cylinder(parent, radius, height, 6, mat)
	cone.cone = true
	cone.rotation = Vector3(pitch, 0.0, 0.0)
	cone.position = Vector3(0.0, cos(pitch) * height * 0.5, sin(pitch) * height * 0.5)
	return cone


## A thin rod laid along local -Z, starting at the parent's origin.
func _rod(parent: Node3D, radius: float, length: float, mat: Material) -> CSGCylinder3D:
	var rod := _cylinder(parent, radius, length, 5, mat)
	rod.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	rod.position = Vector3(0.0, 0.0, -length * 0.5)
	return rod


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> CSGSphere3D:
	var ball := CSGSphere3D.new()
	ball.radius = radius
	ball.radial_segments = 6
	ball.rings = 4
	ball.position = pos
	ball.material = mat
	ball.use_collision = false
	parent.add_child(ball)
	return ball


# ---- Public API ----

## Total leg count: 15 pairs, left before right.
func leg_count() -> int:
	return legs.size()


## Pose both eyes together, for the owner's presence/dilation logic.
func set_eyes(scale: float) -> void:
	if eye_l != null:
		eye_l.scale = Vector3.ONE * scale
	if eye_r != null:
		eye_r.scale = Vector3.ONE * scale


## World position of one foot tip, read straight from the solved joints.
func foot_global(leg_idx: int) -> Vector3:
	if leg_idx < 0 or leg_idx >= legs.size():
		return Vector3.ZERO
	var leg := legs[leg_idx] as Leg
	return leg.tibia.global_transform * Vector3(0.0, -leg.l2, 0.0)


## Test hook: solve one leg toward a world target immediately.
func leg_reach(leg_idx: int, target: Vector3) -> void:
	if leg_idx < 0 or leg_idx >= legs.size():
		return
	_solve_leg(legs[leg_idx] as Leg, target)


## Signed sagittal pitch of the forelegs in radians: about zero when the legs
## stand at their planted attitude, negative as they rear up. Measured from the
## solved femur direction rather than the raw joint angle, which flips sign as
## the knee folds back over the hip on a close, high target.
func foreleg_pitch() -> float:
	if legs.size() < 4:
		return 0.0
	var total := 0.0
	for i in 4:
		total += (legs[i] as Leg).elev
	return clampf((REST_ELEV - total / 4.0) * PITCH_GAIN, -PI * 0.5, PI * 0.5)


# ---- Per-tick update ----

## Pose the rig for this tick. `space` may be null to skip ground raycasts.
func update(dt: float, up: Vector3, yaw: float, vel: Vector3,
		space: PhysicsDirectSpaceState3D, clearance: float, fold: float,
		hunt: float, strike: float) -> void:
	if root == null:
		return
	if dt <= 0.0:
		dt = 0.0
	_time += dt

	# ---- Orientation: yaw-only body, surface frame lives on the rig ----
	var u := Vector3.UP
	if up.length_squared() > 0.000001:
		u = up.normalized()
	var fwd_body := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var flat := fwd_body - u * fwd_body.dot(u)
	if flat.length_squared() < 0.000001:
		flat = -root.global_basis.z
	if flat.length_squared() < 0.000001:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()

	var z_axis := -flat
	var target_basis := Basis(u.cross(z_axis).normalized(), u, z_axis)
	var gt := root.global_transform
	var from_q := gt.basis.get_rotation_quaternion()
	var to_q := target_basis.get_rotation_quaternion()
	var w := 1.0 - exp(-9.0 * dt)
	gt.basis = Basis(from_q.slerp(to_q, w)).orthonormalized()
	root.global_transform = gt
	up_smooth = root.global_basis.y.normalized()

	# ---- Pose weights ----
	hunt_pose = lerpf(hunt_pose, clampf(hunt, 0.0, 1.0), 1.0 - exp(-6.0 * dt))
	var fold_k := 1.0 - clampf(fold, 0.0, 1.0)

	# ---- Undulation ----
	var spd := clampf(vel.length() / 3.0, 0.0, 1.0)
	_phase += dt * (2.0 + 6.0 * spd) * fold_k
	for j in segs.size():
		var seg := segs[j] as Node3D
		var base: Vector3 = _seg_base[j]
		seg.position.y = base.y + sin(_phase - float(j) * 0.5) \
				* (0.02 + 0.05 * spd) * BODY_SCALE * fold_k
		seg.position.x = base.x + sin(_phase - float(j) * 0.5 + PI * 0.5) \
				* 0.025 * BODY_SCALE * spd * fold_k
		seg.position.z = base.z * (1.0 - 0.12 * fold)

	# ---- Head sway, antennae, mandibles, eyes ----
	var sway := (0.01 + 0.025 * spd) * BODY_SCALE * fold_k
	head.position = Vector3(
			HEAD_POS.x + sin(_phase + PI * 0.5) * 0.0125 * BODY_SCALE * spd * fold_k,
			HEAD_POS.y + sin(_phase) * sway + 0.05 * BODY_SCALE * strike \
					+ 0.03 * BODY_SCALE * hunt_pose,
			HEAD_POS.z * (1.0 - 0.12 * fold))

	var aggro := maxf(clampf(hunt, 0.0, 1.0), clampf(strike, 0.0, 1.0))
	var freq := lerpf(1.5, 8.0, aggro) * TAU
	var amp := lerpf(0.12, 0.30, aggro)
	for a in _antennae.size():
		var joints := _antennae[a] as Array
		var side := -1.0 if a == 0 else 1.0
		var ph := _time * freq + float(a) * 1.7
		var base_pivot := joints[0] as Node3D
		base_pivot.rotation = Vector3(
				0.45 + sin(ph) * amp,
				side * 0.35 + sin(ph * 0.6) * amp * 0.3,
				sin(ph * 0.8 + 0.7) * amp * 0.5)
		for k in range(1, joints.size()):
			var joint := joints[k] as Node3D
			joint.rotation = Vector3(
					sin(ph * (1.0 + 0.35 * float(k)) + float(k) * 0.9) * amp * 0.7,
					0.0,
					sin(ph * (1.0 + 0.25 * float(k)) + float(k) * 1.4) * amp * 0.4)

	if mandible_l != null:
		mandible_l.rotation.y = 0.5 * clampf(strike, 0.0, 1.0)
	if mandible_r != null:
		mandible_r.rotation.y = -0.5 * clampf(strike, 0.0, 1.0)

	# ---- Legs: homes, gait, IK ----
	var swinging := [0, 0]
	for leg_in in legs:
		var leg := leg_in as Leg
		if leg.swing_t >= 0.0:
			swinging[0 if leg.side < 0 else 1] += 1

	for i in legs.size():
		var leg := legs[i] as Leg
		_step_leg(leg, dt, vel, space, up_smooth, clearance, fold, hunt, strike,
				fwd_body, swinging)


func _step_leg(leg: Leg, dt: float, vel: Vector3,
		space: PhysicsDirectSpaceState3D, up: Vector3, clearance: float,
		fold: float, hunt: float, strike: float, fwd_body: Vector3,
		swinging: Array) -> void:
	var side_w := root.global_basis.x.normalized() * float(leg.side)
	var anchor_w := leg.seg.global_transform * leg.anchor
	var spread := 0.42 * leg.s * (1.0 - 0.55 * fold)
	var lead := vel * 0.14
	if lead.length() > 0.6 * BODY_SCALE:
		lead = lead.normalized() * 0.6 * BODY_SCALE
	var home := anchor_w + side_w * spread + lead - up * clearance

	# Pose overrides: rearing graspers, then the quieter hunt lift. These drive
	# the IK directly so a still body still reads the pose (the legs are lifted
	# off the surface, not waiting for a step).
	var posed := false
	if strike > 0.3 and leg.pair < 2:
		var wob := Vector3(sin(_time * 7.0 + float(leg.pair)), 0.0,
				cos(_time * 7.0 + float(leg.pair))) * 0.05 * BODY_SCALE
		home = anchor_w + fwd_body * (0.45 * leg.s * strike) \
				+ up * (0.50 * leg.s * strike) + side_w * 0.06 * BODY_SCALE + wob
		posed = true
	elif hunt > 0.3 and leg.pair < 3:
		home += up * (0.10 * hunt) * BODY_SCALE \
				+ fwd_body * (0.06 * hunt) * BODY_SCALE
		posed = true

	if posed:
		if leg.swing_t >= 0.0:
			swinging[0 if leg.side < 0 else 1] -= 1
			leg.swing_t = -1.0
			leg.has_planted = false
		_solve_leg(leg, home)
		return

	var thresh := (0.26 + vel.length() * 0.10) * leg.s * leg.step_jitter \
			* (1.0 - 0.4 * fold)

	if leg.swing_t < 0.0:
		if not leg.has_planted:
			_begin_swing(leg, home, vel, 0.08)
			swinging[0 if leg.side < 0 else 1] += 1
		elif leg.planted.distance_to(home) > thresh and _gait_open(leg, swinging):
			_begin_swing(leg, home, vel)
			swinging[0 if leg.side < 0 else 1] += 1

	var target := home
	if leg.swing_t >= 0.0:
		leg.swing_t += dt / maxf(leg.swing_dur, 0.0001)
		var t := clampf(leg.swing_t, 0.0, 1.0)
		target = leg.swing_from.lerp(leg.swing_to, smoothstep(0.0, 1.0, t)) \
				+ up * (sin(PI * t) * (0.09 + vel.length() * 0.05) * BODY_SCALE)
		if leg.swing_t >= 1.0:
			target = _plant(leg, space, up, anchor_w)
			swinging[0 if leg.side < 0 else 1] -= 1
	elif leg.has_planted:
		target = leg.planted

	_solve_leg(leg, target)


## Lift a leg. `dur_override <= 0` uses the speed-derived swing time.
func _begin_swing(leg: Leg, home: Vector3, vel: Vector3,
		dur_override := -1.0) -> void:
	leg.swing_from = leg.planted if leg.has_planted else home
	leg.has_planted = false
	leg.swing_to = home + vel * clampf(leg.swing_dur, 0.0, 0.3) * 0.5
	if dur_override > 0.0:
		leg.swing_dur = dur_override
	else:
		leg.swing_dur = clampf(0.22 - vel.length() * 0.02, 0.10, 0.26)
	leg.swing_t = 0.0


## True when the gait gates allow this leg to lift: same-side neighbours planted
## and fewer than five legs already swinging on its side.
func _gait_open(leg: Leg, swinging: Array) -> bool:
	if swinging[0 if leg.side < 0 else 1] >= 5:
		return false
	for d: int in [-1, 1]:
		var p: int = leg.pair + d
		if p < 0 or p >= PAIRS:
			continue
		var nb := legs[p * 2 + (0 if leg.side < 0 else 1)] as Leg
		if not nb.has_planted:
			return false
	return true


## Land a swinging leg, planting it on the surface if a space is supplied. The
## probe starts well above the aim point and reaches deep: clinging high off a
## wall puts a foot's home most of a metre off the face, so a short ray would
## stop short and never plant. The first hit is still the nearest surface (wall
## face or deck), so floors behave exactly as before.
func _plant(leg: Leg, space: PhysicsDirectSpaceState3D, up: Vector3,
		anchor_w: Vector3) -> Vector3:
	var land := leg.swing_to
	if space != null:
		var from := leg.swing_to + up * (0.8 * BODY_SCALE)
		var query := PhysicsRayQueryParameters3D.create(from,
				from - up * (1.6 * BODY_SCALE), 1)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			land = hit["position"]

	# Both ends of this test are world metres. `leg.l1`/`leg.l2` are already
	# authored * BODY_SCALE (through `leg.s`) and the rig carries no node
	# scale, so the budget needs no second factor: adding one here would let
	# the gait plant unreachable points and float the feet off the surface.
	var full := leg.l1 + leg.l2
	if anchor_w.distance_to(land) > 0.97 * full:
		var dir := (land - anchor_w).normalized()
		if dir.length_squared() < 0.000001:
			dir = -up
		land = anchor_w + dir * 0.96 * full

	leg.planted = land
	leg.has_planted = true
	leg.swing_t = -1.0
	return leg.planted


# ---- IK ----

## Two-bone analytic solve: aims the coxa at `target_world`, folds the knee up
## and points the tibia at the target. All joint rotations are absolute.
func _solve_leg(leg: Leg, target_world: Vector3) -> void:
	var xf := leg.seg.global_transform.affine_inverse()
	var d := (xf * target_world) - leg.anchor

	var yaw := float(leg.side) * 1.5708
	if Vector2(d.x, d.z).length() > 0.0001:
		yaw = atan2(-d.x, -d.z)
	leg.coxa.rotation = Vector3(0.0, yaw, 0.0)

	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var a := d.dot(fwd)
	var b := d.y
	var reach := sqrt(a * a + b * b)
	var full := leg.l1 + leg.l2
	var r := clampf(reach, 0.22 * full, 0.995 * full)
	var sc := r / maxf(reach, 0.0001)
	a *= sc
	b *= sc

	var cos_alpha := clampf((leg.l1 * leg.l1 + r * r - leg.l2 * leg.l2)
			/ (2.0 * leg.l1 * r), -1.0, 1.0)
	var alpha := acos(cos_alpha)

	var t := Vector2(a / r, b / r)
	var n := Vector2(-t.y, t.x).normalized()
	var k := t * cos_alpha + n * sin(alpha)

	leg.femur.rotation.x = atan2(k.x, -k.y)
	leg.elev = atan2(k.y, k.x)

	var hip := leg.seg.global_transform * leg.anchor
	# `fwd` and UP are unit axes and `leg.l1` already carries BODY_SCALE, so the
	# knee is a true world point with no extra factor.
	leg.knee = hip + (fwd * k.x + Vector3.UP * k.y) * leg.l1

	var m := leg.femur.global_transform.affine_inverse() * target_world
	var to_target := m - Vector3(0.0, -leg.l1, 0.0)
	if to_target.length_squared() > 0.000001:
		leg.tibia.rotation.x = atan2(-to_target.z, -to_target.y)
