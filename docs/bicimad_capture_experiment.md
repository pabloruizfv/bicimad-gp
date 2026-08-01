# Experimento local de captura BiciMAD

Este experimento debe realizarse solo con tu propia cuenta y tu propio dispositivo. El objetivo es observar operaciones de lectura del historial para preparar una futura integración documentada.

Durante la captura no realices pagos, desbloqueos de bicicletas, modificaciones de cuenta ni ninguna otra acción que cambie estado. Limita la sesión a iniciar sesión, abrir perfil si es necesario y consultar el historial de viajes.

## Archivos locales

Guarda temporalmente el HAR original en:

```text
tools/bicimad_probe/private/
```

Esa carpeta está ignorada por Git salvo `.gitkeep`. El HAR original no debe entrar en Git, no debe copiarse a documentación y no debe mostrarse en logs.

## Sanitizar

Desde la raíz del repositorio:

```powershell
python .\tools\bicimad_probe\sanitize_har.py `
  .\tools\bicimad_probe\private\capture.har `
  .\tools\bicimad_probe\private\capture.sanitized.har
```

Comparte o entrega a otro agente solo el archivo `*.sanitized.har`, nunca el original.

## Analizar

Ejecuta el analizador únicamente sobre el HAR sanitizado:

```powershell
python .\tools\bicimad_probe\analyze_har.py `
  .\tools\bicimad_probe\private\capture.sanitized.har
```

Se generarán:

- `bicimad_probe_report.txt`
- `bicimad_probe_report.json`

Solo se deben compartir el HAR sanitizado y estos informes. Si aparece cualquier dato sensible tras la sanitización, elimina los archivos generados y ajusta el sanitizador antes de continuar.

## Información que necesitamos descubrir

- Petición de login.
- Tipo de autenticación.
- Identificador estable del usuario.
- Access token o cookie de sesión.
- Renovación.
- Endpoint del historial.
- Paginación.
- Estructura de un viaje.

No inventes endpoints, formatos, tokens ni credenciales. La clasificación del analizador es heurística y no es una conclusión definitiva.
