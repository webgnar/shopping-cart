class_name ProductDisplay
extends Node3D
## A sale table with a stack of one product on it (scenes/sweep/product_display.tscn). In a supermarket sweep a cart
## that rolls slowly through its GrabZone gets the items one at a time, top of the stack first.
##
## The stack is the Product scenes under Stock, placed in the editor; the sign reads its name and price from the
## first of them and counts down what's left.

@export var stock: Node3D        ## the Product items on the table
@export var zone: Area3D         ## a cart's frame in here, rolling slowly, takes the next item
@export var stop: Marker3D       ## where a bot parks its cart to shop here
@export var title: Label3D       ## "COFFEE  $8.99"
@export var left_label: Label3D  ## "8 left"

## A guest's count from the host (the host's items are moved by the network, not taken here). -1: count them.
var left_override := -1
var _shown := ""


func items() -> Array[Product]:
	var out: Array[Product] = []
	for c in stock.get_children():
		if c is Product:
			out.append(c)
	return out


func product_name() -> String:
	var all := items()
	return all[0].product_name if not all.is_empty() else ""


func price() -> float:
	var all := items()
	return all[0].price if not all.is_empty() else 0.0


## Items still on the table.
func left() -> int:
	if left_override >= 0:
		return left_override
	return items().filter(func(p): return p.on_display).size()


## The item a cart takes next: the last one placed (the top of the stack), or null once it's empty.
func next_item() -> Product:
	var all := items()
	for i in range(all.size() - 1, -1, -1):
		if all[i].on_display:
			return all[i]
	return null


func restock() -> void:
	for p in items():
		p.restock()


func _ready() -> void:
	title.text = "%s\n$%.2f" % [product_name().to_upper(), price()]


func _process(_delta: float) -> void:
	var n := left()
	var text := "SOLD OUT" if n == 0 else "%d left" % n
	if text != _shown:
		_shown = text
		left_label.text = text
