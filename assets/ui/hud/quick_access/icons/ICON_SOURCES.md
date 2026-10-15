# Quick Access icon set

These monochrome HUD icons intentionally match the existing pickup-marker hand icon.

Source family: Google Material Symbols, Rounded style, 48 px SVG.
Licence: Apache License 2.0. The repository already carries the full licence text at
`assets/ui/hud/pickup_marker/APACHE-2.0.txt`.

Files and upstream sources:
- `apparel.svg` — `symbols/web/apparel/materialsymbolsrounded/apparel_48px.svg`
- `backpack.svg` — `symbols/web/backpack/materialsymbolsrounded/backpack_48px.svg`
- `local_fire_department.svg` — `symbols/web/local_fire_department/materialsymbolsrounded/local_fire_department_48px.svg`
- `water_bottle.svg` — `symbols/web/water_bottle/materialsymbolsrounded/water_bottle_48px.svg`
- `lunch_dining.svg` — `symbols/web/lunch_dining/materialsymbolsrounded/lunch_dining_48px.svg`
- `inventory_2.svg` — `symbols/web/inventory_2/materialsymbolsrounded/inventory_2_48px.svg`

Upstream repository: `google/material-design-icons`.

Changes from upstream: each path is explicitly filled white so Godot can tint it through
`TextureRect.modulate`. Geometry is unchanged.
