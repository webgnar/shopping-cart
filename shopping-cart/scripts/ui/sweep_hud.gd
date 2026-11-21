class_name SweepHUD
extends CanvasLayer
## The supermarket sweep's screen: the 3, 2, 1, GO! in the middle, the time left at the top with a line under it,
## what your basket is worth, a short pop-up for each thing that happens (an item in, a bonus, a spill), everyone's
## totals down the side in multiplayer, and the results table at the end. Layout lives in scenes/ui/sweep_hud.tscn;
## scripts/sweep/sweep.gd tells it what to show.

@export var go_color := Color(0.42, 0.9, 0.5)       ## GO! is drawn in this colour
@export var pop_scale := 1.6                        ## each number starts this big and shrinks to 1 over the second
@export var hurry_time := 10.0                      ## s left: the clock turns hurry_color
@export var hurry_color := Color(1, 0.42, 0.42)
@export var toast_time := 1.6                       ## s a pop-up stays up
@export var toast_lines := 3                        ## pop-ups shown at once (newest at the top)

@onready var _clock: Label = %Clock
@onready var _status: Label = %Status
@onready var _countdown: Label = %Countdown
@onready var _total: Label = %Total
@onready var _detail: Label = %Detail
@onready var _toasts: Label = %Toasts
@onready var _standings: Label = %Standings
@onready var _results: PanelContainer = %Results
@onready var _table: Label = %Table

var _toast_list: Array = []   ## [[text, seconds left]]


## Cents as dollars: $123.45.
static func money(cents: int) -> String:
	var neg := cents < 0
	cents = absi(cents)
	return "%s$%d.%02d" % ["-" if neg else "", cents / 100, cents % 100]


## Time left as m:ss.
static func format_left(t: float) -> String:
	var s := ceili(maxf(t, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


## Countdown: `text` ("3", "2", "1", "GO!" or "") and how far through its second it is (0 to 1), for the pop.
func show_countdown(text: String, t: float) -> void:
	_countdown.visible = text != ""
	_countdown.text = text
	_countdown.modulate = go_color if text == "GO!" else Color.WHITE
	_countdown.modulate.a = 1.0 - clampf(t - 0.6, 0.0, 0.4) / 0.4 if text == "GO!" else 1.0
	_countdown.scale = Vector2.ONE * lerpf(pop_scale, 1.0, clampf(t * 4.0, 0.0, 1.0))


func show_clock(left: float, status: String) -> void:
	_clock.text = format_left(left)
	_clock.modulate = hurry_color if left <= hurry_time and left > 0.0 else Color.WHITE
	_status.text = status


func show_basket(cents: int, items: int, bonus_cents: int) -> void:
	_total.text = money(cents)
	_detail.text = "%d item%s%s" % [items, "" if items == 1 else "s",
		"  ·  bonus %s" % money(bonus_cents) if bonus_cents > 0 else ""]


## rows: [{name, cents, me}] best first; empty hides the list.
func show_standings(rows: Array) -> void:
	_standings.visible = not rows.is_empty()
	var lines := PackedStringArray()
	for r in rows:
		lines.append("%s%s  %s" % ["▶ " if r.me else "", r.name, money(r.cents)])
	_standings.text = "\n".join(lines)


func toast(text: String) -> void:
	_toast_list.push_front([text, toast_time])
	_toast_list.resize(mini(_toast_list.size(), toast_lines))
	_show_toasts()


func _process(delta: float) -> void:
	if _toast_list.is_empty():
		return
	for t in _toast_list:
		t[1] -= delta
	_toast_list = _toast_list.filter(func(t): return t[1] > 0.0)
	_show_toasts()


func _show_toasts() -> void:
	_toasts.text = "\n".join(_toast_list.map(func(t): return t[0]))
	_toasts.modulate.a = clampf(_toast_list[0][1] / 0.3, 0.0, 1.0) if not _toast_list.is_empty() else 0.0


## rows: [{name, cents, items, bonus_cents, me}] best first.
func show_results(rows: Array) -> void:
	var lines := PackedStringArray()
	var width := 6
	for r in rows:
		width = maxi(width, String(r.name).length() + 2)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var name := String(r.name) + (" ◀" if r.get("me", false) else "")
		var bonus := "  (bonus %s)" % money(r.bonus_cents) if r.bonus_cents > 0 else ""
		lines.append("%-4s %s%s %9s  %2d items%s" % [RaceHUD.ordinal(i + 1), name, " ".repeat(width - name.length()),
			money(r.cents), r.items, bonus])
	_table.text = "\n".join(lines)
	_results.visible = true


func hide_results() -> void:
	_results.visible = false
