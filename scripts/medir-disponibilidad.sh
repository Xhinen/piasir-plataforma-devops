#!/usr/bin/env bash
# medir-disponibilidad.sh - Mide la disponibilidad de los servicios
# publicados mientras se realiza una operacion de mantenimiento
# (la actualizacion del clustér, por ejemplo).
#
# Uso:
#   scripts/medir-disponibilidad.sh <fichero-de-salida> [segundos-entre-sondas]
#
# Descubre los nombres de maquina declarados en las HTTPRoute del
# clustér, sondea cada uno una vez por intervalo y escribe una linea
# por sonda. Se detiene con Ctrl+C y entonces imprime un resumen por
# servicio, que queda tambien anexado al fichero.
#
# Criterio: un codigo HTTP menor que 400 cuenta como "disponible". El
# fichero guarda el codigo real de cada sonda, de modo que el resumen
# siempre se puede recalcular con otro criterio distinto.
#
# No se usa -k: si el certificado dejase de ser valido eso tambien
# seria una interrupcion del servicio, y debe contar como fallo.

set -uo pipefail

SALIDA="${1:-}"
INTERVALO="${2:-1}"

if [ -z "$SALIDA" ]; then
  echo "uso: $0 <fichero-de-salida> [segundos-entre-sondas]" >&2
  exit 2
fi

if ! command -v kubectl > /dev/null 2>&1; then
  echo "error: no encuentro kubectl" >&2
  exit 1
fi

# --- Descubrimiento de los nombres de maquina publicados -------------

mapfile -t MAQUINAS < <(
  kubectl get httproute -A \
    -o jsonpath='{range .items[*]}{range .spec.hostnames[*]}{@}{"\n"}{end}{end}' \
    2>/dev/null | sort -u
)

if [ "${#MAQUINAS[@]}" -eq 0 ]; then
  echo "error: ninguna HTTPRoute declara nombres de maquina" >&2
  exit 1
fi

# --- Sonda de prueba: si TODO falla, el problema es local ------------

fallos_iniciales=0
for maquina in "${MAQUINAS[@]}"; do
  codigo="$(curl -s -o /dev/null -w '%{http_code}' \
              --max-time 5 "https://${maquina}/" || true)"
  if [ "${codigo:-000}" = "000" ]; then
    fallos_iniciales=$(( fallos_iniciales + 1 ))
  fi
done

if [ "$fallos_iniciales" -eq "${#MAQUINAS[@]}" ]; then
  echo "error: ninguna de las ${#MAQUINAS[@]} maquinas responde antes de" >&2
  echo "       empezar. Revisa la resolucion de nombres y que la autoridad" >&2
  echo "       certificadora interna este en el almacen del sistema." >&2
  echo "       Medir con todo caido no mide nada." >&2
  exit 1
fi

# --- Contadores ------------------------------------------------------

declare -A SONDAS
declare -A FALLOS
for maquina in "${MAQUINAS[@]}"; do
  SONDAS["$maquina"]=0
  FALLOS["$maquina"]=0
done

terminar() {
  {
    echo
    echo "== Resumen =="
    echo "fin: $(date '+%Y-%m-%d %H:%M:%S')"
    printf '%-40s %8s %12s %8s %10s\n' \
      MAQUINA SONDAS DISPONIBLES FALLOS "SEG.CAIDA"
    for maquina in "${MAQUINAS[@]}"; do
      sondas="${SONDAS[$maquina]}"
      fallos="${FALLOS[$maquina]}"
      printf '%-40s %8s %12s %8s %10s\n' \
        "$maquina" "$sondas" "$(( sondas - fallos ))" "$fallos" \
        "$(( fallos * INTERVALO ))"
    done
  } | tee -a "$SALIDA"
  exit 0
}
trap terminar INT TERM

# --- Medicion --------------------------------------------------------

mkdir -p "$(dirname "$SALIDA")"

{
  echo "== Medicion de disponibilidad =="
  echo "inicio:    $(date '+%Y-%m-%d %H:%M:%S')"
  echo "intervalo: ${INTERVALO}s"
  echo "maquinas:  ${#MAQUINAS[@]}"
  for maquina in "${MAQUINAS[@]}"; do
    echo "  - $maquina"
  done
  echo
  echo "Una linea por sonda. FALLO marca codigo >= 400 o sin respuesta."
  echo "Detener con Ctrl+C para obtener el resumen."
  echo
} | tee -a "$SALIDA"

while true; do
  marca="$(date '+%H:%M:%S')"
  for maquina in "${MAQUINAS[@]}"; do
    codigo="$(curl -s -o /dev/null -w '%{http_code}' \
                --max-time 3 "https://${maquina}/" || true)"
    codigo="${codigo:-000}"
    SONDAS["$maquina"]=$(( ${SONDAS[$maquina]} + 1 ))
    if [ "$codigo" = "000" ] || [ "$codigo" -ge 400 ]; then
      FALLOS["$maquina"]=$(( ${FALLOS[$maquina]} + 1 ))
      echo "$marca $maquina $codigo FALLO" >> "$SALIDA"
    else
      echo "$marca $maquina $codigo" >> "$SALIDA"
    fi
  done
  sleep "$INTERVALO"
done
