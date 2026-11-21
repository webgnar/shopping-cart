class_name RaceHUD
extends CanvasLayer
## The race's screen: the 3, 2, 1, GO! countdown in the middle, the race clock at the top with a line under it
## ("Waiting for players...", "You finished 2nd"), and the results table at the end. Layout lives in
## scenes/ui/race_hud.tscn; scripts/race/race.gd tells it what to show.

@export var go_color := Color(0.42, 0.9, 0.5)       ## GO! is drawn in this colour
@export var pop_scale := 1.6                        ## each number starts this big and shrinks to 1 over the second

@onready var _clock: Label = %Clock
@onready var _status: Label = %Status
@onready var _countdown: Label = %Countdown
@onready var _results: PanelContainer = %Results
@onready var _table: Label = %Table


## Race time as m:ss.cc.
static func format_time(t: float) -> String:
	var cs := roundi(maxf(t, 0.0) * 100.0)
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


## Countdown: `text` ("3", "2", "1", "GO!" or "") and how far through its second it is (0 to 1), for the pop.
func show_countdown(text: String, t: float) -> void:
	_countdown.visible = text != ""
	_countdown.text = text
	_countdown.modulate = go_color if text == "GO!" else Color.WHITE
	_countdown.modulate.a = 1.0 - clampf(t - 0.6, 0.0, 0.4) / 0.4 if text == "GO!" else 1.0
	_countdown.scale = Vector2.ONE * lerpf(pop_scale, 1.0, clampf(t * 4.0, 0.0, 1.0))


func show_clock(t: float, status: String) -> void:
	_clock.text = format_time(t)
	_status.text = status


## rows: [{name, time (s, < 0 = didn't finish), me (bool)}] in finishing order.
func show_results(rows: Array) -> void:
	var lines := PackedStringArray()
	var width := 6
	for r in rows:
		width = maxi(width, String(r.name).length())
	for i in rows.size():
		var r: Dictionary = rows[i]
		var place := ordinal(i + 1) if r.time >= 0.0 else "—"
		var time := format_time(r.time) if r.time >= 0.0 else "DNF"
		var name := String(r.name) + (" ◀" if r.get("me", false) else "")
		lines.append("%-4s %s%s  %s" % [place, name, " ".repeat(width + 2 - name.length()), time])
	_table.text = "\n".join(lines)
	_results.visible = true


func hide_results() -> void:
	_results.visible = false
