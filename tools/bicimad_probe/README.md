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
