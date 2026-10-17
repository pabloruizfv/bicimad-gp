# Station terrain elevations

`assets/data/station_terrain_10m.i16.gz` is a cropped, approximately 10 m
terrain grid derived from the IGN/CNIG PNOA MDT05 first coverage. The source
is requested from the official WCS in EPSG:25830 and reprojected to a compact
WGS84 grid. The downloaded GeoTIFF tiles are never stored in the repository.

The companion JSON records bounds, resolution, units, NoData value and source.
Its grid checksum versions the elevations cached with the station catalog.
Each sample is a signed little-endian 16-bit decimeter value; `-32768` means
unknown. The Flutter app loads it lazily and uses bilinear interpolation for
new GBFS stations within the covered area. Stations outside it remain unknown.
The shipped station snapshot also contains precomputed elevations; existing
cached catalogs are enriched automatically. Trip elevation profiles represent
net elevation change between station endpoints, not actual accumulated climb.

Supabase also keeps a protected copy of the station elevations so historical
trips and uploads from older clients can receive a net elevation without each
user opening the latest app. The database trigger only fills missing values;
an elevation supplied by the app remains authoritative.

To regenerate after changing the area or source:

```powershell
python -m pip install requests numpy rasterio
python tools/station_elevation/build_elevation_grid.py --build
python -m unittest discover -s tools/station_elevation/tests
```

After updating the station snapshot or terrain grid, generate a **new**
Supabase migration (never overwrite one that has already been applied):

```powershell
python tools/station_elevation/build_server_elevation_migration.py `
  --output supabase/migrations/<timestamp>_server_climbing_elevation_backfill.sql
```

Review the generated SQL and run `npx supabase db push --dry-run` before
deploying it. The migration seeds the internal lookup, backfills only trips
whose `net_elevation_meters` is null, and recalculates achievement progress for
every profile.

Use `--reuse-grid` to revalidate or restamp the bundled grid without another
download.

The script verifies coverage of both the current station snapshot and stations
in `legacy_route_models.sqlite` before replacing the assets. The grid covers
roughly longitude -3.83 to -3.53 and latitude 40.32 to 40.53. Extend those
bounds and the UTM download bounds together if BiciMAD expands beyond them.

Source: [IGN/CNIG MDT05](https://centrodedescargas.cnig.es/CentroDescargas/modelo-digital-terreno-mdt05-primera-cobertura).
Terrain data and derived grid: CC BY 4.0, attribution IGN/CNIG. See the
[IGN data policy](https://www.ign.es/web/politica-datos).
