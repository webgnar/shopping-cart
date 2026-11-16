extends SceneTree
## Render-cost breakdown for one level: GPU time, draw calls and triangles, with each expensive feature switched
## off in turn. In the cloud this runs on a software GPU (lavapipe), so trust the draw and triangle counts
## more than the milliseconds. Pass a second argument to print only the baseline.
##   xvfb-run godot -s res://tests/perf_render.gd -- <scene> [quick]

var main: Node3D
var vp: RID


func _initialize() -> void:
	_run.call_deferred()


func _measure(label: String, frames := 12) -> void:
	for i in 3:
		await process_frame
	var gpu := 0.0; var cpu := 0.0; var draws := 0.0; var objs := 0.0; var prims := 0.0
	for i in frames:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("  %-34s gpu %8.1f ms  cpu %6.2f ms  draws %6.0f  objs %5.0f  prims %8.0f" % [label, gpu / frames, cpu / frames, draws / frames, objs / frames, prims / frames])


func _run() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	main = load(path).instantiate()
	root.add_child(main)
	for i in 30:
		await physics_frame
	print(path, "  ", root.size)
	await _measure("baseline")
	if OS.get_cmdline_user_args().size() > 1:
		quit()
		return
	var env: Environment = (main.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	env.ssao_enabled = false
	await _measure("- ssao")
	env.glow_enabled = false
	await _measure("- ssao - glow")
	env.ssao_enabled = true; env.glow_enabled = true
	var lights := main.find_children("*", "Light3D", true, false)
	var dir := lights.filter(func(l): return l is DirectionalLight3D and l.shadow_enabled)
	for l in dir: l.shadow_enabled = false
	await _measure("- sun shadow (%d)" % dir.size())
	for l in dir: l.shadow_enabled = true
	var pos := lights.filter(func(l): return not (l is DirectionalLight3D) and l.shadow_enabled)
	for l in pos: l.shadow_enabled = false
	await _measure("- spot/omni shadows (%d)" % pos.size())
	for l in pos: l.shadow_enabled = true
	var local := lights.filter(func(l): return not (l is DirectionalLight3D) and l.visible)
	for l in local: l.visible = false
	await _measure("- all local lights (%d)" % local.size())
	for l in local: l.visible = true
	root.scaling_3d_scale = 0.5
	await _measure("3D scale 0.5")
	quit()
