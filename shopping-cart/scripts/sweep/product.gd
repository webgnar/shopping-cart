class_name Product
extends RigidBody3D
## One item a shopper can sweep into their cart in a supermarket sweep (scripts/sweep/sweep.gd): a box of cereal,
## a can of coffee. Each product is its own scene in scenes/sweep/products/ with its name and price set here in the
## inspector; a ProductDisplay holds a stack of them under its Stock node.
##
## It sits frozen on its display until a slow cart rolls past, then the sweep drops it into that cart's basket as
## a loose body: it rides along, it can spill out in a crash, and it only scores while it's in a basket.

@export var product_name := "Item"
## Dollars. A cart's score is the price of everything in its basket (at most the sweep's item_limit of each product).
@export var price := 1.0

## Where it sits on its display, taken when the level loads; restock() puts it back.
var rest := Transform3D.IDENTITY
## true: still on its display (frozen there); false: taken, now a loose body somewhere in the store.
var on_display := true


func _ready() -> void:
	rest = global_transform


## Price in whole cents (scores are added up in cents so they never drift).
func cents() -> int:
	return roundi(price * 100.0)


## Back on its display, frozen, as at the start of a sweep.
func restock() -> void:
	freeze = true
	global_transform = rest
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	on_display = true


## Off the display and dropped into `cart`'s basket at `slot` (cart-local, see ShoppingCart.basket_drop), moving
## with the cart so it lands rather than being left behind.
func drop_into(cart: ShoppingCart, slot: Vector3) -> void:
	on_display = false
	var xf := cart.frame.global_transform
	global_transform = Transform3D(xf.basis.orthonormalized() * rest.basis.orthonormalized(), xf * slot)
	freeze = false
	linear_velocity = cart.frame.linear_velocity
	angular_velocity = Vector3.ZERO
	sleeping = false
