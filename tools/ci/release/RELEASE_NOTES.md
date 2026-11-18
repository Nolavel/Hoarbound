Pre-release for external smoke testing: **not a finished build**.

**Install**
- Windows: unzip the whole archive and run `Hoarbound.exe`. Keep `data_Hoarbound_windows_x86_64` beside it.
- Linux: unzip and run `./Hoarbound.x86_64`.
- Graphics default to LOW. MEDIUM and HIGH are in the settings menu.
- Logs are written to `logs/` beside the executable. Please send the newest `hoarbound_*.log` with your report.
- F10 saves a report zip (log, settings, system, last route, screenshot) to `reports/`. F9 records the route you play to `tapes/` so we can replay it.

**Known limitations**
- OPEN: the snow surface around Henry visibly shifted in height as he walked, with a square boundary (seen on Intel HD 620). A likely cause was fixed in 0.312c: exports now load the baked snow wind field. It has NOT yet been confirmed on the hardware where the defect was seen, so report it if you see it.
- Low frame rates on integrated GPUs. LOW now draws about 30 % fewer primitives on Duval Street, but this has not been re-measured on an HD 620.

**Changes since 0.314a**
- **English throughout:** the game now runs in English whatever the system language.
- **727 Fort Street, the real building:** rebuilt from the City of Key West 2020 permit drawings. The entrance is the glass double storefront on the side street, with a ramp under the steel canopy; new windows, wood-pattern bands, planters, the "KEY WEST HEALTH CENTER" sign, closed service doors at both ends, roof units, and snow on the roof, canopies and planters. The rooms inside keep their game layout. The compass, the start point and the supplies follow the new entrance.
- **The street around 727:** the Lofts at Bahama Village (opposite 727) and the new Frederick Douglass Community Center stand where they were built; six merged blocks are now the fifteen separate buildings of the City footprints; a wayfinding post stands at 717 Fort Street.
- **Fixes from play tests:** Henry no longer spins while aiming a snowball; a flare taken with held F is in his hand and stays there through a Hub visit; sleep and waiting burn a lit flare; no rime on what lies inside the pack; the load gauge fits the pack; an open cabinet answers F with "search" while you look at its shelves.
- **Performance:** no more hitch on every Tab, the open Hub no longer holds the game at ~22 FPS, and a long freeze the first time the camera came up against Henry is gone.
- **Saves:** broken-window records from older saves whose 727 window has moved are dropped instead of floating in the air.
