#!/usr/bin/env bash
#
# Comprobaciones previas a la confirmacion
# ========================================
#
# Nace de la incidencia 41: en una sola jornada, cinco manifiestos perdieron
# parte de su contenido al editarlos, y dos de esas perdidas no producian
# ningun error visible. Este guion comprueba lo que una persona cansada no
# comprueba.
#
# Se ejecuta solo, desde .githooks/pre-commit, antes de cada confirmacion.
# Tambien puede lanzarse a mano en cualquier momento:
#
#   ./scripts/comprobar-manifiestos.sh
#
# Para saltarselo de forma consciente en un caso excepcional:
#
#   git commit --no-verify
#
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

DIRECTORIO_MANIFIESTOS="kubernetes"
FALLOS=0

rojo()  { printf '  \033[31mFALLO\033[0m  %s\n' "$*"; FALLOS=$((FALLOS + 1)); }
verde() { printf '  \033[32mbien\033[0m   %s\n' "$*"; }
aviso() { printf '  \033[33maviso\033[0m  %s\n' "$*"; }
titulo(){ printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Ningun material privado en el indice
# ---------------------------------------------------------------------------
titulo "Material que nunca debe versionarse"

PATRONES_PROHIBIDOS='clave-maestra|\.pem$|id_rsa|id_ed25519|\.kube/config|typescript'
SOSPECHOSOS="$(git diff --cached --name-only --diff-filter=ACM \
                | grep -E "$PATRONES_PROHIBIDOS" \
                | grep -v 'certificado-publico' || true)"

if [ -n "$SOSPECHOSOS" ]; then
  rojo "hay ficheros sospechosos en el indice:"
  printf '         %s\n' $SOSPECHOSOS
  printf '         (el certificado publico del sellador esta exento)\n'
else
  verde "ningun fichero sospechoso"
fi

# ---------------------------------------------------------------------------
# 2. Ningun secreto en claro
# ---------------------------------------------------------------------------
titulo "Secretos sin sellar"

EN_CLARO="$(grep -rl --include='*.yaml' --include='*.yml' \
              -E '^kind:[[:space:]]*Secret[[:space:]]*$' \
              "$DIRECTORIO_MANIFIESTOS" 2>/dev/null || true)"

if [ -n "$EN_CLARO" ]; then
  rojo "estos manifiestos declaran un Secret sin sellar:"
  printf '         %s\n' $EN_CLARO
  printf '         Usa kubeseal: solo SealedSecret puede versionarse.\n'
else
  verde "no hay ningun Secret en claro"
fi

# ---------------------------------------------------------------------------
# 3. Cada manifiesto es YAML valido y Kubernetes lo entiende
# ---------------------------------------------------------------------------
titulo "Validez de los manifiestos"

if ! command -v kubectl >/dev/null 2>&1; then
  aviso "kubectl no esta disponible: se omite la validacion"
elif ! kubectl version -o json >/dev/null 2>&1; then
  aviso "sin acceso al plano de control: se omite la validacion"
  aviso "(arranca el laboratorio para que esta comprobacion sirva de algo)"
else
  INVALIDOS=0
  while IFS= read -r fichero; do
    [ -f "$fichero" ] || continue
    if ! kubectl apply --dry-run=client -f "$fichero" >/dev/null 2>&1; then
      rojo "no valida: $fichero"
      kubectl apply --dry-run=client -f "$fichero" 2>&1 | head -3 | sed 's/^/           /'
      INVALIDOS=$((INVALIDOS + 1))
    fi
    # El directorio de Helm queda fuera: son ficheros de valores, no
    # manifiestos, y carecen de apiVersion y kind por definicion.
  done < <(find "$DIRECTORIO_MANIFIESTOS" \
             -path "$DIRECTORIO_MANIFIESTOS/helm" -prune -o \
             \( -name '*.yaml' -o -name '*.yml' \) -print | sort)

  [ "$INVALIDOS" -eq 0 ] && verde "todos los manifiestos validan"

  # -------------------------------------------------------------------------
  # 4. Ningun objeto declarado dos veces
  #    Argo CD lo avisa, pero despues de haber confirmado y publicado.
  # -------------------------------------------------------------------------
  titulo "Objetos declarados mas de una vez"

  LISTADO="$(kubectl apply --dry-run=client -f "$DIRECTORIO_MANIFIESTOS/aplicaciones" \
               -o jsonpath='{range .items[*]}{.kind}/{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
               2>/dev/null \
             | sed '/^\/\/$/d' | sort)"

  if [ -z "$LISTADO" ]; then
    aviso "no se pudo obtener el listado de objetos"
  else
    REPETIDOS="$(printf '%s\n' "$LISTADO" | uniq -d)"
    if [ -n "$REPETIDOS" ]; then
      rojo "estos objetos aparecen mas de una vez:"
      printf '         %s\n' $REPETIDOS
      printf '         Casi seguro que un fichero se pego encima de otro.\n'
    else
      verde "ningun objeto repetido"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. Invariantes propias de este repositorio
#    Cada una nace de un fallo real. No son genericas: son las nuestras.
# ---------------------------------------------------------------------------
titulo "Invariantes del proyecto"

comprobar_contiene() {
  local fichero="$1" patron="$2" descripcion="$3"
  [ -f "$fichero" ] || return 0
  if grep -qE "$patron" "$fichero"; then
    verde "$descripcion"
  else
    rojo "$descripcion — falta en $fichero"
  fi
}

# Incidencia 41: el subPath se perdio y la copia paso de 194 MB a 461 MB
comprobar_contiene "$DIRECTORIO_MANIFIESTOS/aplicaciones/copias-nube.yaml" \
  'subPath:[[:space:]]*data' \
  "la copia de Nextcloud se limita al directorio de datos"

# Incidencia 39: sin esta etiqueta, la politica de red bloquea la copia
comprobar_contiene "$DIRECTORIO_MANIFIESTOS/aplicaciones/copias-nube.yaml" \
  'acceso-base-de-datos' \
  "la tarea de copia de Nextcloud esta autorizada ante la politica de red"

# Incidencia 41: la cabecera de variables del guion de la forja se perdio
comprobar_contiene "$DIRECTORIO_MANIFIESTOS/aplicaciones/copias-forja.yaml" \
  '^[[:space:]]*destino=' \
  "el guion de copia de la forja define sus variables"

# Las tres tareas de copia deben verificar lo que producen
for fichero in copias-forja copias-nube copias-vault; do
  comprobar_contiene "$DIRECTORIO_MANIFIESTOS/aplicaciones/${fichero}.yaml" \
    'Verificacion de la copia' \
    "${fichero} verifica la copia que produce"
done

# Un fichero de copias, una sola tarea programada
for fichero in "$DIRECTORIO_MANIFIESTOS"/aplicaciones/copias-*.yaml; do
  [ -f "$fichero" ] || continue
  CUENTA="$(grep -c '^kind: CronJob' "$fichero")"
  if [ "$CUENTA" -ne 1 ]; then
    rojo "$(basename "$fichero") declara $CUENTA tareas programadas, se esperaba 1"
  fi
done

# ---------------------------------------------------------------------------
titulo "Resultado"

if [ "$FALLOS" -eq 0 ]; then
  printf '  Todo correcto.\n\n'
  exit 0
fi

printf '  %s comprobacion(es) fallidas. La confirmacion se detiene.\n' "$FALLOS"
printf '  Si estas seguro de lo que haces: git commit --no-verify\n\n'
exit 1
