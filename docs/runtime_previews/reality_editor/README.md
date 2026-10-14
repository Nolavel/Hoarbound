# Reality editor captures

`view_island`, `view_near_727`: `key_west_reality_editor.tscn` with the far overview and detail
chunks around the editor camera (stage 1).

Dock demo, generator `kw_chunk_builder.11`, shot in the real editor (lavapipe, 2026-10-14) by
`addons/reality_editor/capture_demo.gd` with `HOARBOUND_REALITY_EDITOR_CAPTURE=<folder>`;
downscaled to 1280×720.

| Shot | What to look at |
|---|---|
| `dock_1_search` | "907 whitehead" in the Reality dock: 6 hits, the Hemingway Home record (address source, use, height, chunk, asset) |
| `dock_2_framed_after_F` | after Go to and F (Focus Selection, then the mouse wheel out): the house under the selected FocusMarker, detail chunks with static roof snow loaded around it |
| `dock_3_identified_at_camera` | "At camera": the camera's look ray meets the same house, the list narrows to it |

## Go to framing (2026-10-15, Intel HD 620)

Shot by the same harness, now one Go to + F per address with `focus_report.json` (camera distance after F against the
distance at which the building's bounding sphere fills the view).

| Shot | Distance after F | Needed | Framed |
|---|---|---|---|
| `focus_before_907_whitehead` | 7.7 m | 25.9 m | no: F re-centres the orbit and keeps the editor's 4 m distance |
| `focus_before_1009_windsor` (Old Town) | 7.3 m | 13.8 m | no |
| `focus_after_907_whitehead` | 29.6 m | 25.9 m | yes |
| `focus_after_1009_windsor` | 16.0 m | 13.8 m | yes |

Tried first and measured as not working in Godot 4.8-dev6: a bounds-sized mesh under the marker (internal or plain child),
the marker's `gizmo_extents`, and selecting the bounds mesh itself. F still left the camera 4.0 m from the centre.
