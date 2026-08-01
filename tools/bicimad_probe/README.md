# BiciMAD Probe

Herramientas locales y separadas de Flutter para estudiar capturas propias y hacer una prueba de lectura de viajes con credenciales introducidas manualmente.

No implementan login, no modifican la app oficial, no desactivan certificate pinning y no intentan eludir controles de integridad. No guardes credenciales, tokens, HAR reales ni respuestas crudas en el repositorio.

## Descarga local de viajes

`fetch_trips.py` hace una unica peticion de solo lectura:

```text
GET https://apiemtpay.emtmadrid.es/v2/bicimad/trips/
```

El script pide localmente:

- `accessToken`, oculto con `getpass`
- `email`
- `userId`
- `nif`
- `deviceId`
- `deviceModel`

Usa `userId` tambien como `session`. No guarda esos valores, no los imprime y no vuelca cabeceras completas.

Ejecutar desde la raiz del repositorio:

```powershell
py .\tools\bicimad_probe\fetch_trips.py
```

Si la peticion funciona, solo se escribe:

```text
tools/bicimad_probe/private/trips_normalized.json
```

No se guarda la respuesta sin procesar.

## Descarga con login MPass

`fetch_trips_with_login.py` realiza, en una sola ejecucion, estas tres llamadas de solo lectura:

1. Login MPass.
2. Consulta de `userdata` para obtener exclusivamente `data.DS_DN`.
3. Consulta de viajes.

Ejecutar desde la raiz del repositorio:

```powershell
python .\tools\bicimad_probe\fetch_trips_with_login.py
```

El programa pedira interactivamente:

- Email.
- Contraseña, oculta con `getpass`.
- `passKey`, oculta con `getpass`.
- `X-ClientId`, oculto con `getpass`.
- Device ID, oculto con `getpass`.
- Device model visible, con valor predeterminado `Samsung SM-A127F`.
- Version de Android, con valor predeterminado `13`.

`passKey` y `X-ClientId` deben obtenerse de una captura propia y legitima. No deben compartirse, publicarse, registrarse ni incluirse en Git. Usa una contraseña actual y nunca una contraseña que haya sido expuesta.

Este flujo es experimental y puede cambiar si MPass o BiciMAD modifican su API. Solo debe utilizarse para consultar los viajes de la cuenta propia. No implementa reservas, desbloqueos, pagos ni operaciones de escritura.

Si funciona, solo se escribe:

```text
tools/bicimad_probe/private/trips_normalized.json
```

La respuesta cruda, el access token, el id de usuario, el NIF, el device ID, `passKey`, `X-ClientId` y la contraseña no se guardan ni se imprimen.

## Normalizacion

Por cada viaje se conservan solo estos campos:

- `external_id`
- `origin_station_number`
- `origin_station_name`
- `destination_station_number`
- `destination_station_name`
- `started_at`
- `ended_at`
- `duration_minutes`
- `duration_text`

Se descartan datos personales, financieros, dispositivo, bicicleta, coordenadas y penalizaciones.

## Flujo HAR previo

Guarda el HAR original solo en `tools/bicimad_probe/private/`. Esa carpeta esta ignorada por Git salvo `.gitkeep`.

Sanitiza la captura:

```powershell
py .\tools\bicimad_probe\sanitize_har.py `
  .\tools\bicimad_probe\private\capture.har `
  .\tools\bicimad_probe\private\capture.sanitized.har
```

Analiza solo el HAR sanitizado:

```powershell
py .\tools\bicimad_probe\analyze_har.py `
  .\tools\bicimad_probe\private\capture.sanitized.har
```

## Pruebas

```powershell
py -m unittest discover .\tools\bicimad_probe\tests
```
