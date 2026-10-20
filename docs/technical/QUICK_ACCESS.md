# Quick Access

Quick Access is a physical-pocket selector around Henry, not a generic hotbar.

## Runtime grammar

- First mouse-wheel tick opens the selector and does not change the selection.
- Wheel down moves clockwise through filled physical pockets.
- Wheel up moves counter-clockwise through filled physical pockets.
- LMB confirms the highlighted pocket and draws its item.
- RMB closes the selector without changing the held item.
- `1`–`4` remain expert direct-draw shortcuts. They flash only the addressed pocket instead of opening the full selector.
- Empty pockets stay visible as part of Henry's body map but wheel navigation skips them.

The four selectable locations are:

1. left coat pocket;
2. right coat pocket;
3. left thigh pocket;
4. backpack lid pocket.

`HANDS` is deliberately not a fifth slot. It is a live status card that reports the item Henry is actually holding and, when useful, its state.

## Presentation

The cards are projected from `QuickAccessAnchors` around Henry and rendered as screen-space `Control` nodes so they stay readable over the 3D world.

- The anchor rig follows camera yaw each frame; screen-space card following provides the visible smoothing.
- Opening the selector does not pause orbit. In a normal frame, each card follows its own `Node3D` anchor. When projected cards begin to crowd, or the camera frames Henry in a tight space (`TpsCamera.get_composition()`), they blend smoothly into a cross around `HANDS`. As framing opens up, they blend back to their individual anchors.
- The cross has fixed places: left coat pocket left, right coat pocket right, pack lid above, thigh below. Spacing comes from the real card sizes plus `ORBIT_GAP_PX`, so no two cards can touch; the cross is bounded as a whole, never card by card.
- The cross centre glides from Henry's projected hands to the screen centre with the camera composition: around Henry when cards merely crowd in the open, centred on screen in tight spaces where Henry sits low at the frame edge.
- The selector closes after five seconds without navigation or confirmation. Each wheel tick while open restarts the five-second countdown, even if no other filled pocket is available.
- Cards use `BG_frame.gdshader`; `reveal` grows the background outward and `base_color` carries inactive/active state.
- Pocket cards keep a directional fade toward the composition centre.
- `HANDS` uses a prompt-like centred strip: a compact filled core, then continuous alpha falloff to transparent at both horizontal ends.
- The active pocket is warm yellow; inactive occupied pockets are gray; empty pockets are quieter.
- Confirming a pocket sends a temporary copy of its icon toward `HANDS`, then the physical held presentation is updated.
- Direct keys use the same transfer language but reveal only the selected pocket and `HANDS`.

## Icon language

Quick Access icons use the same Google Material Symbols Rounded family as the existing pickup-marker hand icon. The icons are monochrome white SVGs so Godot can tint them. Source and licence notes live in `assets/ui/hud/quick_access/icons/ICON_SOURCES.md`.

## Verification

Commit marker `[quick-access-preview]` activates the existing `checks` workflow's Quick Access preview job. The capture loads production `key_west_reality.tscn` (it waits for the street chunk to stream in), keeps Henry as a live grounded `Player` with normal idle/AnimationTree processing, runs the selector sequence in the real Key West scene, encodes an MP4 and uploads key PNGs plus `report.json`.
