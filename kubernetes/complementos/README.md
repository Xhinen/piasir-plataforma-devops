# Complementos del clúster

Componentes de plataforma instalados sobre Kubernetes que no son aplicaciones
del ayuntamiento, sino infraestructura del propio clúster: red, balanceo,
almacenamiento y entrada de tráfico.

Este fichero existe porque estos componentes **no se instalaron con Helm**, de
modo que el clúster sabe qué objetos tiene pero no de dónde salieron. Sin esta
tabla, reconstruir la plataforma dependería de recordar qué versión se aplicó
y desde qué dirección. Las versiones no están escritas de memoria: se han leído
del clúster en ejecución, con los comandos que figuran al final.

## Versiones en ejecución

Comprobado el 16 de octubre de 2026.

| Componente | Versión | Función | Instalación |
|---|---|---|---|
| Tigera Operator | v1.42.0 | Instala y mantiene Calico | Manifiesto de upstream |
| Calico | v3.32.0 | Complemento de red del clúster (CNI) y políticas de red | Gestionado por el operador |
| Gateway API | v1.5.0 | Definiciones de recursos de la especificación de entrada de tráfico | Manifiesto de upstream |
| Envoy Gateway | v1.5.4 | Implementación de Gateway API | Helm |
| MetalLB | v0.16.0 | Balanceador de carga para redes sin proveedor de nube | Manifiesto de upstream |
| local-path-provisioner | v0.0.36 | Aprovisionador de volúmenes persistentes sobre disco local | Manifiesto de upstream |
| kube-prometheus-stack | 87.2.1 | Observabilidad: Prometheus, Grafana y Alertmanager | Helm |

Las dos instalaciones con Helm quedan registradas en el propio clúster; su
inventario y sus valores están en `kubernetes/helm/`.

## Reproducción desde cero

El orden importa: la red antes que nada, porque sin complemento de red los
nodos no pasan de `NotReady`; las definiciones de recursos antes que quien las
usa.

```bash
# 1. Red del clúster
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
kubectl apply  -f kubernetes/complementos/calico-installation.yaml

# 2. Definiciones de la especificación de entrada de tráfico
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

# 3. Balanceador de carga
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.0/config/manifests/metallb-native.yaml
kubectl apply -f kubernetes/base/metallb-direcciones.yaml
kubectl apply -f kubernetes/base/metallb-anuncio.yaml

# 4. Almacenamiento local
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml

# 5. Implementación de Gateway API y observabilidad, con sus valores
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.5.4 \
  -n envoy-gateway-system --create-namespace \
  -f kubernetes/helm/valores-eg.yaml
helm install monitoring prometheus-community/kube-prometheus-stack --version 87.2.1 \
  -n monitoring --create-namespace \
  -f kubernetes/helm/valores-monitoring.yaml

# 6. Objetos propios de la plataforma
kubectl apply -f kubernetes/base/
kubectl apply -f kubernetes/aplicaciones/
```

> **Verificar antes de dar por buenas las órdenes de upstream.** Las direcciones
> anteriores son la forma canónica de instalar cada componente, pero no consta
> en ningún registro cuál se empleó exactamente en junio de 2026. Confírmalas
> contra la documentación de cada proyecto antes de usarlas en una
> reconstrucción real.

## De dónde salen estas versiones

```bash
kubectl get installation default -o jsonpath='{.status.calicoVersion}'
kubectl get deployment -n tigera-operator    -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'
kubectl get deployment -n metallb-system     -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'
kubectl get deployment -n local-path-storage -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'
kubectl get crd gateways.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}'
helm list --all-namespaces
```

## Limitación conocida

Cuatro de los seis componentes se instalaron aplicando manifiestos de upstream
sin fijar su procedencia en el repositorio, y la constancia de sus versiones es
posterior a la instalación: se ha reconstruido interrogando al clúster, no
leyendo lo que se declaró al instalarlo. Es la misma clase de divergencia entre
documentación y realidad que recoge la incidencia 12 a propósito del runtime de
contenedores, y que motiva el requisito R03.

La corrección definitiva corresponde a la fase 13: con un modelo de despliegue
continuo, estos componentes se declaran en el repositorio con su versión fijada
y el clúster converge hacia lo declarado, de modo que la pregunta «qué versión
hay instalada» deja de responderse interrogando a la máquina.
