# bicimad GP

Prototipo Flutter para importar viajes propios de BiciMAD, conservar el
historico local y participar en una comunidad identificada mediante Supabase
Auth.

## Funcionalidades

- Login MPass y descarga de viajes de la cuenta propia.
- Importacion paginada y acumulativa del historico BiciMAD, con guardado por
  pagina, deduplicacion por `trip_id` y reanudacion tras fallos transitorios.
- Sesion social mediante Custom SMTP y un unico OTP al mismo correo de MPass,
  sin contrasena adicional ni enlaces de confirmacion.
- Perfil con `@usuario` inmutable, nombre publico, avatar y privacidad.
- Busqueda, follows, solicitudes y listas de seguidores y seguidos.
- Copia privada del historico en Supabase y estadisticas sociales agregadas.
- Bicicleta y precio de cada etapa, con agregacion segura en viajes con pit stops.
- Pantallas General, Viajes, Rankings, Comunidad y Ajustes.
- Historico Open Data agregado por ruta y catalogo local de estaciones.

## Arquitectura

- `lib/app`: composicion de providers, router y tema.
- `lib/core`: configuracion, red, almacenamiento y utilidades.
- `lib/features/authentication`: cliente MPass/BiciMAD y sesion local segura.
- `lib/features/trips`: persistencia local, normalizacion y presentacion.
- `lib/features/social`: OTP, perfiles, follows y sincronizacion con Supabase.
- `supabase/migrations`: esquema, RPC, restricciones y politicas RLS.

Las dependencias principales son `flutter_riverpod`, `go_router`, `http`,
`cronet_http`, `flutter_secure_storage`, `sqlite3`, `flutter_map` y
`supabase_flutter`. Los viajes personales se guardan en una SQLite writable
separada de `assets/data/legacy_route_models.sqlite`, que sigue siendo la base
de solo lectura del historico Open Data.

Al abrir una version que todavia tenga `community.localTrips.v1` en secure
storage, la app migra las etapas a SQLite dentro de una transaccion, verifica
los `trip_id` esperados y solo entonces elimina el JSON legacy. La migracion es
idempotente y se reintenta en el siguiente arranque si no puede completarse.

## Configuracion local

`local_secrets.json` no es un almacen seguro. Es configuracion temporal de
desarrollo y sus valores quedan incorporados en la aplicacion compilada. El
archivo esta ignorado por Git y no debe compartirse. Incluye `CARTO_API_KEY`
para autorizar las teselas raster de CARTO.

```powershell
Copy-Item local_secrets.example.json local_secrets.json
flutter pub get
flutter run -d <DEVICE_ID> --dart-define-from-file=local_secrets.json
```

Los cambios en `--dart-define-from-file` requieren detener y recompilar; hot
reload no es suficiente. La pantalla de Configuracion experimental sigue siendo
el fallback local para `passKey` y `X-ClientId`.

Los importes de BiciMAD se conservan como valores decimales, sin convertirlos a
centimos. En un viaje formado por varias etapas, el precio solo se suma cuando
todas las etapas lo incluyen; las bicicletas distintas se mantienen por etapa.

La primera sincronizacion recorre el historico hasta una pagina de menos de 30
elementos. Una vez agotado, las sincronizaciones incrementales empiezan por los
viajes recientes y se detienen tras dos paginas completas consecutivas cuyos
`trip_id` ya eran conocidos. Cada pagina se guarda localmente antes de pedir la
siguiente y se intenta subir a Supabase sin borrar datos anteriores.

## Supabase

Consulta [docs/supabase_setup.md](docs/supabase_setup.md) para instalar e iniciar
sesion en la CLI, vincular el proyecto, aplicar migraciones, configurar la
plantilla OTP, configurar Custom SMTP y probar dos cuentas. Los usuarios de la
app no requieren invitaciones al equipo de Supabase.

## Open Data y estaciones

```powershell
python tools/opendata_ingest/build_legacy_route_models.py --input opendata --output assets/data/legacy_route_models.sqlite
python tools/station_catalog/build_station_catalog_asset.py --output assets/data/station_catalog_snapshot.json
```

El SQLite Open Data contiene solo modelos agregados, no viajes individuales. La
app usa primero el catalogo local de estaciones y lo actualiza en segundo plano.

## Calidad

```powershell
dart format .
flutter analyze
flutter test
```

## Seguridad y limitaciones

No incluyas credenciales, tokens ni datos personales en Git o logs. Flutter usa
solo la clave publicable de Supabase; nunca `service_role`. Los viajes detallados
son privados.

No se incluyen feed, logros, comentarios, likes, recomendaciones,
notificaciones push, reservas, desbloqueos ni pagos. El Open Data se mantiene
separado de la comunidad.
