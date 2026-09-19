# Publicar una APK en GitHub Releases

Procedimiento para generar y publicar una nueva version de BiciMAD GP.

## 1. Comprobar los cambios

Desde la raiz del repositorio:

```powershell
git status
flutter analyze
flutter test
```

No publiques `local_secrets.json`, `android/key.properties` ni el keystore.

## 2. Actualizar la version

Edita `pubspec.yaml` y cambia `version` siguiendo versionado semantico:

```yaml
version: 1.1.0+2
```

- Incrementa la version tras cambios funcionales.
- Incrementa tambien el numero posterior a `+` en cada APK publicada.
- No reutilices el mismo numero de version para otra APK.

## 3. Ajustar la compatibilidad, si procede

Edita `update_policy.json` solo si una version anterior deja de ser compatible
con el backend, la base de datos o el formato de datos:

```json
{
  "minimumSupportedVersion": "1.1.0"
}
```

No aumentes este valor solo porque exista una release nueva. Las versiones
compatibles se actualizaran de forma voluntaria y no quedaran bloqueadas.

## 4. Generar la APK firmada

Usa la configuracion local, sin pegar secretos en la terminal ni en GitHub:

```powershell
flutter pub get
flutter build apk --release --dart-define-from-file=local_secrets.json
```

La APK resultante es:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Opcionalmente, calcula su hash para conservar una referencia local:

```powershell
Get-FileHash build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256
```

## 5. Crear la GitHub Release

En GitHub:

1. Haz commit y push de los cambios, incluido el nuevo `pubspec.yaml`.
2. Abre el repositorio `pabloruizfv/bicimad-gp`.
3. Entra en **Releases** y pulsa **Draft a new release**.
4. Crea un tag nuevo, por ejemplo `v1.1.0`.
5. Selecciona la rama `main`.
6. Escribe las notas de la version.
7. Adjunta `app-release.apk`.
8. Publica la release.

El actualizador integrado consulta la release mas reciente y busca el primer
asset con extension `.apk`.

## 6. Comprobar la instalacion

Instala la APK en un dispositivo de prueba. Android puede pedir permiso para
instalar aplicaciones desconocidas y siempre requiere confirmacion del usuario.

Comprueba:

- que la APK se instala sobre la version anterior;
- que el login y la sincronizacion siguen funcionando;
- que la release es publica y el asset se puede descargar;
- que `update_policy.json` se puede consultar desde `main`.

## 7. Probar una actualizacion obligatoria

La APK publicada debe contener ya el actualizador. Para probarlo:

1. Publica una version posterior con el actualizador.
2. Cambia temporalmente `minimumSupportedVersion` a una version superior a la instalada.
3. Haz commit y push de `update_policy.json`.
4. Abre la app instalada y comprueba la pantalla de actualizacion.
5. Restaura el valor correcto y vuelve a hacer commit y push.

No dejes el valor de prueba en `main`.

## 8. Regla de seguridad

La APK distribuida puede contener claves publicables necesarias para la app,
pero nunca debe incluir `service_role`, contrasenas, keystores ni
`local_secrets.json`. La clave de firma debe conservarse siempre para que las
actualizaciones se puedan instalar sobre versiones anteriores.
