# JHE Billing Hub

Aplicación nativa Flutter para Windows y Android. No utiliza Electron, Chromium ni WebView. Mantiene Supabase como backend de autenticación y datos.

## Código principal

- `native/`: aplicación Flutter nativa y pruebas.
- `supabase/`: migraciones y Edge Functions del backend.
- `src/` y `electron/`: código web/Electron legado conservado como referencia; no forman parte de la distribución nativa actual.

## Desarrollo nativo

Desde `native/`:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release
flutter build apk --release --split-per-abi
```

El script de compilación reproducible está en `native/tool/build-reliable.ps1`. Las distribuciones publicadas se guardan en `releases/`; cada compilación limpia la anterior.
