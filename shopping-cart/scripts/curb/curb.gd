@tool
class_name Curb
extends Path3D
## A cast-in-place concrete curb swept along this Path3D's curve (scenes/curb/curb.tscn), to the "Type C Doweled"
## drawing in References/Props/type_c_doweled_curb.png. The curve is the curb line (the front top edge, where the
## face starts) at ground level. The street is on the right of the curve's direction, so wind an island's loop so
## its right side faces out. Bends follow the curve; use curve_through() to round the corners of a polyline. An
## open curve gets square ends, a closed one (curve.closed) joins up. Keep bends wider than the curb (about 0.2 m)
## where the back is on the inside. Mesh and collision are rebuilt whenever the
## curve changes, in the editor too.
##
## For a parking lot generator: instance curb.tscn, set `curve = Curb.curve_through(points, radius, closed)`.

const IN := 0.0254
## The drawing, in inches. Profile x is across the curb (+ toward the street, 0 at the curb line), y is up.
const TOP_WIDTH := 6.0 * IN          ## back face to curb line
const HEIGHT := 6.0 * IN             ## at the curb line
const TOP_RISE := 0.25 * IN          ## the back of the top stands 1/4" higher, so the top drains to the street
const BATTER := 1.5 / 12.0           ## the face leans back 1 1/2" per foot
const BACK_RADIUS := 0.25 * IN
const FRONT_RADIUS := 0.75 * IN
const BACK_SEGMENTS := 3
const FRONT_SEGMENTS := 5
const SMOOTH_DEG := 35.0             ## profile corners sharper than this get hard edges
const TESSELLATE_DEG := 3.0          ## how finely bends are followed

@export var mesh_instance: MeshInstance3D    ## its mesh is an ArrayMesh (local to scene), filled here
@export var collision: CollisionShape3D      ## a ConcavePolygonShape3D (local to scene), filled here

var _queued := false


func _ready() -> void:
	curve_changed.connect(_queue_build)
	build()


## The curb's cross-section, counter-clockwise from the back of the base, with both top corners rounded.
static func profile() -> PackedVector2Array:
	var back_bottom := Vector2(-TOP_WIDTH, 0.0)
	var front_bottom := Vector2(HEIGHT * BATTER, 0.0)
	var front_top := Vector2(0.0, HEIGHT)
	var back_top := Vector2(-TOP_WIDTH, HEIGHT + TOP_RISE)
	var p := PackedVector2Array([back_bottom, front_bottom])
	p.append_array(_fillet(front_bottom, front_top, back_top, FRONT_RADIUS, FRONT_SEGMENTS))
	p.append_array(_fillet(front_top, back_top, back_bottom, BACK_RADIUS, BACK_SEGMENTS))
	return p


## A Curve3D through `points` with each corner rounded to `corner_radius` (a circular arc as a Bézier, shrunk where
## the legs are too short). With `closed`, the last point joins back to the first and that corner is rounded too.
static func curve_through(points: PackedVector3Array, corner_radius := 1.0, closed := false) -> Curve3D:
	var c := Curve3D.new()
	c.closed = closed
	var n := points.size()
	for i in n:
		var p := points[i]
		if not closed and (i == 0 or i == n - 1):
			c.add_point(p)
			continue
		var prev := points[(i - 1 + n) % n]
		var next := points[(i + 1) % n]
		var a := (p - prev).normalized()
		var b := (next - p).normalized()
		var turn := a.angle_to(b)
		if turn < 0.001:
			c.add_point(p)
			continue
		# Tangent length for the radius, at most half of each leg so neighbouring corners don't overlap.
		var d := minf(corner_radius * tan(turn * 0.5), minf(p.distance_to(prev), p.distance_to(next)) * 0.5)
		var r := d / tan(turn * 0.5)
		var k := 4.0 / 3.0 * tan(turn * 0.25) * r   # Bézier handle that best fits a circular arc
		c.add_point(p - a * d, Vector3.ZERO, a * k)
		c.add_point(p + b * d, -b * k, Vector3.ZERO)
	return c


## Rebuilds the mesh and collision from the curve now (it also happens by itself, once a frame, as the curve changes).
func build() -> void:
	_queued = false
	var mesh := mesh_instance.mesh as ArrayMesh
	var shape := collision.shape as ConcavePolygonShape3D
	mesh.clear_surfaces()
	shape.set_faces(PackedVector3Array())
	if curve == null or curve.point_count < 2:
		return
	var path := curve.tessellate(5, TESSELLATE_DEG)
	if curve.closed and path.size() > 2 and path[0].is_equal_approx(path[path.size() - 1]):
		path.resize(path.size() - 1)
	if path.size() < 2:
		return
	var sweep := _Sweep.new(profile())
	sweep.run(path, curve.closed)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sweep.verts
	arrays[Mesh.ARRAY_NORMAL] = sweep.normals
	arrays[Mesh.ARRAY_TEX_UV] = sweep.uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	shape.set_faces(sweep.verts)


func _queue_build() -> void:
	if not _queued:
		_queued = true
		build.call_deferred()


## The arc rounding corner `c` (between the edges from `a` and to `b`) with radius `r`, from the a side to the b side.
static func _fillet(a: Vector2, c: Vector2, b: Vector2, r: float, segs: int) -> PackedVector2Array:
	var u := (a - c).normalized()
	var v := (b - c).normalized()
	var half := u.angle_to(v) * 0.5
	var centre := c + (u + v).normalized() * r / sin(absf(half))
	var t1 := c + u * r / tan(absf(half))
	var t2 := c + v * r / tan(absf(half))
	var a1 := (t1 - centre).angle()
	var sweep := wrapf((t2 - centre).angle() - a1, -PI, PI)
	var out := PackedVector2Array()
	for i in segs + 1:
		out.append(centre + Vector2.from_angle(a1 + sweep * i / segs) * r)
	return out


## Sweeps a closed 2D profile along a polyline, keeping it upright, with mitred bends and capped open ends.
## The profile's first edge (the base) is left out: it sits on the ground.
class _Sweep:
	var prof: PackedVector2Array
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var _edge_n: Array[Vector2] = []       # outward normal of profile edge i (from point i to i + 1)
	var _vert_n: Array[Array] = []         # [normal at the edge's start, at its end], smoothed across soft corners
	var _v: Array[float] = []              # distance around the profile, for UVs

	func _init(p: PackedVector2Array) -> void:
		prof = p
		var n := p.size()
		for i in n:
			var e := p[(i + 1) % n] - p[i]
			_edge_n.append(Vector2(e.y, -e.x).normalized())
		var acc := 0.0
		for i in n:
			_v.append(acc)
			acc += p[i].distance_to(p[(i + 1) % n])
		var cos_soft := cos(deg_to_rad(SMOOTH_DEG))
		for i in n:
			var prev := _edge_n[(i - 1 + n) % n]
			var next := _edge_n[(i + 1) % n]
			var me := _edge_n[i]
			_vert_n.append([(me + prev).normalized() if me.dot(prev) > cos_soft else me,
					(me + next).normalized() if me.dot(next) > cos_soft else me])

	func run(path: PackedVector3Array, closed: bool) -> void:
		var m := path.size()
		var rights: Array[Vector3] = []       # the profile's +x at each path point, mitre-scaled
		var along: Array[float] = []
		var dist := 0.0
		for j in m:
			var t_in := _flat(path[j] - path[(j - 1 + m) % m]) if (j > 0 or closed) else Vector3.ZERO
			var t_out := _flat(path[(j + 1) % m] - path[j]) if (j < m - 1 or closed) else Vector3.ZERO
			if t_in == Vector3.ZERO:
				t_in = t_out
			if t_out == Vector3.ZERO:
				t_out = t_in
			var r_in := t_in.cross(Vector3.UP)
			var r_out := t_out.cross(Vector3.UP)
			var r := (r_in + r_out).normalized()
			if r == Vector3.ZERO:
				r = r_out
			rights.append(r / maxf(r.dot(r_in), 0.25))
			if j > 0:
				dist += path[j].distance_to(path[j - 1])
			along.append(dist)
		var segs := m if closed else m - 1
		for j in segs:
			var k := (j + 1) % m
			var u1 := along[j]
			var u2 := along[j] + path[j].distance_to(path[k])
			for i in range(1, prof.size()):   # skip edge 0, the base
				var i2 := (i + 1) % prof.size()
				var a := _at(path[j], rights[j], prof[i])
				var b := _at(path[k], rights[k], prof[i])
				var c := _at(path[k], rights[k], prof[i2])
				var d := _at(path[j], rights[j], prof[i2])
				var na := _n3(rights[j], _vert_n[i][0])
				var nb := _n3(rights[k], _vert_n[i][0])
				var nc := _n3(rights[k], _vert_n[i][1])
				var nd := _n3(rights[j], _vert_n[i][1])
				var v1 := _v[i]
				var v2 := _v[i] + prof[i].distance_to(prof[i2])
				_tri([a, b, c], [na, nb, nc], [Vector2(u1, v1), Vector2(u2, v1), Vector2(u2, v2)])
				_tri([a, c, d], [na, nc, nd], [Vector2(u1, v1), Vector2(u2, v2), Vector2(u1, v2)])
		if not closed:
			_cap(path[0], rights[0], -_flat(path[1] - path[0]))
			_cap(path[m - 1], rights[m - 1], _flat(path[m - 1] - path[m - 2]))

	func _cap(at: Vector3, right: Vector3, n: Vector3) -> void:
		var idx := Geometry2D.triangulate_polygon(prof)
		for t in range(0, idx.size(), 3):
			var p := [prof[idx[t]], prof[idx[t + 1]], prof[idx[t + 2]]]
			_tri([_at(at, right, p[0]), _at(at, right, p[1]), _at(at, right, p[2])], [n, n, n],
					[p[0], p[1], p[2]])

	# Adds a triangle, wound so its front faces along the normals (Godot's front faces are clockwise).
	func _tri(p: Array, n: Array, uv: Array) -> void:
		var order := [0, 1, 2]
		if (p[1] - p[0]).cross(p[2] - p[0]).dot(n[0] + n[1] + n[2]) > 0.0:
			order = [0, 2, 1]
		for o: int in order:
			verts.append(p[o])
			normals.append(n[o])
			uvs.append(uv[o])

	static func _at(origin: Vector3, right: Vector3, q: Vector2) -> Vector3:
		return origin + right * q.x + Vector3.UP * q.y

	static func _n3(right: Vector3, n: Vector2) -> Vector3:
		return (right.normalized() * n.x + Vector3.UP * n.y).normalized()

	static func _flat(v: Vector3) -> Vector3:
		return Vector3(v.x, 0.0, v.z).normalized()
