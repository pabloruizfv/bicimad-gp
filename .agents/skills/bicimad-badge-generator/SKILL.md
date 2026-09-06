---
name: bicimad-badge-generator
description: Crear y actualizar emblemas SVG consistentes para el sistema de logros de BiciMAD Social a partir de las bases oficiales de grafito, bronce, plata y oro. Usar cuando se solicite diseñar una categoría de badges, generar sus niveles, incorporar un pictograma central, modificar una familia de logros o validar SVG de badges destinados a Flutter.
---

# BiciMAD Social - Badge Generator

## Objetivo

Crear emblemas SVG consistentes para el sistema de logros de BiciMAD Social usando siempre una de las cuatro bases oficiales incluidas en `assets/bases/` dentro de este skill.

No rediseñar la medalla base para cada logro. Reutilizar exactamente las plantillas para conservar la identidad visual de la colección.

## Bases oficiales

Usar una de estas plantillas:

- `assets/bases/badge_base_graphite.svg`
- `assets/bases/badge_base_bronze.svg`
- `assets/bases/badge_base_silver.svg`
- `assets/bases/badge_base_gold.svg`

Aplicar por defecto esta escala de niveles:

1. grafito
2. bronce
3. plata
4. oro

Si una categoría tiene menos de cuatro niveles, asignar los metales según sus umbrales. No inventar un quinto metal salvo petición expresa.

## Regla principal

Para crear un badge nuevo:

1. Copiar la base metálica correspondiente.
2. Conservar intacta toda la estructura exterior de la medalla.
3. Modificar únicamente el contenido del grupo `<g id="badge-content"></g>`.
4. Insertar dentro de ese grupo el pictograma específico del logro.
5. Mantener el `viewBox`, dimensiones, anillos, bordes, cinta, sombras y gradientes originales.
6. No alterar el tono del metal para diferenciar logros de la misma categoría.

No modificar las cuatro bases durante la creación normal de badges. Si se solicita cambiar una paleta metálica, actualizar primero la plantilla correspondiente y regenerar desde ella las variantes afectadas.

## Consistencia entre niveles

Usar exactamente el mismo `badge-content` en todos los niveles de una categoría. La única diferencia visual debe ser el metal: grafito, bronce, plata u oro.

No añadir estrellas, laureles, números, llamas, coronas, destellos ni adornos para señalar el nivel salvo petición expresa. No escribir dentro del badge umbrales como `1`, `10` o `50`: el nombre y el umbral pertenecen a la interfaz.

## Selección del pictograma

Priorizar pictogramas SVG existentes, reconocibles y con licencia compatible antes de dibujar uno nuevo. Preferir, en este orden:

1. Tabler Icons
2. Material Symbols
3. Heroicons
4. Otro recurso SVG abierto y claramente identificable

Al reutilizar un recurso externo:

- Conservar en el SVG final un comentario breve con el nombre del icono y su procedencia.
- Respetar su licencia.
- Incorporar la geometría SVG directamente, sin código remoto ni referencias externas.
- Adaptar escala, posición, grosor y color solo lo necesario para integrarlo.
- Rechazar iconos con licencia dudosa.

## Estilo del pictograma

Hacer que el icono central:

- Sea simple y reconocible a tamaño pequeño.
- Quede visualmente centrado dentro del anillo.
- Tenga trazos suficientemente gruesos para móvil.
- Evite detalles finos que desaparezcan al reducirlo.
- Use preferentemente azul BiciMAD `#244E78`.
- Use blanco `#FFFFFF` para huecos o contraste cuando sea necesario.
- No tenga fondo rectangular adicional.
- No sobresalga ni quede cortado por el área central.

Como referencia, representar los pit stops mediante un surtidor reconocible con cuerpo azul y hueco superior blanco.

## Nombres y destino

Usar nombres estables, descriptivos, en minúsculas y con guiones bajos:

```text
badge_<categoria>_<umbral>_<metal>.svg
```

Ejemplos:

```text
badge_pit_stop_1_graphite.svg
badge_pit_stop_10_bronze.svg
badge_pit_stop_50_silver.svg
badge_pit_stop_100_gold.svg
```

Si el umbral no es numérico, usar un identificador semántico corto.

Mantener las bases dentro de este skill. Guardar los SVG finales que cargará Flutter en `<raíz-del-proyecto>/assets/badges/`. Agrupar por categoría cuando haya muchos:

```text
assets/badges/pit_stops/
assets/badges/trips/
assets/badges/stations/
assets/badges/bikes/
```

No configurar Flutter para cargar las plantillas vacías del skill salvo razón funcional explícita. Si la nueva ruta de salida no está cubierta por `pubspec.yaml`, actualizarlo.

## Flujo para una categoría nueva

1. Identificar el concepto, los umbrales y los metales.
2. Buscar o reutilizar un único pictograma SVG representativo y de licencia compatible.
3. Generar primero una variante y comprobarla a tamaño móvil.
4. Ajustar únicamente el contenido de `badge-content` hasta centrarlo y hacerlo legible.
5. Replicar exactamente ese mismo contenido en las demás bases metálicas.
6. Cambiar únicamente la base entre niveles.
7. Guardar los resultados bajo la categoría correspondiente en `assets/badges/`.
8. Verificar que los niveles conservan idéntica geometría central.
9. Comprobar que no se introdujo texto, números o decoración no solicitada.

## Prohibiciones

- No redibujar la medalla desde cero.
- No cambiar la cinta entre categorías.
- No añadir decoración de nivel aparte del metal.
- No usar un icono distinto para cada umbral de una categoría.
- No rasterizar a PNG como fuente principal.
- No incrustar imágenes base64 dentro del SVG.
- No añadir texto sin solicitud expresa.
- No modificar las bases durante la generación normal.
- No inventar un pictograma cuando exista un SVG abierto adecuado.

## Validación final

Antes de terminar:

1. Comprobar que cada SVG es XML válido.
2. Comprobar que conserva `viewBox="0 0 512 512"`.
3. Comprobar que existe exactamente un grupo con `id="badge-content"`.
4. Inspeccionar el resultado a 512 px y a 20-24 px para confirmar que nada queda cortado y que el símbolo sigue siendo legible.
5. Comparar todos los niveles y confirmar que `badge-content` es idéntico.
6. Confirmar que la única diferencia entre niveles es el metal, salvo instrucción contraria.
7. Confirmar que no hay referencias remotas, imágenes base64, texto ni adornos imprevistos.
8. Informar de todos los archivos creados o modificados.

## Ejemplo: pit stops

Para una familia de pit stops:

- Usar un surtidor de gasolina como metáfora visual.
- Reutilizar exactamente el mismo surtidor en todos los niveles.
- Usar cuerpo azul `#244E78` y blanco `#FFFFFF` en el hueco superior.
- Cambiar únicamente grafito, bronce, plata u oro entre niveles.
- No añadir estrellas.
