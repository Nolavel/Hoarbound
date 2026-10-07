class_name LocomotionDynamicsProfile
extends Resource

## Walking dynamics another system may ask MovementController for by id. The
## movement layer owns these values and decides where they apply.

## Name a requester asks for, e.g. &"data_matched".
@export var id: StringName = &""
## Acceleration and braking towards the walking target speed, m/s^2.
@export var walk_accel_m_s2: float = 12.0
@export var walk_decel_m_s2: float = 18.0
## Damping rate of Henry turning to face where he walks, as Player.turn_rate.
@export var turn_rate: float = 10.0
