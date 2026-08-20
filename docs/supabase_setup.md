# Supabase social MVP

Esta integracion usa Supabase Auth con OTP por correo y la clave publicable del
proyecto. Flutter no utiliza `service_role` ni ninguna clave secreta de backend.

## 1. Preparar la configuracion local

```powershell
Copy-Item local_secrets.example.json local_secrets.json
```

Completa localmente `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` y
`SUPABASE_PROJECT_REF`, ademas de la configuracion de BiciMAD. No compartas este
archivo. Los valores de `--dart-define-from-file` se incorporan a la aplicacion
compilada y este mecanismo es solo para desarrollo.

## 2. Instalar e iniciar sesion en Supabase CLI

```powershell
npm install --save-dev supabase
npx supabase login
```

La CLI solicita el token de administracion localmente. No lo guardes en el
repositorio ni lo pases como argumento del comando.

## 3. Vincular el proyecto y aplicar migraciones

Ejecuta desde la raiz:

```powershell
npx supabase link --project-ref <PROJECT_REF>
npx supabase db push
```

Sustituye `<PROJECT_REF>` localmente. Revisa la migracion antes de confirmar. No
uses `supabase db reset --linked` contra el proyecto remoto.

## 4. Configurar Custom SMTP y las plantillas OTP

Este proyecto usa **Custom SMTP**. Configuralo en **Project Settings >
Authentication > SMTP Settings**. Los usuarios de la app no son miembros del
equipo de Supabase y no deben recibir ni aceptar invitaciones a la organizacion.

En **Authentication > Email Templates**, configura tanto **Confirm signup**
como **Magic link or OTP** para que incluyan `{{ .Token }}`. La app siempre pide
ese codigo y lo verifica mediante Supabase Auth; no depende de enlaces ni de
`{{ .ConfirmationURL }}`. El correo **Confirm signup** corresponde al primer
acceso de un usuario nuevo, no a una invitacion al equipo del proyecto.

El flujo social es unico:

1. Usuario nuevo: login MPass, una llamada a `signInWithOtp`, un OTP y
   onboarding obligatorio.
2. Usuario existente en otro movil: login MPass, una llamada a
   `signInWithOtp`, un OTP y recuperacion del perfil e historico.
3. Sesion Supabase vigente y del mismo correo MPass: acceso directo, sin envio
   de correo.

No hay un segundo flujo de alta ni un envio adicional automatico. La pantalla
de verificacion solo verifica el codigo recibido; si el envio inicial falla, el
boton **Reintentar** inicia un nuevo intento explicito y protegido contra dobles
pulsaciones.

## 5. Probar con dos cuentas

```powershell
flutter pub get
flutter run -d <DEVICE_ID> --dart-define-from-file=local_secrets.json
```

1. Inicia MPass con la primera cuenta y verifica el unico OTP recibido en ese
   mismo correo.
2. Crea un perfil visible y sincroniza los viajes.
3. Cierra ambas sesiones desde Ajustes.
4. Repite con una segunda cuenta y otro `@usuario`.
5. Comprueba el follow inmediato a un perfil visible y la solicitud pendiente a
   uno oculto.
6. Comprueba aceptar, rechazar, cancelar, dejar de seguir y eliminar seguidor.
7. Confirma que una cuenta nunca puede consultar viajes detallados de la otra.
8. En otro Android, comprueba que se recupera primero el historico de la nube y
   despues se incorporan los viajes recientes de MPass.
9. Con una sesion Supabase vigente, reinicia la app y confirma que accede sin
   enviar otro correo.

Los cambios del archivo de configuracion requieren detener y recompilar. Hot
reload no actualiza los valores de `String.fromEnvironment`.
