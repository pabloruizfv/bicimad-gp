# Ingesta del histórico Open Data

Genera el modelo empírico por ruta dirigida utilizado por Flutter:

```powershell
python tools/opendata_ingest/build_legacy_route_models.py `
  --input opendata `
  --output assets/data/legacy_route_models.sqlite
```

## Formatos admitidos

- Movimientos JSON legacy directos o dentro de ZIP (2017-2021).
- Viajes CSV directos o dentro de ZIP (2021 en adelante).
- Catálogos de estaciones JSON directos, ZIP o RAR.
- CSV separados por `;` o `,`, incluido el export mixto de octubre de 2021.
- Catálogos JSON NDJSON y exportaciones antiguas con formato Mongo `NumberInt`.

Los RAR se leen con `tar`, disponible en Windows moderno. Si un RAR no se
puede abrir, el proceso falla en lugar de omitir silenciosamente el catálogo.

## Deduplicación y estaciones

Se selecciona una fuente de viajes por mes. Si coinciden JSON legacy y CSV,
se prefiere el CSV; si una publicación está repetida directa y comprimida, se
prefiere la directa. Dentro de cada fuente se deduplica por `idTrip` o `_id`
cuando existe.

La ruta se identifica con el código público de estación, conservando sufijos
como `1a` y `1b`. Para los movimientos legacy, que solo contienen IDs internos,
se construye una equivalencia usando todos los catálogos disponibles. Un ID
interno solo se acepta si siempre corresponde a un único código público; las
equivalencias ambiguas o ausentes se rechazan y contabilizan.

El SQLite no contiene viajes individuales. Guarda únicamente estaciones,
metadatos de generación e histogramas agregados por ruta dirigida.
