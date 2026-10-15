# Developer Diorama Map

The developer map is a debug-only live second camera over the production world.
It removes itself from release builds and does not own gameplay or streaming
state.

## Placement and camera

- Upper-left corner.
- 500 x 320 px panel with a 20 px screen margin.
- Perspective camera, 50 degree FOV, fixed 90 m height (about 160 x 100 m round Henry). Its own environment has no fog: the world's depth fog is opaque at 100 m, the camera's distance to Henry. It leaves out the snow contact and screen-pass layers.
- 64 degree downward pitch with a 12 degree yaw offset. The trapezoid comes from
  the real perspective camera; the viewport texture is not distorted.

The map is follow-only. Hoarbound's normal TPS scene has no free mouse cursor,
so free-pan and recenter controls are deliberately absent.

World exposes `enable_runtime_dev_map` under Developer tools. It defaults to
false. When true, physical M (`toggle_dev_map`) shows/hides the map at runtime.
When false, the same M edge is ignored and the map stays hidden.

The gold dot marks Henry.

## Map-only labels

The frozen Key West OSM snapshot already carries building addresses and named
roads. ChunkedCityMassing.get_map_label_entries() exposes a bounded local
selection around Henry:

- nearest house numbers render in warm amber above their buildings;
- nearest unique street names render in pale text above the road surface;
- labels refresh as Henry moves and are capped to avoid visual clutter.

The labels use render layer 20. The diorama camera sees that layer; the TPS
camera explicitly masks it out while the debug map exists. no_depth_test keeps
the text readable above roofs and streets without changing production geometry.

The SubViewport shares the parent World3D, so terrain, weather, snow, city
streaming and live world changes are the same objects the TPS camera sees.

## Preview

tools/runtime/capture_dev_diorama_map.gd captures one full-screen placement
frame and map-only frames before and after Henry moves. The existing checks.yml
dev-map-preview job uploads those PNGs without invoking the Key West GIS or
Overture build pipeline.
