# bicimad GP

Prototipo Flutter para importar viajes propios de BiciMAD, conservar el
historico local y participar en una comunidad identificada mediante Supabase
Auth.

## Licencia

El código propio de este repositorio se distribuye bajo
[PolyForm Noncommercial 1.0.0](LICENSE). Permite uso, estudio, modificación y
redistribución con fines no comerciales. Los usos comerciales requieren una
autorización o licencia adicional del titular de los derechos.

Esta licencia no concede derechos sobre logos, avatares, iconos, mapas, datos,
servicios externos ni otros recursos de terceros incluidos o utilizados por la
aplicación. Consulta sus licencias y condiciones por separado.

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
- Pantallas Mi Perfil, Viajes, Rankings, Comunidad y Ajustes.
- Insignias, rankings de Comunidad y comparaciones Cara a cara.
- Historico Open Data agregado por ruta y catalogo local de estaciones.
- Cotas de terreno precalculadas por estacion y malla local para resolver
  estaciones nuevas sin conexion; los desniveles aun no se muestran en la UI.

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

La malla de elevaciones `assets/data/station_terrain_10m.i16.gz` es una obra
derivada del modelo [MDT05 del IGN/CNIG](https://centrodedescargas.cnig.es/CentroDescargas/modelo-digital-terreno-mdt05-primera-cobertura),
CC BY 4.0, atribucion IGN/CNIG. El metodo de generacion y sus limites se
documentan en [tools/station_elevation/README.md](tools/station_elevation/README.md).

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

### Firma de produccion Android

Las compilaciones `release` requieren una firma de produccion y fallan de forma
intencionada si falta `android/key.properties`. Ese archivo y el keystore
`android/app/bicimad-gp-release.jks` estan ignorados por Git. Deben conservarse
fuera del repositorio y respaldarse juntos: perder el keystore impide publicar
actualizaciones sobre la misma instalacion de Android.

Para generar una APK firmada localmente:

```powershell
flutter build apk --release --dart-define-from-file=local_secrets.json
```

El resultado queda en
`build/app/outputs/flutter-apk/app-release.apk`. No compartas `key.properties`
ni el keystore; solo distribuye la APK.

Las versiones futuras consultan `update_policy.json` y la GitHub Release mas
reciente. Si existe una version nueva compatible, la app ofrece actualizar de
forma opcional. `minimumSupportedVersion` solo debe aumentarse cuando una
version antigua deje de ser compatible con el backend o el esquema; en ese
caso la actualizacion pasa a ser obligatoria.

El procedimiento completo para generar y publicar una APK esta en
[`docs/publishing_github_release.md`](docs/publishing_github_release.md).

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
python tools/security/check_publication.py --history
```

## Seguridad y limitaciones

No incluyas credenciales, tokens ni datos personales en Git o logs. Flutter usa
solo la clave publicable de Supabase; nunca `service_role`. Los viajes detallados
son privados.

Consulta [SECURITY.md](SECURITY.md) y la
[revision previa a publicacion](docs/publication_security_review.md) antes de
abrir el repositorio o distribuir compilados. Las claves de integracion no se
distribuyen con el codigo: cada instalacion de desarrollo necesita configuracion
legitima propia. Publicar el codigo no autoriza el uso de servicios de terceros.

No se incluyen feed, comentarios, likes, recomendaciones,
notificaciones push, reservas, desbloqueos ni pagos. El Open Data se mantiene
separado de la comunidad.
