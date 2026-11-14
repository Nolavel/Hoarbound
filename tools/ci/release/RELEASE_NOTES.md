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

**Changes since 0.312c**
- **Cold you can see.**
  - **Breath:** Henry's breath steams at his mouth in the cold, faster and stronger when he is out of breath, and drifts with the wind.
  - **Rime:** his clothes, hat, pack and the gear on it frost over outdoors. He starts the game frosted and thaws gradually by the stove or in a warm room. The rime is saved.
  - **Face:** cheeks and the nose tip redden in the cold, and rime settles on the brows.
- **Stamina:**
  - breath comes back sooner and faster when standing;
  - an emptied tank keeps Henry winded until he recovers, with no sprint stutter;
  - the run tapers into a jog;
  - the cursor arcs now show the tank while he catches his breath.
- **Road flare:** a new model, and the flare is now an editable scene.
- **Stove:** the stove and its logs are now editable scenes, with the same look.
- **Hints:** X puts away and G drops a held item, and the bedroll takes F or C. Flare readouts are localised.
- **LOW graphics:** no vegetation shadows and one sun shadow split.
- **For testers:** F9 route recording and the F10 report, also written automatically after a crashed session.
