Pre-release for external smoke testing: **not a finished build**.

**Install**
- Windows: unzip the whole archive and run `Hoarbound.exe`. Keep `data_Hoarbound_windows_x86_64` beside it.
- Linux: unzip and run `./Hoarbound.x86_64`.
- Graphics default to LOW. MEDIUM and HIGH are in the settings menu.
- Logs are written to `logs/` beside the executable. Please send the newest `hoarbound_*.log` with your report.

**Known limitations**
- OPEN: on some GPUs (seen on Intel HD 620) the snow surface around Henry visibly shifts in height as he walks, and a square boundary can be seen. It does not reproduce on the CI/dev renderer and is under investigation. This build does not fix it.
- Low frame rates on integrated GPUs: about 9-11 FPS on LOW on an HD 620.

**Changes since 0.312b**
- The .NET assemblies are back in both archives. 0.312 and 0.312b failed to start with ".NET assemblies not found".
- The default graphics quality is LOW again.
