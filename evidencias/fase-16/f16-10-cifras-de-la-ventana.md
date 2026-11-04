# Fase 16 — Cifras de la ventana de mantenimiento

Actualización del clúster de Kubernetes de v1.36.2 a v1.36.6.
Drenaje del nodo `k8s-worker-02`, que alberga los volúmenes locales de
los tres servicios con estado.

Fecha: 3 de noviembre de 2026.

## Método

La medición activa desde fuera del clúster falló (ver incidencia
correspondiente: el medidor se detuvo dieciocho minutos antes del
ejercicio y nadie lo comprobó). Las cifras que siguen están
**reconstruidas a posteriori desde Prometheus**, que estuvo en
funcionamiento durante toda la ventana por encontrarse en el otro nodo.

Métrica empleada: `kube_pod_status_ready{condition="true"}`, agregada
por espacio de nombres para eliminar la etiqueta `instance`, que cambia
cuando kube-state-metrics se recoloca y rompe la continuidad de las
series.

Consultas utilizadas:

```promql
max by (namespace) (
  kube_pod_status_ready{condition="true", namespace=~"forja|nube|vault",
                        pod!~".*cron.*|copia-.*|postgresql.*|valkey.*"}
)

sum(kube_pod_status_ready{condition="true", namespace="portfolio"})

sum(kube_pod_status_ready{condition="true",
    namespace="envoy-gateway-system", pod=~"envoy-portfolio.*"})

ALERTS{alertstate=~"pending|firing", namespace=~"portfolio|forja|nube|vault"}
```

## Cronología

| Hora     | Suceso |
|----------|--------|
| 17:28:56 | Se inicia el drenaje de `k8s-worker-02` |
| 17:29:10 | Envoy pasa de 2 réplicas listas a 1 |
| 17:29:20 | Última muestra con forja, nube y vault listos |
| 17:29:40 | Tres alertas `KubeDeploymentReplicasMismatch` pasan a *pendiente* |
| 17:34:55 | El nodo se devuelve a servicio (`uncordon`) |
| 17:35:20 | forja y vault vuelven a estar listos; alertas pendientes resueltas |
| 17:35:40 | Envoy recupera sus 2 réplicas |
| 17:36:00 | nube vuelve a estar lista |

## Resultados

| Servicio | Indisponibilidad | Observaciones |
|----------|------------------|---------------|
| portfolio (web pública) | **0 s** | 3 réplicas listas en todas las muestras |
| forja (Forgejo) | **6 min 00 s** | volumen local atado al nodo |
| vault (Vaultwarden) | **6 min 00 s** | volumen local atado al nodo |
| nube (Nextcloud) | **6 min 40 s** | volumen local atado al nodo |
| Envoy (plano de datos) | 0 s de corte; **6 min 30 s sin redundancia** | de 2 réplicas a 1 |

Tiempo entre la devolución del nodo a servicio y la recuperación de cada
servicio: **25 s** (forja, vault) y **65 s** (nube).

## Lecturas

**La indisponibilidad no la causa la actualización, la causa el
drenaje.** De los 6 minutos de caída, 5 min 59 s corresponden al tiempo
que el nodo permaneció acordonado y solo 25-65 s a la recuperación de
los servicios. Acortar la ventana pasa por reducir el tiempo fuera de
servicio del nodo, no por optimizar los contenedores.

**El problema de fondo es el aprovisionador de almacenamiento, no
Kubernetes.** `portfolio` se recolocó sin interrupción porque no tiene
estado. Los tres servicios caídos lo están porque `local-path` ata cada
volumen al nodo donde se creó y los pods no pueden seguirlo. Con
almacenamiento en red habrían migrado igual que la web.

**La redundancia del plano de datos desaparece durante el
mantenimiento.** La restricción de reparto de Envoy es
`whenUnsatisfiable: DoNotSchedule`: con solo dos nodos de trabajo, la
réplica desalojada no tiene dónde colocarse y el servicio funciona seis
minutos con una única instancia. Es una limitación de la maqueta —tres
nodos la eliminarían—, no del diseño.

**El umbral temporal de las alertas es una decisión de política, no un
detalle técnico.** La vigilancia detectó la caída a los 44 segundos,
pero `KubeDeploymentReplicasMismatch` exige quince minutos de
persistencia antes de notificar. Una interrupción de seis minutos es,
con los valores por defecto, silenciosa por diseño.

## Salvedades

- El muestreo de kube-state-metrics es de 30 segundos: una interrupción
  más breve que ese intervalo no sería visible en estas cifras.
- Durante la ventana, las series de forja, nube y vault **desaparecen**
  en lugar de valer cero. Un hueco y un cero no son lo mismo: el hueco
  significa que no existía ningún pod del que informar.
- La medida es de *disponibilidad del pod*, no de *respuesta HTTP*. Son
  equivalentes en la práctica porque las sondas de disponibilidad de
  Forgejo, Nextcloud y Vaultwarden consultan un extremo HTTP de la
  propia aplicación, pero no es exactamente lo mismo que medir desde
  fuera del clúster.
