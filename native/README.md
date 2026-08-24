# JHE Billing Hub nativo

Aplicación Flutter compilada de forma nativa para Windows y Android. No utiliza Electron, Chromium, WebView ni una sesión de navegador. Conserva Supabase para las cuentas, roles, avisos y datos existentes.

## Funciones

- acceso con roles Administrador y Gestión;
- avisos de solicitudes, facturas emitidas y facturas cobradas;
- gestiones administrativas con filtros, ordenación, duplicado y completado desde el hilo de comunicación;
- facturas y presupuestos con alta, edición, conversión, cobro, rectificativas, PDF, impresión y Excel;
- clientes, emisores y usuarios/roles;
- árbol de ponencias y generación local de documentos.

## Compilación fiable

```powershell
powershell -ExecutionPolicy Bypass -File tool/build-reliable.ps1
```

Los entregables se generan en `../releases/` y se conserva sólo la última versión.

## Árbol de ponencias

La pantalla `Ponencias` del administrador lee `billing_requests` en Supabase. La exportación histórica de Notion se conserva en `source_data` con trazabilidad, sin abrir Notion ni depender del navegador.
