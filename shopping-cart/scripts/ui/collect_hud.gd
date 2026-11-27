class_name CollectHUD
extends SweepHUD
## The cart collection round's screen (scenes/ui/collect_hud.tscn, the sweep's HUD with its own captions): the count,
## the time left, your points with the carts you've returned and the chain you're pushing, a pop-up for each cart
## that cashes in, everyone's points down the side in multiplayer, and the results at the end.
## scripts/collect/cart_collect.gd tells it what to show.


func show_score(points: int, returned: int, carrying: int) -> void:
	%Total.text = str(points)
	%Detail.text = "%d cart%s returned%s" % [returned, "" if returned == 1 else "s",
		"  ·  pushing %d" % carrying if carrying > 0 else ""]


## rows: [{name, points, me}] best first; empty hides the list.
func show_board(rows: Array) -> void:
	%Standings.visible = not rows.is_empty()
	var lines := PackedStringArray()
	for r in rows:
		lines.append("%s%s  %d" % ["▶ " if r.me else "", r.name, r.points])
	%Standings.text = "\n".join(lines)


## rows: [{name, points, returned, best_chain, me}] best first.
func show_final(rows: Array) -> void:
	var lines := PackedStringArray()
	var width := 6
	for r in rows:
		width = maxi(width, String(r.name).length() + 2)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var name := String(r.name) + (" ◀" if r.get("me", false) else "")
		lines.append("%-4s %s%s %5d pts  %2d carts  (longest chain %d)" % [RaceHUD.ordinal(i + 1), name,
			" ".repeat(width - name.length()), r.points, r.returned, r.best_chain])
	%Table.text = "\n".join(lines)
	%Results.visible = true
