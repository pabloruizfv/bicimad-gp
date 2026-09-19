# Revision previa a GitHub (2026-09-06)

## Alcance

Revision estatica del repositorio y su historial local: configuracion, archivos
publicables, login y persistencia, transportes/logs, probes, esquema SQL,
permisos/RLS y superficies sociales de lectura. Pruebas de regresion de Flutter
y Python. No se han consultado cuentas reales, desplegado cambios, modificado
usuarios ni reescrito commits. Los recursos graficos y sus licencias quedan
expresamente fuera de esta revision, por decision del propietario.

No es una certificacion de seguridad: no se ha verificado el estado remoto de
Supabase, auditado exhaustivamente dependencias/CVE ni ejecutado un pentest.

## Hallazgos y cambios

### Permisos de funciones internas: alta prioridad

Las migraciones revocaban `PUBLIC`, pero no las concesiones directas a los
roles de API. En proyectos con esos permisos por defecto, una funcion como
`get_best_route_times_for_users(uuid[])` podria invocarse directamente con
otros UUID y devolver rutas/fechas sin pasar por los filtros de las RPC publicas.
El codigo demuestra la falta de revocacion; NO se ha probado que el proyecto
remoto conserve ese permiso actualmente.

La nueva migracion `20260906120000_harden_api_privileges.sql` elimina todos los
permisos de `PUBLIC`, `anon` y `authenticated` sobre las funciones de la app y
restaura EXECUTE solo para las RPC que Flutter utiliza. Incluye funciones
renombradas de logros. Tambien elimina privilegios sobrantes en tablas y la
secuencia de trips, y restaura las lecturas necesarias sujetas a RLS.
No cambia cuerpos de funciones, filas, formulas, relaciones ni politicas RLS.
No toca funciones ajenas a esta app ni permisos de `service_role`.

Fundamento: [Supabase: securing your API](https://supabase.com/docs/guides/api/securing-your-api)
y [database functions](https://supabase.com/docs/guides/database/functions).

### Datos expuestos en diagnosticos

- Se elimina el identificador de telefono del mensaje de configuracion CARTO.
- El probe de descarga ya no imprime fecha/estaciones del ultimo viaje ni
  descripciones arbitrarias del servidor. Las exportaciones privadas no cambian.
- Los codigos MPass en consola se limitan al formato numerico de dos caracteres.
- Los diagnosticos MPass de Flutter solo se emiten en debug.
- Las vistas genericas no muestran `Exception.toString()` de SDK/SQLite/red;
  conservan mensajes propios de la app y usan un mensaje neutro para el resto.
- Flutter rechaza claves administrativas Supabase al arrancar, sin imprimirlas.
- Ambos mapas comparten `CartoTileLayer`: `silenceExceptions` evita que los
  errores de descarga de `flutter_map` impriman la URL con la clave CARTO.
  Una tesela fallida queda transparente y se expulsa de la cache de imagenes,
  siguiendo la implementacion de la libreria; las teselas correctas no cambian.

### Publicacion accidental

Se amplian exclusiones de compilados, material de firma y bases personales,
con excepcion explicita para el SQLite agregado Open Data. Se incorpora un
checker offline con pruebas, modo index y modo historial, y un workflow de
solo lectura, sin credenciales de servicios ni acciones de despliegue.

El analizador excluye la carpeta privada de investigacion. En esta maquina,
`dart format .` tropieza con rutas largas de artefactos decompilados; se puede
usar `dart format lib test` sin borrar ni modificar ese material.

## Datos revisados

No se encontraron coincidencias de valores actuales de `local_secrets.json`
ni patrones comunes de tokens reales en el codigo publicable/historial revisado.
Los tests usan datos ficticios. Esto no descarta secretos en formatos no cubiertos.

La SQLite versionada contiene `metadata`, `stations` y `route_models`, no
tablas de viajes personales. Los APK oficiales/capturas/diagnosticos privados
no estan versionados, salvo el archivo vacio `.gitkeep`.

Persisten avisos del historial: correo personal en metadatos de ocho commits
y el antiguo identificador del dispositivo en un blob. No se imprimen sus valores.

## Aplicacion manual de SQL

En el proyecto ya vinculado, revisar las migraciones pendientes y aplicar:

```powershell
npx supabase db push --dry-run
npx supabase db push
```

`db push` aplica TODAS las migraciones pendientes, no solo la nueva. Comprobar
el listado antes de confirmar. Esta revision no ha ejecutado ninguna accion remota.

Despues ejecutar el contenido de `supabase/tests/api_privileges.sql` en el SQL
Editor con permisos administrativos. Es una comprobacion de ACL sin leer filas
privadas ni modificar datos. Con una instancia local tambien puede ejecutarse
mediante `psql -v ON_ERROR_STOP=1 -f supabase/tests/api_privileges.sql` usando una
conexion local configurada fuera del repositorio. No poner passwords en la CLI.

Las pruebas Dart comprueban la cobertura de la migracion, no sustituyen la
ejecucion SQL. No habia PostgreSQL/Docker disponibles para ejecutarla localmente.
Probar despues login, carga de perfil, follows, sincronizacion, logros, rankings
y Cara a cara con dos cuentas propias (incluyendo perfil oculto/no seguido).

## Decisiones pendientes del propietario

1. Historial: aceptar la publicacion de metadatos personales o autorizar una
   limpieza del correo y del antiguo serial antes del primer push publico.
   Cambiar la configuracion de Git o usar `.mailmap` no borra los objetos antiguos.
2. Licencia de assets: el codigo propio ya declara PolyForm Noncommercial
   1.0.0 en `LICENSE`; sigue siendo necesario revisar y documentar por separado
   la licencia de logos, avatares, iconos, mapas y datos de terceros.
3. Distribucion de APK: el release sigue firmado con la clave debug, tal como
   estaba. Cambiarla ahora puede impedir actualizar instalaciones existentes
   sin reinstalar. Requiere plan de firma/distribucion, no un cambio silencioso.
4. Credenciales tecnicas: decidir alcance de distribucion de binarios y
   autorizacion de la integracion MPass/CARTO. Publicar el fuente no publica la
   configuracion, pero un binario puede contenerla. No se han rotado claves.

## Limites de la arquitectura actual que no se han cambiado

- Los viajes se suben desde un cliente controlable por el usuario. RLS impide
  escribir en cuentas ajenas, pero no certifica que un tiempo propio sea real.
  Un sistema antitrampas requeriria validacion independiente y otro alcance.
- Quien puede leer logros conforme a RLS puede consultar tambien `unlocked_at`
  en `user_achievements`, aunque la UI ajena no muestre esa fecha. Si se quiere
  que sea privada en servidor, hace falta una proyeccion/RPC que oculte ese campo
  y adaptar sus consumidores. No se ha cambiado ese contrato en esta revision.
- No se ha alterado el backup del dispositivo ni el almacenamiento de la sesion
  Supabase que mantiene la libreria, ni las reglas de logout ya acordadas.
- El checker no revisa legitimidad/licencias de assets ni garantiza ausencia
  de secretos desconocidos. La comprobacion humana previa al primer push sigue
  siendo necesaria.

## GitHub

Antes de hacer publico: habilitar reporte privado de vulnerabilidades,
secret scanning/push protection donde esten disponibles y proteger la rama
principal con revision y el check `Publication safety`. No guardar
`local_secrets.json` en Actions ni publicar compilados desde este workflow.
