# Reality Library validation

Status: **pass**

## Errors

- none

## Warnings (real-world data issues; source geometry left untouched)

- **extends_far_beyond_extent**: 18
  - kw:admin:overture:85a07df3-0c05-44ca-a7e7-16a6603427ae (admin_areas) bounds [304996, 2712494, 575015, 2854120]
  - kw:admin:overture:e1a6fdec-5613-423f-8911-03963861a164 (admin_areas) bounds [298804, 2698414, 585531, 2854120]
  - kw:admin:usgs_gu:ebf7e37b-1b26-4033-85a4-4209585e9387 (admin_areas) bounds [286493, 2698414, 582124, 2854137]
  - kw:admin:usgs_gu:{991c8996-d988-4175-a968-f48392930aa7} (admin_areas) bounds [422536, 2718524, 472336, 2739352]
  - kw:admin:usgs_gu:{c6a182ee-63f9-49e3-b0a1-5c81e3e8ad36} (admin_areas) bounds [300702, 2717128, 423494, 2735826]
  - kw:admin:usgs_gu:{e3b72fab-23c9-46e4-a6e5-7b786c26a238} (admin_areas) bounds [422536, 2718523, 472336, 2739351]
- **building_in_water**: 53
  - kw:building:osm:w1158807119 (building/shelter) local=(-3920,818)
  - kw:building:osm:w1158807120 (building/shed) local=(-3877,827)
  - kw:building:osm:w1158807121 (building/None) local=(-3868,828)
  - kw:building:osm:w1158807124 (building/None) local=(-3889,829)
  - kw:building:osm:w1158831718 (building/None) local=(-2958,222)
  - kw:building:osm:w116823616 (building/None) local=(2529,-2003)
- **overlapping_buildings**: 6
  - kw:building:osm:r7272605 ~ kw:building:osm:w495352760
  - kw:building:osm:r8408405 ~ kw:building:osm:w543603597
  - kw:building:osm:r8408405 ~ kw:building:osm:w543603596
  - kw:building:osm:w524088621 ~ kw:building:osm:w524088623
  - kw:building:osm:w524088621 ~ kw:building:osm:w524088624
  - kw:building:osm:w525234579 ~ kw:building:osm:w88159279
- **identical_geometry**: 3
  - addresses: 333 hashes shared by >1 feature
  - land_use: 1 hashes shared by >1 feature
  - places: 294 hashes shared by >1 feature
- **pier_detached_from_coast**: 137
  - kw:coastal:osm:w1158807126 subclass=floating
  - kw:coastal:osm:w1158807127 subclass=floating
  - kw:coastal:osm:w1158807128 subclass=floating
  - kw:coastal:osm:w1158807131 subclass=floating
  - kw:coastal:osm:w1158831719 subclass=floating
  - kw:coastal:osm:w1158831720 subclass=floating
