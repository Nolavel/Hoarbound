# First Exit A — stranger playtest run (#80)

One continuous run on the integrated candidate, Graciosa, no debug, no teleport, no TestScene.
Game time is fixed: 60 real minutes per game day, a new game starts at 12:00
(#42), so a 10–15 minute run ends in late afternoon / dusk.

Start **New Game**, not Continue from a shelter test save. Record the candidate
commit, renderer, locale and elapsed real time before the run. Do not delete the
author's saves. The current candidate starts at the bunker and retains all
author-approved supplies: 33 boards, 66 nails, 12 logs (nine at the shelter), both kits,
one flask and two pineapple tins. The historical scarcity reduction is not part
of this candidate. Existing WeatherBeat and pickup/save systems are implemented;
this run checks whether a stranger discovers and completes their connected flow.

## Before: what the observer says to the tester

Say only this:

> "You play Henry. Survive the first night. WASD moves; F interacts; Tab opens
> your pack; 1–4 draws from pockets; LMB uses the held item; G puts carried wood
> down; Esc goes back. Think aloud. I will observe without helping."

Do **not** mention: tinder, boards, the shelter house, wind, the weather turn,
sitting, the stove ring, the table, or sleep = save.

## Timeline and what to watch

| Real time | Beat | Watch for | Ask after the run |
|---|---|---|---|
| 0:00–0:45 | Bunker, exile | Does the tester try the bunker door? Do they read "no way back"? Is the water tower a heading? | "Where were you, and why did you leave?" |
| 0:45–2:00 | Route choice: road / shore / ruins | Which route, and did they look before choosing? | "Why that way?" |
| 2:00–5:30 | Resources | Do they read boards / tinder / firewood as future decisions? Do they leave something behind? | "What did you not take, and why?" |
| When 200 m from the start, or after 5 min; deferred while sheltered | Weather turn | Did the plan change: faster, less looting, a sheltered path, no going back? | "What changed when the storm came?" |
| 5:30–7:30 | Finding the shelter among 11 lots | Did they pick it by looking (breaches, stove, mattress), or by a prompt? | "How did you know which house?" |
| 7:00–9:00 | 4 repairable windows + operable door, boards carried three at a time | Do they discover staging, hammer/nails and camera-aimed LMB placement? Which holes do they choose first? | "Which windows did you close, and why those?" |
| 8:00–12:00 | Stove and recovery | Light the stove (3 s held catch, 20 s development), sit, wait, dry (steam, trend marks), warm food on the ring, eat from the table. Did it read as a ritual or as a chain of F prompts? | "What were you doing by the stove?" |
| 11:00–15:00 | Sleep → save → reload | Sleep through the mattress/bedroll. Reload the slot: picked-up loot must not return (#79), shelter, fuel, weather, bedroll and inventory must hold. | — |

Use F on the stove: Henry walks to its door, opens it and crouches. RMB lays
one log per press; LMB lays tinder once a log is in; release, then a new LMB
press strikes the lighter and a 3-second hold lights it. F closes the stove. The
fire then develops over 20 seconds. Observe hand item visibility, water remaining, knife refusal and separate
pineapple opening/eating, G drop recovery and the protected seated meal ritual.
Do not give these steps to the tester in advance. If they need help, record the
timestamp, intended action, visible prompt and intervention as a failed link.

## Pass

**Pass** needs every beat to happen without the observer's help, and the
tester's own retelling to carry this chain, in their words:

> "They left me outside. I chose a path because I saw its cost. I did not take
> everything. The weather turned and made me change the plan. I found a house,
> saw where the wind got in, closed what I could, made a fire, warmed up, dried
> off, ate, and only then lay down. After loading, the world remembered."

If all systems fire but this chain does not appear in the retelling, First
Exit A is **not** done. Write one line per missing link and file it.

## Failure run (second pass)

Freeze or fail the night on purpose (greed for weight, ignoring the storm,
wrong boards). The tester must be able to say what to do differently.

## Publisher frames

`tools/runtime/capture_first_exit_frames.gd` renders the six frames of the #80
table (bunker and tower, route with clutter, weather turn, boarding, lit stove,
seated with Kenny) into `user://shots/first_exit/`. They are for the capture
checklist, not a substitute for the human run.
