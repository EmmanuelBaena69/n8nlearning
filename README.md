# Monitor de KPIs de Catálogo Digital — n8n + Supabase

## Objetivo de la solución

Automatizar el monitoreo del catálogo de productos de la empresa usando datos públicos de [DummyJSON](https://dummyjson.com/products). La solución calcula KPIs de calidad y riesgo, guarda un histórico en base de datos SQL, expone consultas vía webhook, genera alertas automáticas por email y permite consultas en lenguaje natural mediante un agente IA.

---

## Arquitectura resumida

```
Workflow 1 — Ingesta y alertas
Webhook POST /kpi_actual
  → HTTP Request (dummyjson.com/products)
  → Code node (cálculo de KPIs)
  → INSERT en kpi_historico (Supabase)
  → IF (¿KPI fuera de umbral?)
      → TRUE: Send email (alerta)
      → FALSE: fin

Workflow 2 — Consulta webhook con IA
Webhook GET /kpi_actual
  → SELECT kpi_historico (último registro, ordenado por fecha DESC)
  → HTTP Request (Ollama qwen2.5:3b)
      prompt: datos del KPI + pregunta del usuario
      responde SOLO con JSON: kpi_name, kpi_value, status, timestamp, mensaje
  → Respond Webhook (JSON)

Workflow 3 — Agente IA
Webhook POST /ask_kpi
  → AI Agent (Ollama qwen2.5:3b)
      Tool: consultar_kpis (SELECT kpi_historico)
  → Code node (evalúa exec_status)
  → INSERT en log_agente (Supabase)
  → Respond Webhook (JSON)
```

---

## Tecnologías usadas

| Herramienta | Uso |
|-------------|-----|
| n8n (local, Docker) | Orquestador de workflows |
| Supabase (PostgreSQL) | Base de datos SQL |
| DummyJSON API | Fuente de datos de productos |
| Ollama + qwen2.5:3b | Modelo LLM local para el agente |
| Gmail (OAuth2) | Envío de alertas por email |
| Postman | Pruebas de webhooks |
| Docker | Contenedores para n8n y Ollama |

---

## KPIs implementados

### KPI 1 — Calidad del catálogo (`catalog_quality_score`)

Mide el porcentaje de productos con campos críticos completos:

```
%_brand      = productos con brand / total
%_images     = productos con images.length > 0 / total
%_dimensions = productos con width, height y depth definidos / total

catalog_quality_score = promedio(%_brand, %_images, %_dimensions)
```

- **Umbral**: 90%
- **Estado OK**: valor >= 90
- **Estado ALERTA**: valor < 90


## Supuestos

- Se usa DummyJSON como fuente de datos mock en lugar de una API productiva real.
- El umbral de calidad de catálogo se fijó en 90% como valor de referencia para demostración.
- El agente responde en base al último KPI registrado en la BD.
- Ollama corre en el mismo entorno Docker que n8n, en la misma red (`n8n_network`).

---

## Pasos para ejecutar

### Prerrequisitos

- Docker instalado
- Cuenta en Supabase (gratuita)
- Postman instalado

### 1. Levantar los contenedores

```bash
# Crear red compartida
docker network create n8n_network

# Levantar Ollama
docker run -d --name ollama --network n8n_network -p 11434:11434 ollama/ollama
docker exec -it ollama ollama pull qwen2.5:3b

# Levantar n8n
docker run -d --name n8n_local --network n8n_network -p 5678:5678 n8nio/n8n:latest
```

### 2. Crear tablas en Supabase

Ejecutar el archivo `script.sql` en el SQL Editor de Supabase.

### 3. Importar workflows en n8n

1. Abrir `http://localhost:5678`
2. Ir a **Workflows → Import**
3. Importar los archivos `.json` de la carpeta `workflows/`

### 4. Configurar credenciales

Ver sección **Configuración de credenciales** más abajo.

### 5. Activar los workflows

Encender el toggle de cada workflow en n8n.

---

## Configuración de credenciales

> ⚠️ Nunca compartas estos valores reales en repositorios públicos.

### Supabase (Postgres)

En n8n → **Credentials → New → Postgres**:

| Campo | Valor |
|-------|-------|
| Host | `db.<tu-proyecto>.supabase.co` |
| Port | `5432` |
| Database | `postgres` |
| User | `postgres` |
| Password | (contraseña de tu proyecto en Supabase → Settings → Database) |
| SSL | Enable |

### Gmail

En n8n → **Credentials → New → Gmail OAuth2** y conectar cuenta de Google.

### Ollama

No requiere credenciales. URL interna: `http://ollama:11434`

---

## Cómo probar

### Workflow 1 — Disparar ingesta y alerta

```http
GET http://localhost:5678/webhook-test/kpi_actual
Content-Type: application/json
```

Respuesta esperada:
```json
{ "message": "Workflow was started" }
```

### Workflow 2 — Consultar KPIs

```http
POST http://localhost:5678/webhook-test/ask_kpi
```

Respuesta esperada:
```json
{
  "nombre_kpi": "Calidad catalogo KPI-01",
  "valor_kpi": "83.30",
  "status": "ALERTA",
  "umbral": "88.00",
  "fecha_hora": "2026-03-17T17:54:34.117Z"
}
```

### Workflow 3 — Consulta al agente IA

```http
POST http://localhost:5678/webhook-test/ask_kpi
Content-Type: application/json

{
  "question": "¿hay alguna alerta activa?"
}
```

Respuesta esperada:
```json
{
  "response": "Sí, hay una alerta activa. El KPI Calidad catalogo KPI-01 está por debajo del umbral de 88.00 con un valor de 83.30."
}
```

---

## Evidencias de funcionamiento

Ver carpeta `evidencias/`:

| Archivo | Descripción |
|---------|-------------|
| `workflow1_ejecucion.png` | Workflow 1 ejecutado en n8n |
| `workflow2_webhook.png` | Respuesta del webhook en Postman |
| `workflow3_agente.png` | Respuesta del agente IA |
| `supabase_kpi_historico.png` | Registros en tabla kpi_historico |
| `supabase_log_agente.png` | Registros en tabla log_agente |
| `email_alerta.png` | Email de alerta recibido |

---

## Limitaciones y mejoras futuras

- **Ollama local**: el agente depende de que Ollama esté corriendo en el mismo entorno. En producción se reemplazaría por un modelo en la nube (OpenAI, Anthropic).
- **exec_status del agente**: se registra `OK` cuando el agente responde exitosamente y `ERROR` cuando falla o no genera respuesta (por ejemplo, caída de Ollama o pérdida de conexión). Esto permite trazabilidad básica de fallos en el log_agente.
- **Autenticación en webhooks**: los endpoints no tienen autenticación. En producción se agregaría un token de seguridad en los headers.
- **Schedule automático**: en n8n cloud gratuito el Cron trigger está limitado. En producción se configuraría ejecución automática diaria o por hora.
- **Si DummyJSON no responde?**:El nodo HTTP Request falla y n8n detiene el workflow. Como mejora futura se agregaría un nodo de manejo de errores que registre el fallo y envíe una alerta.
