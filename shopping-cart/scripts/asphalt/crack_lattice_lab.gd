extends Control
## Crack lattice lab (scenes/asphalt/crack_lattice_lab.tscn): the spring-mesh cracking experiment on a 2 x 2 m patch.
## Pick a year and the patch is aged to it (going back starts again from new; ageing takes a while).

@export var sim: CrackLattice
@export var year: HSlider
@export var info: Label


func _ready() -> void:
	year.drag_ended.connect(func(_changed: bool) -> void: _age())
	sim.changed.connect(_show)
	_show()


func _age() -> void:
	info.text = "Ageing to year %d..." % int(year.value)
	await get_tree().process_frame
	await get_tree().process_frame
	sim.advance_to(year.value)


func _show() -> void:
	var s := sim.stats()
	info.text = "Year %.0f\n%d stones, %d springs\n%d springs broken\n%.1f m of crack (%.1f m in the wheel path)" % [
			s.year, s.stones, s.springs, s.broken, s.crack_m, s.wheel_path_m]
