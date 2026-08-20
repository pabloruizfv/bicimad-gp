# Supabase Auth OTP probe

Herramienta local y temporal para observar el primer correo enviado por
Supabase Auth a un usuario nuevo. No utiliza MPass, no verifica el OTP y no
accede a perfiles, viajes ni tablas de la base de datos.

Lee `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` desde el
`local_secrets.json` ignorado por Git. Nunca muestra esos valores. Rechaza una
clave con formato de `service_role` o `sb_secret_`.

Ejecutar desde la raíz del proyecto:

```powershell
python tools/supabase_auth_probe/diagnose_new_user_otp.py
```

Introduce un correo de prueba que no esté registrado si quieres observar el
flujo real de alta. El script hace una sola petición `POST /auth/v1/otp` con
`create_user: true`. La petición puede crear el usuario de Supabase Auth, pero
no crea el perfil social de la aplicación.

Después comprueba:

- que llega un único correo;
- que para un usuario nuevo se usa la plantilla **Confirm signup**;
- que el mensaje contiene un código OTP visible;
- que no exige abrir un enlace ni redirige a `localhost`.

El script no guarda el correo, la respuesta ni el código.
