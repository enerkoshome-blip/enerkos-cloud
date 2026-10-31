Enerkos Cloud

Arquitectura general del sistema

Proyecto: Enerkos Home
Versión: 1.0
Estado: Diseño inicial

1. Objetivo

Desarrollar una plataforma centralizada para administrar las tarifas eléctricas de Enerkos Home y distribuir actualizaciones controladas a los dispositivos instalados.

El sistema permitirá actualizar las tarifas sin necesidad de modificar el firmware de cada dispositivo.

2. Arquitectura tecnológica

- GitHub: repositorio y control de versiones del código.
- Cloudflare Pages: alojamiento del panel administrativo.
- Cloudflare Workers: API de comunicación.
- Supabase: base de datos y autenticación.
- LittleFS: almacenamiento local de tarifas en los dispositivos.

3. Componentes

Panel administrativo

Permitirá:

- Administrar las empresas distribuidoras.
- Crear y modificar tarjetas tarifarias.
- Revisar y validar valores.
- Aprobar publicaciones.
- Programar actualizaciones.
- Administrar dispositivos.
- Consultar el historial de publicaciones.

Servidor

Gestionará:

- Autenticación.
- Consulta de versiones.
- Distribución de archivos tarifarios.
- Registro de dispositivos.
- Control de publicaciones.
- Historial de actualizaciones.

Dispositivo Enerkos

La pantalla ESP32:

- Consultará periódicamente la versión disponible.
- Descargaría las tarifas mediante HTTPS.
- Validará integridad y versión.
- Guardará los archivos en LittleFS.
- Mantendrá la última versión válida ante errores.

El sensor ESP32 continuará utilizando ESP-NOW para comunicarse con la pantalla.

4. Empresas distribuidoras

La plataforma contemplará inicialmente:

- CGE.
- Enel.
- Chilquinta.

Cada empresa tendrá sus propias versiones de tarifas.

5. Flujo de publicación

1. Administrador crea una nueva versión.
2. Se ingresan los datos tarifarios.
3. Se validan los valores.
4. Se aprueba la versión.
5. Se publica manualmente.
6. El dispositivo piloto consulta la actualización.
7. Se verifica el resultado.
8. Se habilita la distribución a los demás dispositivos.

6. Control de versiones

Las tarifas publicadas serán inmutables.

Una corrección generará una nueva versión, conservando las anteriores para proteger el historial de consumo y costos.

7. Seguridad

- Acceso administrativo protegido.
- Comunicación HTTPS.
- Identificación individual de dispositivos.
- Credenciales únicas por dispositivo.
- Validación de integridad y autenticidad de archivos.
- No almacenar claves privadas en GitHub.
- Separación entre credenciales administrativas y credenciales de dispositivos.

8. Estrategia de implementación

Fase 1: estructura de repositorio y documentación.

Fase 2: base de datos y autenticación.

Fase 3: panel administrativo.

Fase 4: API y distribución de tarifas.

Fase 5: integración con firmware ESP32.

Fase 6: pruebas con dispositivo piloto.

Fase 7: despliegue progresivo.

9. Principio de compatibilidad

La integración debe respetar el funcionamiento existente del motor tarifaEngine y preservar los registros históricos del dispositivo.

No se modificarán los cálculos tarifarios sin una validación previa.
