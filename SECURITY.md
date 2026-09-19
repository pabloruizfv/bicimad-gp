# Seguridad

## No publicar informacion privada

No adjuntar passwords, OTP, tokens, cabeceras, respuestas de MPass, bases
personales, capturas HAR, configuracion local ni material de firma a issues,
pull requests o logs de CI. Usar fixtures sinteticos. No subir un ZIP de la
carpeta de trabajo: contiene archivos privados que Git no publica.

`local_secrets.example.json` debe permanecer vacio. `local_secrets.json`,
`tools/bicimad_probe/private/`, compilados y bases personales estan ignorados.
La excepcion SQLite versionada es `assets/data/legacy_route_models.sqlite`,
que contiene modelos agregados Open Data, no el historial personal de la app.

Antes de publicar o preparar un commit:

```powershell
python tools/security/check_publication.py --history
python tools/security/check_publication.py --staged --history
```

La primera orden revisa archivos versionados y nuevos no ignorados; la segunda
revisa el contenido exacto del index. `--history` incluye objetos alcanzables
desde todas las referencias locales, incluso archivos borrados. No incluye
reflogs, objetos inalcanzables ni referencias remotas que no se hayan descargado.
El informe solo muestra categorias y ubicaciones, nunca coincidencias.

El checker detecta artefactos privados, patrones comunes de tokens/claves y
valores de la configuracion local si esta existe. Los avisos de correo o serie
de dispositivo requieren revision humana. No es un detector universal de
secretos: una salida sin errores no demuestra ausencia de datos sensibles.
El workflow `Publication safety` ejecuta el control y pruebas sin secretos.
Es una comprobacion posterior al push, NO evita por si sola la primera filtracion.

## Cliente y servicios

- La contrasena MPass se envia directamente a MPass; no se persiste ni se envia
  a Supabase. La sesion MPass se conserva mediante secure storage.
- Supabase mantiene el flujo email + OTP y la restauracion de sesion existentes.
- Flutter admite la clave publicable o legacy `anon`, nunca `service_role` ni
  una clave secreta. La validacion de arranque es una proteccion contra errores
  de configuracion, no evita que un valor ya compilado sea extraido de una APK.
- `--dart-define` NO cifra los valores. CARTO y las credenciales tecnicas MPass
  deben tratarse como recuperables por quien reciba el binario.
- La privacidad en nube depende de permisos, RLS y comprobaciones `auth.uid()`
  del servidor, nunca de ocultar codigo o de filtrar solo en Flutter.
- La verificacion TLS sigue activa. No introducir bypasses para diagnosticar.
- Los mensajes crudos de excepciones/respuestas no son adecuados para compartir.
  Los probes imprimen conteos/codigos controlados; sus exportaciones siguen
  siendo privadas aunque no contengan passwords.

## Cambios de SQL

Crear siempre una migracion nueva. Para cada funcion, revocar explicitamente
`PUBLIC`, `anon` y `authenticated` y conceder solo el acceso que necesite la app.
Una funcion interna `SECURITY DEFINER` que acepta un UUID no debe quedar
invocable desde el cliente. Revisar tambien implementaciones renombradas.
No asumir que RLS protege el contenido leido por una funcion con privilegios
del propietario.

## Informar de vulnerabilidades

No publicar una reproduccion con datos reales ni abrir un issue publico con
credenciales. El mantenedor debe habilitar un canal privado de reporte en
GitHub antes de publicarlo; mientras no exista, no adjuntar detalles sensibles.
No se promete un plazo de respuesta ni una auditoria independiente.

Si una clave real aparece en Git, revocarla/rotarla en su servicio. Borrarla del
ultimo commit o anadirla a `.gitignore` no borra copias anteriores. La limpieza
del historial requiere una decision del mantenedor y coordinacion con clones.
