#!/usr/bin/env bash
# Exporta al repositorio el estado declarativo del cluster.
#
# Este script vive en scripts/ y se vuelve a ejecutar cada vez que cambie algo
# en el cluster: su salida es la fotografia versionada de lo desplegado.
#
# Distingue dos naturalezas, y la distincion importa:
#
#   - Objetos escritos a mano (Gateway, rutas, la aplicacion, el rango de
#     direcciones del balanceador). Se exportan como manifiestos limpios y son
#     la fuente de verdad: de aqui los leera Argo CD en la fase 13.
#
#   - Componentes instalados con Helm (Calico, MetalLB, Envoy Gateway, la pila
#     de observabilidad). De estos NO se exportan los objetos que generan, que
#     son cientos y los regenera el propio grafico. Se guarda lo unico que hace
#     falta para reproducirlos: que version esta instalada y con que valores.
#
# Uso:  ./scripts/exportar-manifiestos.sh
set -euo pipefail

cd "$(dirname "$0")/.."     # raiz del repositorio

if ! python3 -c 'import yaml' 2>/dev/null; then
    echo "Falta el modulo de YAML para Python. Instalalo con:" >&2
    echo "    sudo pacman -S python-yaml" >&2
    exit 1
fi

mkdir -p kubernetes/base kubernetes/aplicaciones kubernetes/helm

# ---------------------------------------------------------------------------
# Limpiador: quita del manifiesto todo lo que pone el cluster y no el autor.
# Dejarlo haria que el fichero no se pueda volver a aplicar en un cluster
# nuevo, que es justo para lo que existe.
# ---------------------------------------------------------------------------
limpiar() {
    python3 -I -c '
import sys, yaml

RUIDO_META = {
    "uid", "resourceVersion", "generation", "creationTimestamp",
    "managedFields", "selfLink", "ownerReferences", "finalizers",
}
RUIDO_ANOT = {
    "kubectl.kubernetes.io/last-applied-configuration",
    "deployment.kubernetes.io/revision",
    "meta.helm.sh/release-name",
    "meta.helm.sh/release-namespace",
}
RUIDO_SPEC_SVC = {
    "clusterIP", "clusterIPs", "ipFamilies", "ipFamilyPolicy",
    "internalTrafficPolicy", "sessionAffinity",
}

def limpia(obj):
    obj.pop("status", None)
    meta = obj.get("metadata", {})
    for k in RUIDO_META:
        meta.pop(k, None)
    for campo in ("annotations", "labels"):
        d = meta.get(campo)
        if isinstance(d, dict):
            for k in list(d):
                if k in RUIDO_ANOT or k.startswith("kubectl.kubernetes.io/"):
                    d.pop(k)
            if not d:
                meta.pop(campo)
    if obj.get("kind") == "Service":
        spec = obj.get("spec", {})
        for k in RUIDO_SPEC_SVC:
            spec.pop(k, None)
        for puerto in spec.get("ports", []):
            puerto.pop("nodePort", None)
    return obj

docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
salida = []
for d in docs:
    if d.get("kind", "").endswith("List"):
        salida.extend(limpia(i) for i in d.get("items", []))
    else:
        salida.append(limpia(d))

if not salida:
    sys.exit(3)
yaml.safe_dump_all(salida, sys.stdout, default_flow_style=False, sort_keys=False)
'
}

exportar() {   # exportar <destino> <descripcion> <argumentos de kubectl get...>
    local destino=$1 descripcion=$2; shift 2
    printf '  %-46s' "$destino"
    if kubectl get "$@" -o yaml 2>/dev/null | limpiar > "$destino.tmp"; then
        {
            echo "# $descripcion"
            echo "# Exportado por scripts/exportar-manifiestos.sh el $(date +%F)."
            cat "$destino.tmp"
        } > "$destino"
        rm -f "$destino.tmp"
        echo "ok"
    else
        rm -f "$destino.tmp"
        echo "sin resultados (revisar)"
    fi
}

echo
echo "== Objetos propios de la plataforma ==================================="
exportar kubernetes/base/namespaces.yaml \
    "Espacios de nombres de la plataforma" \
    namespace portfolio
exportar kubernetes/base/gatewayclass.yaml \
    "Clase de pasarela servida por Envoy Gateway" \
    gatewayclass eg
exportar kubernetes/base/gateway.yaml \
    "Punto unico de entrada de trafico al cluster" \
    gateway mi-gateway -n portfolio
exportar kubernetes/base/httproutes.yaml \
    "Reglas de encaminamiento por nombre de servidor" \
    httproute -n portfolio
exportar kubernetes/base/metallb-direcciones.yaml \
    "Rango de direcciones que MetalLB asigna a los balanceadores" \
    ipaddresspool -n metallb-system
exportar kubernetes/base/metallb-anuncio.yaml \
    "Anuncio de capa 2 de las direcciones del balanceador" \
    l2advertisement -n metallb-system

echo
echo "== Aplicaciones ======================================================="
exportar kubernetes/aplicaciones/portfolio.yaml \
    "Sitio web municipal: despliegue y servicio" \
    deployment,service -n portfolio

echo
echo "== Componentes instalados con Helm ===================================="
helm list --all-namespaces --output yaml > kubernetes/helm/instalaciones.yaml
echo "  kubernetes/helm/instalaciones.yaml            ok"

helm list --all-namespaces --output json \
  | python3 -I -c 'import sys,json; [print(r["name"], r["namespace"]) for r in json.load(sys.stdin)]' \
  | while read -r nombre espacio; do
        destino="kubernetes/helm/valores-${nombre}.yaml"
        printf '  %-46s' "$destino"
        helm get values "$nombre" -n "$espacio" > "$destino"
        echo "ok"
    done

echo
echo "== Comprobacion: el cluster acepta lo exportado ======================="
kubectl apply --dry-run=server -f kubernetes/base/ >/dev/null \
    && echo "  kubernetes/base/          valido" \
    || echo "  kubernetes/base/          REVISAR: el servidor rechaza algo"
kubectl apply --dry-run=server -f kubernetes/aplicaciones/ >/dev/null \
    && echo "  kubernetes/aplicaciones/  valido" \
    || echo "  kubernetes/aplicaciones/  REVISAR: el servidor rechaza algo"

echo
echo "Listo. Revisa los ficheros antes de confirmarlos: la exportacion"
echo "automatica es un punto de partida, no un sustituto de leerlos."
