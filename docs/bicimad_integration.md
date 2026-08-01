# Integración pendiente con BiciMAD

La integración real todavía no está implementada. `RealBicimadRepository` existe solo como marcador y lanza un error controlado.

Antes de conectar la app con servicios reales falta descubrir, validar y documentar:

1. Petición real de inicio de sesión.
2. Formato de credenciales.
3. Respuesta de autenticación.
4. Identificador estable del usuario.
5. Access token.
6. Refresh token.
7. Caducidad.
8. Endpoint de renovación.
9. Endpoint de historial.
10. Paginación.
11. Campos reales de cada viaje.

No se deben inventar URLs, endpoints, cabeceras, tokens ni formatos de respuesta. Tampoco se deben guardar credenciales reales ni incluir secretos en el repositorio.
