#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# evidencias.sh — recoge la salida de los comandos de verificacion de una fase
# y la guarda fechada en evidencias/, para adjuntarla al commit de esa fase.
#
#   Uso:  ./scripts/evidencias.sh <fase> [etiqueta]
#   Ej.:  ./scripts/evidencias.sh 10 alta-nodo-worker-02
#
# No sustituye a las capturas de las interfaces graficas: cubre todo lo que es
# salida de terminal, que es la mayor parte y la que peor se lee como imagen.
# ---------------------------------------------------------------------------
set -uo pipefail

FASE="${1:?Indica el numero de fase. Ej: ./scripts/evidencias.sh 10 alta-nodo}"
ETIQUETA="${2:-verificacion}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SALIDA="$RAIZ/evidencias/fase-$(printf '%02d' "$FASE")-${ETIQUETA}-$(date +%Y%m%d-%H%M).md"

ejecutar() {
  local titulo="$1"; shift
  printf '\n## %s\n\n```console\n$ %s\n' "$titulo" "$*" >> "$SALIDA"
  if "$@" >> "$SALIDA" 2>&1; then :; else printf '[comando no disponible o con error]\n' >> "$SALIDA"; fi
  printf '```\n' >> "$SALIDA"
}

{
  printf '# Evidencias de la fase %s — %s\n\n' "$FASE" "$ETIQUETA"
  printf -- '- Fecha: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf -- '- Equipo: %s\n' "$(hostname)"
  printf -- '- Usuario: %s\n' "$(whoami)"
  printf -- '- Commit: %s\n' "$(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null || echo 'sin repositorio')"
} > "$SALIDA"

ejecutar "Nodos del cluster"            kubectl get nodes -o wide
ejecutar "Pods de todos los espacios"   kubectl get pods -A
ejecutar "Servicios de tipo balanceador" kubectl get svc -A --field-selector spec.type=LoadBalancer
ejecutar "Pasarelas y rutas"            kubectl get gateway,httproute -A
ejecutar "Volumenes persistentes"       kubectl get pv,pvc -A
ejecutar "Versiones de los componentes" kubectl version -o yaml

printf '\n---\n\nCapturas de interfaz grafica pendientes de adjuntar a esta fase:\n\n- [ ] \n' >> "$SALIDA"

printf 'Evidencias guardadas en:\n  %s\n' "$SALIDA"
printf 'Revisa el fichero antes de hacer commit: no debe contener tokens ni contrasenas.\n'
