Pre-release for external smoke testing: **not a finished build**.

**Install**
- Windows: unzip the whole archive and run `Hoarbound.exe`. Keep `data_Hoarbound_windows_x86_64` beside it.
- Linux: unzip and run `./Hoarbound.x86_64`.
- Graphics default to LOW. MEDIUM and HIGH are in the settings menu.
- Logs are written to `logs/` beside the executable. Please send the newest `hoarbound_*.log` with your report.

**Known limitations**
- OPEN: the snow surface around Henry visibly shifted in height as he walked, with a square boundary (seen on Intel HD 620). A likely cause is fixed in this build: exported games did not load the baked snow wind field and fell back to a moving snow window, while the editor worked. That fix is checked on the exported pack. It has NOT yet been confirmed on the hardware where the defect was seen, so treat the issue as open and report it if you see it.
- Low frame rates on integrated GPUs: about 9-11 FPS on LOW on an HD 620.

**Changes since 0.312b**
- Exports now load the baked snow wind field (`ResourceLoader.exists` instead of `FileAccess.file_exists` on an imported PNG).
- The .NET assemblies are back in both archives. 0.312 and 0.312b failed to start with ".NET assemblies not found".
- The default graphics quality is LOW again.
