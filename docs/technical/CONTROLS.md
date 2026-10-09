# Controls and context rules

Every key in `project.godot` does something in the game. A key without a
consumer is removed rather than kept "for later" (#76). `tools/ci/check_input_map.py`
fails the build when two actions share a key without an entry in
`tools/ci/input_overlap_allowlist.txt`.

## Keys

| Key | Action | What it does |
|---|---|---|
| W A S D | `move_*` | Walk; any move input also stands Henry up from a seat |
| Shift | `sprint` | Sprint |
| Space | `jump` | Jump; also stands Henry up from a seat |
| C | `crouch` | Crouch |
| Q / E | `lean_left` / `lean_right` | Lean (reserved; Q/E never carry item actions) |
| Z | `switch_shoulder` | Camera shoulder |
| F | `interact` | Context action, see below |
| Tab | `open hub` | Player Hub: pack on Henry, pockets, Use |
| Wheel | `quick_next` / `quick_prev` | Pick a pocket (quick access) |
| Wheel click | `quick_use` | Draw the selected pocket item; use it on the next click once held |
| 1–4 | `select item slot 1–4` | Draw from a physical pocket: flare, hammer, knife, flask, tin or other small supplies |
| G | `drop_carried` | Put the whole log/board armful on clear ground in front of Henry; blocked placement keeps it in his arms |
| Esc | `pause` | Context back-out, see below |
| LMB | `fire` | In gameplay: Use the item already in Henry's hand; in the Hub: drag/drop |
| M | `toggle_dev_map` | Debug builds only: show/hide the diorama map when `World.enable_runtime_dev_map` is true; otherwise no effect |

### Lighting the road flare

1. Tap `F` by the flare to pick it up. After the pickup-stow animation it is
   auto-sorted into a compatible Quick Access pocket when one is free. Holding
   `F` opens manual placement instead.
2. Press the matching `1`–`4` Quick Access slot. Henry draws the **unlit**
   flare into the existing hand socket and raises the held-item arm pose.
3. Press **LMB**. Because the flare is already physically in Henry's hand, the
   existing `fire` input becomes contextual **Use held item** and strikes it.
4. Press **LMB** again to drop the burning flare.
5. Wheel-click (`quick_use`) draws the selected item first and uses an already
   held item next; the mouse wheel selects pockets without drawing them.

It is a single-use pyrotechnic light, not an on/off electric torch. At the
First Exit clock rate (a 24-hour day in 3600 real seconds), its 75 real seconds
of burn time equal **30 game minutes**.

## F: one verb, resolved by context

Two kinds of attention pick what F acts on:

- **World mechanisms** (doors, stove and firebox, windows, seats, beds, table
  food, benches) are picked by the **player's view**. A soft cone runs around the
  screen centre. When one is selected, the central prompt opens: Enso into
  brackets, gradient, key, action and detail.
- **Pickups** (`ItemPickup`) are picked by **Henry's head attention**: where his
  head looks, within ±90°. The camera framing never moves for them.
- **World wins F.** While a world mechanism is selected, the pickup gives up its
  `[F]`.

What each marker means:

| Marker | Meaning |
|---|---|
| Central brackets + prompt | F operates **this** world mechanism |
| Ring over an item: top arc + plain `F` | Tap F: take **this** item into storage (Quick Access pocket for preferred items, otherwise the pack). It shows only when Henry can physically get it: a floor spot he can walk to in a straight line, with the item inside his reach |
| Ring, lower-left arc | Hold F: take the item into the hand. On the hold the same `F` gains a key frame in place (it never moves), an open hand appears inside the ring, and the arc grows from both ends to a full circle at 1.0 s. Shown only for items a hand can show (pocket-size; not the hammer or flare yet) |
| Ring, lower-right arc | Not an action: almost invisible until a tap is refused by storage (overweight), then it lights up |
| ✕ in the ring centre, F turns red | The pickup did not happen. The lit arc names the cause: right = storage, left = hands/hold. The hand icon gives way to it; the F fades back to cream with the ✕ |
| Small `[F]` keycap over an armful | F takes the boards or logs into both arms at once |
| Faint dot over an item | Henry notices it; F does not take it now (another item is dominant, a world mechanism has F, or it cannot be reached) |
| ✓ check mark | "Notice this": opt-in for rare or authored objects only, never ordinary loot. It never makes anything actionable |

There is no manual cycling: Henry's head picks among close items.

The first matching row wins.

| Context | F does |
|---|---|
| A dialog is open (sleep or wait prompt) | Confirm the dialog |
| Hub placement is running | Nothing (LMB drags; release drops) |
| Seated, and the camera looks at something within 2 m (food on the table, the stove ring, the set-down pack) | Act on it: eat, warm up, go through the pack |
| Seated, nothing looked at | Open the wait prompt |
| Standing, a world mechanism under the view | Within 0.9 m act on it (open, board up, feed the stove, sit, sleep); further, walk to it, then act |
| Standing, a pickup ring is shown, F released within 0.22 s | Tap: store the item, turning in place or walking to the solved spot first; it takes exactly that item. Moving with WASD cancels. A newly blocked path gets one retry, then "Can't reach it from here". Overweight: ✕ in the ring centre with the right arc lit, nothing taken |
| Standing, a pickup ring is shown, F held | Past 0.22 s it is a hold, and releasing before 1.0 s cancels (never a tap). At 1.0 s the item goes into the hand. Storage still owns it and its weight; the hand only shows it. Anything already in the hand is put away into its own storage in the same step. Hands that cannot be emptied (burning flare, an armful) or overweight refuse with ✕ in the ring centre and the left arc lit; nothing is dropped |
| Bedroll placement preview is up | Lay only when the camera-ray preview is green; red means slope/clearance/distance is invalid |
| Board-placement preview is up | LMB nails the translucent board at the camera-aimed height; Esc cancels |

Rules for new features:
- A new interaction is an `InteractiveArea`, never a new key.
- Something that must take F from world targets (a preview, a dialog) handles it in
  `_input` and marks it handled; everything else stays in the normal target path.
- Manual placement in pockets is in the Hub (Tab). Holding F on a pickup no longer
  opens it.
- A seated feature is reached by looking at it (`InteractComponent` seated aim), not
  by a second key.
- An `ItemPickup` uses the pickup channel; every other `InteractiveArea` uses the world
  channel. Set `special_awareness` only for objects worth noticing from afar.

### Boarding a shelter opening

1. Pick up up to three boards. They stay visibly in Henry's arms.
2. Aim at an opening and press `F`: the whole armful is laid beside that opening.
3. Pick the shelter hammer from Quick Access (`1`–`4` or wheel selection).
4. Aim at the opening and press `F` again. Henry takes one staged board in the other hand.
5. Move the camera up/down. The translucent board stays bound to the opening plane.
6. `LMB` nails that exact position. It spends one staged board and **2 nails**.
7. Overlapping placements are legal: only actual covered height reduces the remaining wind/snow gap.

The hammer and a 66-nail box are authored inside the First Exit shelter.

### Water, tins and wood

Place supplies into pockets through the Hub. `1`–`4` or wheel-click draws the
selected item; `LMB` uses the item physically held. Changing pockets or opening
the Hub stows it without losing it. A flask's physical mark and persistent readout
show remaining water; each drink is 250 ml. Opening pineapple requires an owned
knife and leaves an opened tin; the next Use eats it. Seated table F uses the same
two steps. Game prompts follow the selected locale.

`G` is the author's explicitly requested exception to the contextual F-only
grammar for releasing two-hand loads. It tries a short list of spots: straight
ahead, slightly left or right, nearer, wider, farther. At each it tries the pile
across or along Henry. A floor ray, wall check and whole-pile clearance check
prevent placement through walls or over deep drops. If none fits, the load stays
in the hands. `F` picks
the pile back up. Draw the hatchet from the tool bench, aim at loose boards and
`F` starts four seconds of chopping: one board yields one log. Without a drawn
hatchet the boards remain ordinary pickups. Only the two supply benches can be
dismantled with the hammer; the cloth-covered ritual table remains available.

## Esc: always one step back

| Context | Esc does |
|---|---|
| Sleep or wait prompt open | Cancel the prompt |
| Hub open (any mode, including inspection) | Close the Hub; an inspected pack goes back on |
| Bedroll placement preview | Cancel the preview; nothing is spent |
| Seated | Stand up |
| Otherwise | Pause menu |

Each owner claims Esc in `_input` and marks it handled, so the pause menu
(`_unhandled_input`) only sees it when nothing else is open.
