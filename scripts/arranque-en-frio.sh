#!/usr/bin/env bash
#
# Arranque en frio de la plataforma
# =================================
#
# Recupera la forja cuando no se puede contar con Argo CD, porque el
# repositorio que Argo CD vigila esta alojado en la propia forja.
#
# Esta dependencia circular es conocida y deliberada: la plataforma no
# depende de ningun proveedor externo para desplegar. El precio es que la
# forja no puede recuperarse a si misma, y por eso su arranque esta escrito
# aqui en lugar de confiarse a la memoria de quien atienda la incidencia.
#
# Una vez la forja responde, Argo CD vuelve a tener fuente y repone el resto
# de la plataforma por si solo. Este guion cubre unicamente el arranque.
#
#   Requisitos previos
#   ------------------
#   1. Acceso con kubectl al plano de control.
#   2. El controlador de secretos sellados en pie y CON SU CLAVE PRIVADA.
#      Sin ella no se descifra ningun secreto del repositorio y la
#      recuperacion se detiene aqui.
#   3. Las dos piezas de la copia, accesibles desde esta maquina.
#   4. Este repositorio. Si la forja no existe, se clona del espejo externo:
#        git clone https://github.com/Xhinen/piasir-plataforma-devops.git
#
#   Uso
#   ---
#     ./scripts/arranque-en-frio.sh preparar
#     ./scripts/arranque-en-frio.sh restaurar <base.dump> <datos.tar.gz>
#     ./scripts/arranque-en-frio.sh arrancar
#
#   Las tres fases estan separadas a proposito: entre la primera y la segunda
#   hay una decision humana que ningun guion debe tomar por su cuenta, que es
#   QUE COPIA se restaura.
#
set -euo pipefail

ESPACIO="forja"
ESPACIO_SELLADOS="sealed-secrets"
DESPLIEGUE_SELLADOS="sealed-secrets"
GRAFICO="oci://code.forgejo.org/forgejo-helm/forgejo"
VERSION_GRAFICO="17.3.0"
POD_RESTAURACION="restauracion-dr"

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALORES="${RAIZ}/kubernetes/helm/valores-forgejo.yaml"
MANIFIESTOS="${RAIZ}/kubernetes/aplicaciones"
MANIFIESTO_POD="${RAIZ}/kubernetes/pruebas/restauracion-dr.yaml"

paso()  { printf '\n== %s\n' "$*"; }
aviso() { printf '   %s\n' "$*"; }
abortar() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Comprobaciones previas. Se ejecutan en las tres fases: durante un incidente
# nadie recuerda cual era imprescindible.
# ---------------------------------------------------------------------------
comprobar_entorno() {
  paso "Comprobaciones previas"

  for binario in kubectl helm; do
    command -v "$binario" >/dev/null 2>&1 || abortar "falta el mandato '$binario'"
  done

  kubectl version -o json >/dev/null 2>&1 \
    || abortar "no hay acceso al plano de control"

  local listos
  listos="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
  aviso "nodos en estado Ready: ${listos}"
  [ "$listos" -ge 1 ] || abortar "ningun nodo disponible"

  # Se busca en todos los espacios de nombres a proposito: el controlador no
  # tiene por que estar donde uno recuerda. Aqui vive en 'sealed-secrets'.
  local claves
  claves="$(kubectl get secrets -A \
              -l sealedsecrets.bitnami.com/sealed-secrets-key \
              --no-headers 2>/dev/null | wc -l)"
  if [ "$claves" -eq 0 ]; then
    abortar "no se encuentra ninguna clave del controlador de secretos sellados.
   Restaurala ANTES de continuar; sin ella los secretos del repositorio
   no se pueden descifrar y nada de lo que sigue funcionara:
     kubectl apply -f <clave-maestra>.yaml
     kubectl -n ${ESPACIO_SELLADOS} rollout restart deploy/${DESPLIEGUE_SELLADOS}"
  fi
  aviso "claves del controlador de secretos sellados: ${claves}"

  [ -f "$VALORES" ] || abortar "no se encuentra ${VALORES}"
}

# ---------------------------------------------------------------------------
# Fase 1 — Infraestructura vacia, lista para recibir la copia
# ---------------------------------------------------------------------------
fase_preparar() {
  comprobar_entorno

  # Salvaguarda. Esta fase detiene la aplicacion, asi que no debe poder
  # ejecutarse por descuido sobre un sistema que esta dando servicio.
  if kubectl -n "$ESPACIO" get deploy/forgejo >/dev/null 2>&1; then
    local listas
    listas="$(kubectl -n "$ESPACIO" get deploy/forgejo \
                -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    if [ "${listas:-0}" -gt 0 ] && [ "${FORZAR:-no}" != "si" ]; then
      abortar "la forja esta EN SERVICIO con ${listas} replica(s).
   Esta fase la detiene. Si es lo que quieres de verdad (por ejemplo para
   un ensayo), repite con:
     FORZAR=si $0 preparar"
    fi
  fi

  paso "Espacio de nombres"
  kubectl create namespace "$ESPACIO" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$ESPACIO" acceso-gateway=permitido --overwrite

  paso "Manifiestos del repositorio"
  aviso "secretos sellados, base de datos, volumenes y tarea de copia"
  kubectl apply -f "$MANIFIESTOS"

  paso "Esperando a la base de datos"
  kubectl -n "$ESPACIO" wait --for=condition=ready pod/postgresql-0 --timeout=600s

  paso "Instalando la forja, detenida"
  # El grafico rechaza cero replicas por esquema, asi que se instala y se
  # reduce acto seguido. No importa que llegue a arrancar un instante: la
  # fase de restauracion borra y recrea la base de datos antes de volcarla.
  if helm -n "$ESPACIO" status forgejo >/dev/null 2>&1; then
    aviso "la version ya existe, se omite la instalacion"
  else
    helm install forgejo "$GRAFICO" \
      --namespace "$ESPACIO" \
      --version "$VERSION_GRAFICO" \
      --values "$VALORES"
  fi
  kubectl -n "$ESPACIO" scale deploy/forgejo --replicas=0

  paso "Pod de restauracion"
  kubectl apply -f "$MANIFIESTO_POD"
  kubectl -n "$ESPACIO" wait --for=condition=ready "pod/${POD_RESTAURACION}" --timeout=300s

  cat <<'FIN'

   Infraestructura lista y detenida.

   DECISION HUMANA: elige que copia restaurar. Por omision, la mas reciente
   del almacen; si se sospecha corrupcion logica, una anterior.

     kubectl -n forja exec restauracion-dr -- ls -lh /copias

   Despues:

     ./scripts/arranque-en-frio.sh restaurar <base.dump> <datos.tar.gz>

   Los dos ficheros pueden estar ya dentro del almacen de copias o ser rutas
   locales de esta maquina; el guion lo resuelve solo.

FIN
}

# ---------------------------------------------------------------------------
# Fase 2 — Restaurar contenido
# ---------------------------------------------------------------------------
fase_restaurar() {
  local base_origen="${1:-}" datos_origen="${2:-}"
  [ -n "$base_origen" ] && [ -n "$datos_origen" ] \
    || abortar "uso: $0 restaurar <base.dump> <datos.tar.gz>"

  comprobar_entorno

  kubectl -n "$ESPACIO" get "pod/${POD_RESTAURACION}" >/dev/null 2>&1 \
    || abortar "no existe el pod de restauracion; ejecuta antes la fase 'preparar'"

  # Si la ruta existe en esta maquina, se sube. Si no, se asume que el
  # fichero ya esta en el almacen de copias del clúster.
  local base datos
  if [ -f "$base_origen" ]; then
    paso "Subiendo el volcado de la base"
    kubectl cp "$base_origen" "${ESPACIO}/${POD_RESTAURACION}:/copias/$(basename "$base_origen")"
  fi
  if [ -f "$datos_origen" ]; then
    paso "Subiendo el empaquetado de datos"
    kubectl cp "$datos_origen" "${ESPACIO}/${POD_RESTAURACION}:/copias/$(basename "$datos_origen")"
  fi
  base="/copias/$(basename "$base_origen")"
  datos="/copias/$(basename "$datos_origen")"

  paso "Huellas de los ficheros a restaurar"
  aviso "COMPARALAS con las del registro de copias antes de seguir"
  kubectl -n "$ESPACIO" exec "$POD_RESTAURACION" -- sha256sum "$base" "$datos"

  paso "Restaurando"
  kubectl -n "$ESPACIO" exec "$POD_RESTAURACION" -- bash -c "
    set -euo pipefail

    echo '-- recreando la base de datos vacia'
    psql -d postgres -c 'DROP DATABASE IF EXISTS forgejo;'
    psql -d postgres -c 'CREATE DATABASE forgejo OWNER forgejo;'

    echo '-- volcado'
    pg_restore --no-owner --no-privileges -d forgejo '${base}' \
      || echo '   (restauracion con avisos)'

    echo '-- volumen de datos'
    find /datos-forja -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    tar xzf '${datos}' -C /datos-forja

    echo '-- comprobacion'
    psql -d forgejo -c 'SELECT (SELECT count(*) FROM \"user\") AS usuarios,
                               (SELECT count(*) FROM repository) AS repositorios;'
    du -sh /datos-forja
  "

  cat <<'FIN'

   Contenido restaurado. Para levantar el servicio:

     ./scripts/arranque-en-frio.sh arrancar

FIN
}

# ---------------------------------------------------------------------------
# Fase 3 — Levantar y verificar
# ---------------------------------------------------------------------------
fase_arrancar() {
  comprobar_entorno

  paso "Retirando el pod de restauracion"
  kubectl -n "$ESPACIO" delete "pod/${POD_RESTAURACION}" --ignore-not-found

  paso "Levantando la forja"
  kubectl -n "$ESPACIO" scale deploy/forgejo --replicas=1
  kubectl -n "$ESPACIO" rollout status deploy/forgejo --timeout=600s

  paso "Verificacion"
  kubectl -n "$ESPACIO" exec postgresql-0 -- psql -U forgejo -d forgejo -c \
    "SELECT (SELECT count(*) FROM \"user\") AS usuarios,
            (SELECT count(*) FROM repository) AS repositorios,
            (SELECT count(*) FROM package) AS paquetes;"

  local codigo
  codigo="$(curl -sk -o /dev/null -w '%{http_code}' \
            https://forja.sierraalta.internal/ || true)"
  aviso "respuesta de la forja por HTTPS: ${codigo}"
  printf '   hora de servicio restablecido: %s\n' "$(date -Iseconds)"

  cat <<'FIN'

   Forja en pie. Queda por hacer, en este orden:

   1. Comprobar que el repositorio de la plataforma esta completo en la
      forja. Si se recupero de una copia anterior al ultimo envio, reenviar
      desde el clon local:
        git push forja main

   2. Devolver el gobierno a Argo CD, que ya vuelve a tener fuente:
        kubectl -n argocd patch application aplicaciones-plataforma \
          --type merge \
          -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

   3. Lanzar una copia nueva ahora que el servicio esta sano:
        kubectl -n forja create job --from=cronjob/copia-forja copia-post-dr

   4. Anotar las dos cifras: tiempo de recuperacion y perdida de datos.

FIN
}

case "${1:-}" in
  preparar)  fase_preparar ;;
  restaurar) shift; fase_restaurar "$@" ;;
  arrancar)  fase_arrancar ;;
  *)
    cat <<FIN
Arranque en frio de la plataforma.

  $0 preparar
  $0 restaurar <base.dump> <datos.tar.gz>
  $0 arrancar

Consulta la cabecera de este fichero para los requisitos previos.
FIN
    exit 1
    ;;
esac
