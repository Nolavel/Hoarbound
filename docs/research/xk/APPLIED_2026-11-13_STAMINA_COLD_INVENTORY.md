# xk theses applied: stamina, cold readout, pack and inventory (2026-11-13)

The owner asked for the xk notes to be applied to gameplay, and for a re-check of the pack, the inventory,
the body-cold readout and stamina, with stamina made smoother and intuitive. This note follows the format
in `HOARBOUND_RELEVANCE.md`: Hoarbound fact, external thesis, gap, check, status. The thesis citations
come from the external `notes/01_геймдизайн.md` at upstream `main`, read on 2026-11-13. They are
cited as in the source; the videos were not re-watched.

## Stamina

| Item | Content |
|---|---|
| **Fact (measured before the change)** | A sprint empties the tank in 20 s. The tank then refilled only after 5 s of nothing, at 3 per second, so 33 s to full, the same walking or standing. Holding Shift on an empty tank blocked recovery: every crumb of breath re-enabled the sprint, which ate it and restarted the 5 s pause. In a replayed route the tank sat at 0 for 18 s of walking. At 0 the run snapped from 4.5 to 1.5 m/s. The only display, the cursor arcs, vanished as the tank emptied, so nothing said why the run stopped or when it would return. |
| **Theses** | "Lerp and smoothing are critical for the feel" `[2026-08-15 · 166 02:13:00]`. "The character obeys the player, not the animations" `[2026-06-16 · 151 01:16:00]`. "Showing −2 next to the energy counter replaces a tutorial" `[2026-03-24 · 128 00:26:00]`. |
| **Gap** | The pause, the empty-tank trap and the missing feedback break all three. |
| **Change** | See below. |
| **Check** | The replay of a 30 s run, then a 10 s walk, then standing (`tools/runtime/replay_input_tape.tscn`, ice-lab shore): <br>• sprint back at 29 s instead of 40 s; <br>• full at 55 s instead of 74 s; <br>• the run fades 4.5 → 3.0 m/s over its last 4 s. <br>`test_stamina_recovery` fails on the old code (4 of 5 checks). |
| **Status** | Done at the owner's request. All numbers are exports, for tuning after a play session. |

**Change:**
- **Empty tank.** Henry is winded until breath is back to 35 %: no sprint flicker, and holding Shift no longer blocks recovery.
- **Recovery.** It starts 1 s after the last exertion instead of 5 s, and eases in over 0.8 s.
- **Pace by activity.** Recovery runs at full pace standing (empty to full in about 12 s), 0.55 walking, 0.75 sneaking and 0 in the air. It slows down to 0.6 with no energy, using the `FatigueComponent` data the sprint already reads.
- **Winded jog.** The winded fade, already in the code and proposed earlier, is now on (`winded_sprint_share` 0.4), so the run tapers into a laboured jog instead of snapping to a walk.
- **Cursor arcs.**
  - They now sit on a faint full-circle track; their length is the tank and their brightness no longer drops with it.
  - Before, the arcs faded with the tank, so at 19 % they were nearly invisible and at 0 not drawn at all: the moment the player most needed to know was the one shown least (`capture_stamina_cursor.gd`, before and after).
  - After a run they stay and fill as breath comes back; they fade out once the tank is full.
  - While winded the track breathes in dim red.

## Body-cold readout

| Item | Content |
|---|---|
| **Fact** | `capture_vitals_hud.gd` in Key West Reality: <br>• blizzard: body 34.7 °C, felt −21 °C; <br>• critical night: 29.9 °C; <br>• at the stove: 34.1 °C, felt +7 °C. <br>The warmth column is yellow, then red, then rising. Falling and rising chevrons show the rate of change, `FEELS` says where Henry stands, and the silhouette frosts the exposed parts. `test_cold_readouts`, `test_thermal_model` and `test_vital_cluster` pass. |
| **Theses** | "−2 next to the counter" (above). "Weak agency: constant damage you cannot answer kills the wish to play" `[2026-07-04 · 154 00:39:00]`. |
| **Assessment** | Applicable and already met. The chevrons are the "−2", and `FEELS` changes the moment Henry steps into shelter or near a fire, so the answer to the cold is readable without text. No change made. |
| **Open question** | Does a first-time player link `FEELS` to "go inside"? That needs a stranger's first run (see the playtest question in `HOARBOUND_RELEVANCE.md`), not an agent. |
| **Side note** | The controls panel bottom right sits on a large dark ink blot that reads heavy against snow. It is not part of this task and is left for the owner. |

## Pack and inventory

| Item | Content |
|---|---|
| **Fact** | **Suites** — 11 pack, hands, pocket and quick-access suites pass. <br>**`audit_727_pickups.gd` in the real 727:** <br>• all 11 open-floor pickups are taken by F; <br>• the 9 inside cabinets and drawers need the container opened first, which this audit does not do; <br>• the Quick Access draws from pockets, straps and carabiners work; <br>• Tab's hand card puts the pack knife and the pocket hammer in hand; <br>• X empties the hands; <br>• the lighter "not drawn" is the audit's own order (a burning flare is already in hand), as found earlier. |
| **Thesis** | Friction should mean something: physical presence, not a delay of intent (`HOARBOUND_RELEVANCE.md`, pack section). |
| **Assessment** | No defect found to fix. Whether the pack's physical steps feel meaningful or slow is a playtest question: watch for repeated attempts and cancellations. |
| **Status** | Verified, nothing changed. |

## Closed loop (proposal only, not built)

"A good system feeds itself: A feeds B, B feeds C, C changes A" `[2026-10-06 · 180 01:24:00]`.

Today:
- energy (fatigue) slows the sprint build-up and the breath recovery;
- load slows walking;
- cold does not touch stamina.

One candidate is that a chilled body catches its breath slower, so cold → stamina → route choice → exposure.

This changes balance, so it needs the owner's decision. The hook would be `MovementController.get_recovery_share()`.
