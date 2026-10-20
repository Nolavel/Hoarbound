class_name SnowResistance
extends RefCounted
## Snowpack between the drawn top and hard ground, felt through the boots: crust holds
## until a step's load breaks it, drift pockets plunge a leg. Henry's collider stays on the ground.

## Crust strength varies in patches about this wide, metres: the same-looking surface
## holds in one place and gives way a stride further on.
const CRUST_PATCH_M: float = 1.6
## Soft pockets under drifts, about this wide.
const POCKET_M: float = 1.1
## Drift depth over the settled cover at which pockets are fully possible, metres.
const POCKET_DRIFT_M: float = 0.2


## How one boot settles at one plant. `support` is where it rests while the crust
## holds; after `break_s` seconds of stance it drops to `plunge` (INF: never breaks).
class Plant extends RefCounted:
	var support: float = 0.0
	var plunge: float = 0.0
	var break_s: float = INF

	func broke() -> bool:
		return break_s < INF


## A plant at `at`: `softness` 1 powder .. 0 crust, `drift` depth above the settled cover,
## `impact` 0 slow walk .. 1 run, `load_share` the weight on this boot (about half standing).
static func plant(at: Vector2, depth: float, softness: float, drift: float, impact: float, max_pack: float, load_share: float = 1.0) -> Plant:
	var p := Plant.new()
	var give: float = depth * max_pack
	## Loose snow compacts by its share of the give, as before the crust model.
	var loose: float = give * softness
	var crust: float = 1.0 - softness
	var strength: float = crust * lerpf(0.3, 1.5, SnowField._vnoise(at / CRUST_PATCH_M + Vector2(41.0, 7.0)))
	var load: float = (0.55 + 0.6 * clampf(impact, 0.0, 1.0)) * load_share
	p.support = loose + give * crust * 0.15
	p.plunge = p.support
	if crust > 0.1 and load > strength:
		p.plunge = maxf(give, p.support)
		## Stronger crust bears the load a moment longer before it snaps.
		p.break_s = 0.05 + 0.25 * clampf(strength / load, 0.0, 1.0)
	var pocket: float = smoothstep(0.62, 0.8, SnowField._vnoise(at / POCKET_M + Vector2(3.0, 19.0))) \
		* clampf(drift / POCKET_DRIFT_M, 0.0, 1.0)
	if pocket > 0.5:
		p.plunge = maxf(p.plunge, depth * lerpf(max_pack, 0.95, pocket))
		p.break_s = minf(p.break_s, 0.08)
	return p


## Sink after `t` seconds of stance: settling onto the support, then the plunge.
static func sink_at(p: Plant, t: float, settle_s: float, impact: float) -> float:
	var settle: float = 1.0 - exp(-maxf(t, 0.0) / maxf(settle_s, 0.001))
	var sink: float = p.support * lerpf(settle, 1.0, clampf(impact, 0.0, 1.0))
	if t > p.break_s:
		sink += (p.plunge - p.support) * (1.0 - exp(-(t - p.break_s) / 0.07))
	return sink
