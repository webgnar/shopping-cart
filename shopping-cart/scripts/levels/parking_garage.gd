extends "res://scripts/main.gd"
## Parking garage level: start on the roof and roll the cart down ten gently sloped floors. Floors 10 to 6
## turn right at each flat landing; at the halfway landing the garage carries on into a second wing where
## floors 5 to 1 turn left, and you leave at street level.
##
## Everything (decks, walls, parked cars, lights, sky, the CartSpawn marker) is nodes in
## scenes/levels/parking_garage.tscn; main.gd supplies the cart, camera, input and HUD.
