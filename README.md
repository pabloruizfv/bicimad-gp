# BiciMAD Social

MVP móvil en Flutter para comparar tiempos de viajes de BiciMAD entre usuarios de una comunidad. Cada ranking corresponde a una pareja ordenada de estaciones: `origen -> destino`. La ruta inversa se trata como un ranking distinto.

## Funcionalidades del MVP

- Acceso simulado con MPass.
- Elección inicial del nombre visible.
- Navegación inferior Material 3 con Viajes, Rankings y Perfil.
- Listado de viajes del usuario actual ordenado por fecha.
- Sincronización simulada con fecha de última sincronización.
- Detalle de viaje con mejor marca personal, posición comunitaria y percentil.
- Ranking completo por pareja de estaciones.
- Compartir resultados con `share_plus`.

## Arquitectura

La app usa una estructura sencilla por capas:

- `lib/app`: configuración de app, tema, router y providers globales.
- `lib/core`: errores y utilidades reutilizables.
- `lib/features/authentication`: sesión MPass simulada y pantalla de acceso.
- `lib/features/trips`: modelos, repositorios, datos simulados y pantallas de viajes.
- `lib/features/rankings`: modelos y servicio puro de ranking.
- `lib/features/profile`: pantalla de perfil.
- `lib/shared/widgets`: widgets reutilizables pequeños.

La lógica competitiva vive en `RankingService` para poder probarla sin UI ni servicios remotos.

## Dependencias principales

- Flutter y Dart.
- `flutter_riverpod` para estado.
- `go_router` para navegación.
- `share_plus` para abrir el menú nativo de compartir.

## Ejecutar la app

```bash
flutter pub get
flutter run
```

Para un dispositivo Android conectado:

```bash
flutter devices
flutter run -d <device-id>
```

## Ejecutar pruebas

```bash
flutter analyze
flutter test
```

## Modo simulado

Toda la app funciona con datos locales definidos en código. El login acepta cualquier usuario no vacío y cualquier contraseña no vacía. La contraseña no se almacena, no se registra y no se usa para llamar a servidores reales.

Los viajes, usuarios y rankings son datos simulados para validar el concepto del producto.

## Limitaciones actuales

No hay integración real con BiciMAD, MPass, Supabase ni backend remoto. Tampoco hay GPS, mapas, amigos, ligas privadas, comentarios, logros, notificaciones, filtros avanzados, meteorología ni detección de viajes anómalos.

## Siguiente paso para integrar BiciMAD

Antes de sustituir `MockBicimadRepository` por `RealBicimadRepository`, hay que descubrir y documentar el flujo real de autenticación e historial de viajes. El detalle pendiente está en `docs/bicimad_integration.md`.

## Seguridad

No incluyas credenciales, tokens, secretos ni datos reales sensibles en el repositorio. No registres contraseñas ni respuestas de autenticación reales.
