# xk research — questions worth testing in Hoarbound

> **Critical prompts, not a second GDD.** Nothing in this file is a feature request, accepted design decision, implementation instruction or playtest result. The purpose is to help agents challenge assumptions **without importing xk's taste as Hoarbound canon**.

Read [INDEX.md](INDEX.md) for source topics and [SOURCE.md](SOURCE.md) for provenance. Confirm current gameplay in GitHub and any production decisions in Miro before proposing changes.

## First Exit A — comprehension without hand-holding

**Possible question:** Can an unfamiliar player understand the next plausible *action* (shelter, weather pressure, equipment) without the game prescribing an optimal route? Where do diegetic cues work, and where is the player simply stuck?

- Cross-check: [experience pillars](../../game_design/EXPERIENCE_PILLARS.md), [First Exit contract](../../game_design/VERTICAL_SLICE.md), [GDD snapshot](../../GDD.md).
- External lens: [game design — player learning / readability](https://github.com/Dis1re/xk_streamparser/blob/main/notes/01_геймдизайн.md), [production — playtests](https://github.com/Dis1re/xk_streamparser/blob/main/notes/05_производство_и_процесс.md).
- Evidence to seek: observations from fresh-player runs, not agent intuition. Distinguish *intentional uncertainty* from *unreadable interaction*.

## Survival decisions — systems that alter behaviour

**Possible question:** Do weather, exposure, fatigue, inventory and fuel cause actual choices and improvisation, rather than only repeated upkeep? Is a decision understandable **after** its consequences without displaying excessive HUD instruction?

- Cross-check: [experience pillars](../../game_design/EXPERIENCE_PILLARS.md) and current owners in [GDD](../../GDD.md).
- External lens: [game design — systems, choices and difficulty](https://github.com/Dis1re/xk_streamparser/blob/main/notes/01_геймдизайн.md).
- Evidence to seek: moments when players voluntarily change route, loadout or schedule because of world state; do not add mechanics just to increase complexity.

## Shelters and spatial memory — clarity through place

**Possible question:** Do Fort Street, recognizable landmarks and the character of shelters help players learn the city without a quest-arrow system? Does shelter comfort feel earned by danger and work?

- Cross-check: [Key West design doctrine](../../world/KEY_WEST_DESIGN_DOCTRINE.md), [experience pillars](../../game_design/EXPERIENCE_PILLARS.md).
- External lens: [game design — levels, pacing and narrative/world](https://github.com/Dis1re/xk_streamparser/blob/main/notes/01_геймдизайн.md).
- Evidence to seek: wayfinding observations and players' own spatial descriptions. **Do not** take generic HUD/navigation advice as permission to replace the approved diegetic approach.

## Backpack and physical interaction — meaningful friction

**Possible question:** Which gestures make item selection and storage feel physical and legible, and which merely delay player intent? Can sound and spatial feedback communicate failure or success before adding more text?

- Cross-check: [experience pillars](../../game_design/EXPERIENCE_PILLARS.md), [architecture](../../technical/ARCHITECTURE.md), existing inventory implementation.
- External lens: [game design — game feel and readability](https://github.com/Dis1re/xk_streamparser/blob/main/notes/01_геймдизайн.md).
- Evidence to seek: repeated pickup/storage attempts, misreads and cancellation behaviour. A reference is **not** an implementation specification.

## Prototype and testing — falsifiable questions

**Possible question:** What single hypothesis must each First Exit playtest verify? Can observers separate control confusion, survival misunderstanding and a deliberate creative choice?

- Cross-check: [First Exit scope](../../game_design/VERTICAL_SLICE.md) and the owner's current test plan/production priorities.
- External lens: [production — prototype and playtests](https://github.com/Dis1re/xk_streamparser/blob/main/notes/05_производство_и_процесс.md).
- Evidence to seek: observed actions, points of hesitation and exact questions players ask, not only favorable impressions. A suggestion becomes a task only through the normal owner-approved workflow.

## Steam and positioning — later-stage critical review

**Possible question:** When the game has representative footage and a tested loop, does its store presentation communicate *systemic survival in frozen Key West* to its intended audience? Are marketing forecasts based on current external data?

- Cross-check: [PRD](../../../PRD.md), [First Exit contract](../../game_design/VERTICAL_SLICE.md), current owner roadmap.
- External lens: [marketing and Steam](https://github.com/Dis1re/xk_streamparser/blob/main/notes/02_маркетинг_и_steam.md), [outdated or qualified advice](https://github.com/Dis1re/xk_streamparser/blob/main/notes/99_устаревшие_советы.md).
- Evidence to seek: real player/store feedback and independently verified current Steam guidance. Stream-era percentages and anecdotes are **not** targets or forecasts for Hoarbound.

## Required form of an agent's critique

For any external argument that affects a recommendation, write:

1. **Hoarbound fact** — link to a canonical document, current code or observed playtest.
2. **External viewpoint** — the exact upstream note, and stream/timecode when available; mark uncertainty or guest attribution.
3. **Tension or opportunity** — how the viewpoints differ, including why the outside suggestion might be inappropriate.
4. **Proposed test** — smallest observation or experiment that could distinguish the alternatives.
5. **Decision status** — *hypothesis only* until the author accepts it. Do not record it in Miro/GDD as approved on the basis of this file.

Owner-approved intent wins over imported advice. Conflict is a reason to **ask for a decision**, not to silently substitute the outside viewpoint.
