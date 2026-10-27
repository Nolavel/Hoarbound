class_name TemperatureText
extends RefCounted

## Signed whole degrees for IM Fell English SC, which has no minus sign and draws "-" like a
## tilde: negatives take the en dash it does have, positives a plus.


static func signed(celsius: float) -> String:
	var whole: int = roundi(celsius)
	if whole < 0:
		return "–%d" % -whole
	return "+%d" % whole if whole > 0 else "0"
