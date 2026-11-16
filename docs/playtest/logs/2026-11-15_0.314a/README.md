# Windows playtest log — Hoarbound 0.314a

Captured: 2026-11-15 20:59:17 (log header). Windows / GTX 1050 Ti / Vulkan Forward+ / 1920×1080.
Tracking issue: [#42 — First Exit A Windows smoke test](https://github.com/Nolavel/Hoarbound/issues/42).

## Raw file

Original: `hoarbound_2026-11-15_20-59-17.log`
Size: **3,938,119 bytes**; **2,342 lines**.
Original SHA-256: `1c4847e92f2169af5250cc83f9c3466966db4ac449471d72a705da4537ec2415`.

The GitHub connector could not send the 3.8-MB log in a single request, so the raw UTF-8 text was split on line boundaries into **eight lossless parts**:
`part-01.log` through `part-08.log`.
Parts 01–07 contain 300 lines each; part 08 contains 242 lines. Each part ends in LF.
The concatenation is the original log.

Reconstruct (Linux/macOS/WSL, from this directory):

```sh
cat part-*.log > hoarbound_2026-11-15_20-59-17.log
sha256sum hoarbound_2026-11-15_20-59-17.log
```

Cross-platform Python:

```python
from pathlib import Path
folder = Path(".")
parts = sorted(folder.glob("part-*.log"))
assert len(parts) == 8
output = folder / "hoarbound_2026-11-15_20-59-17.log"
output.write_bytes(b"".join(part.read_bytes() for part in parts))
```

## Interpretation

The one SESSION contains three `[World] initialized` intervals; do not assume these are independent process startups.
All three `[PerfMeta]` records have the same display settings (`snow_quality=high`, `vsync_mode=1`, 1920×1080).
The snow offscreen buffer sizes differ in interval 3; cause not established.
The `[Boot] ... at N s` values appear to be session uptime, not per-world boot duration.

This is evidence only; work scope and acceptance remain in issue #42 and the Miro production board.
