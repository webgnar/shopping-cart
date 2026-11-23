class_name CartBallHUD
extends CanvasLayer
## Cart Ball's screen: the scoreboard at the top (Green's goals, the match clock, Red's goals), a big word in the
## middle (3, 2, 1, GO!, GOAL!) and the full-time panel. Layout lives in scenes/ui/cart_ball_hud.tscn;
## scripts/ball/cart_ball.gd tells it what to show.

@export var go_color := Color(0.42, 0.9, 0.5)       ## GO! is drawn in this colour
@export var pop_scale := 1.6                        ## the big word starts this big and shrinks to 1

@onready var _green: Label = %GreenScore
@onready var _red: Label = %RedScore
@onready var _clock: Label = %Clock
@onready var _status: Label = %Status
@onready var _banner: Label = %Banner
@onready var _final: PanelContainer = %FullTime
@onready var _final_score: Label = %FinalScore
@onready var _final_line: Label = %FinalLine


## Match clock as m:ss.
static func format_clock(t: float) -> String:
	var s := ceili(maxf(t, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


func show_score(green: int, red: int, clock: float, status: String) -> void:
	_green.text = str(green)
	_red.text = str(red)
	_clock.text = format_clock(clock)
	_status.text = status


## The big word in the middle ("" hides it), its colour, and how far through it is (0 to 1) for the pop.
func show_banner(text: String, color: Color, t: float) -> void:
	_banner.visible = text != ""
	_banner.text = text
	_banner.modulate = go_color if text == "GO!" else color
	_banner.scale = Vector2.ONE * lerpf(pop_scale, 1.0, clampf(t * 4.0, 0.0, 1.0))


func show_full_time(green: int, red: int, line: String) -> void:
	_final_score.text = "GREEN %d  –  %d RED" % [green, red]
	_final_line.text = line
	_final.visible = true


func hide_full_time() -> void:
	_final.visible = false
