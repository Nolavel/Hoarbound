class_name Opener
extends InteractiveArea

## A way into a container (a door, a lid, a drawer): what the container asks, whatever kind it is. A new kind
## extends this and plugs into ItemContainer.openers with no change there (ARCHITECTURE §16).

## It starts to open (true) or to shut.
signal toggled(open: bool)


## Whether it stands open now (a kind overrides it).
func is_open() -> bool:
	return false


## Whether it is still moving between open and shut.
func is_swinging() -> bool:
	return false
