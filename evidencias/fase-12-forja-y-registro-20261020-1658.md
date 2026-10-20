# Evidencias de la fase 12 — forja-y-registro

- Fecha: 2026-10-20 16:58:38 CEST
- Equipo: cachyos-xhinen
- Usuario: xhinen
- Commit: 0cc446d

## Nodos del cluster

```console
$ kubectl get nodes -o wide
NAME            STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
k8s-master      Ready    control-plane   115d    v1.36.2   192.168.18.54   <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.4.1
k8s-worker      Ready    <none>          115d    v1.36.2   192.168.18.53   <none>        Ubuntu 24.04.5 LTS   6.8.0-147-generic (amd64)   containerd://2.4.1
k8s-worker-02   Ready    <none>          7d20h   v1.36.2   192.168.18.58   <none>        Ubuntu 24.04.4 LTS   6.8.0-147-generic (amd64)   containerd://2.4.1
```

## Pods de todos los espacios

```console
$ kubectl get pods -A
NAMESPACE              NAME                                                     READY   STATUS    RESTARTS         AGE
calico-system          calico-apiserver-55f864f9b8-k4kcn                        1/1     Running   23 (3h42m ago)   115d
calico-system          calico-apiserver-55f864f9b8-nfs4t                        1/1     Running   23 (3h42m ago)   115d
calico-system          calico-kube-controllers-787f6dc75b-4pbd6                 1/1     Running   23 (3h42m ago)   115d
calico-system          calico-node-m9lfj                                        1/1     Running   7 (3h42m ago)    7d20h
calico-system          calico-node-qq27x                                        1/1     Running   22 (3h42m ago)   115d
calico-system          calico-node-zh7jf                                        1/1     Running   23 (3h42m ago)   115d
calico-system          calico-typha-689657f664-2459l                            1/1     Running   7 (3h42m ago)    7d20h
calico-system          calico-typha-689657f664-pnmhg                            1/1     Running   23 (3h42m ago)   115d
calico-system          csi-node-driver-bdl7x                                    2/2     Running   44 (3h42m ago)   115d
calico-system          csi-node-driver-kbb2l                                    2/2     Running   14 (3h42m ago)   7d20h
calico-system          csi-node-driver-lrmb2                                    2/2     Running   46 (3h42m ago)   115d
cert-manager           cert-manager-58cbcbdbf4-gs7hn                            1/1     Running   2 (3h42m ago)    8h
cert-manager           cert-manager-cainjector-6468bc96c7-w28jm                 1/1     Running   2 (3h42m ago)    8h
cert-manager           cert-manager-webhook-558c6d4f4d-52l4m                    1/1     Running   2 (3h42m ago)    8h
envoy-gateway-system   envoy-gateway-65974d7cbd-db2zf                           1/1     Running   19 (3h42m ago)   92d
envoy-gateway-system   envoy-portfolio-mi-gateway-c5b29929-7bfdbc7b89-r687x     2/2     Running   32 (3h42m ago)   92d
forja                  forgejo-59978fc84c-hmz5n                                 1/1     Running   0                76m
forja                  postgresql-0                                             1/1     Running   0                179m
kube-system            coredns-589f44dc88-hpx9n                                 1/1     Running   23 (3h42m ago)   115d
kube-system            coredns-589f44dc88-vxvn2                                 1/1     Running   23 (3h42m ago)   115d
kube-system            etcd-k8s-master                                          1/1     Running   19 (3h42m ago)   102d
kube-system            kube-apiserver-k8s-master                                1/1     Running   23 (3h42m ago)   115d
kube-system            kube-controller-manager-k8s-master                       1/1     Running   20 (3h42m ago)   102d
kube-system            kube-proxy-g9pgv                                         1/1     Running   19 (3h42m ago)   102d
kube-system            kube-proxy-jrw87                                         1/1     Running   19 (3h42m ago)   102d
kube-system            kube-proxy-pblhj                                         1/1     Running   7 (3h42m ago)    7d20h
kube-system            kube-scheduler-k8s-master                                1/1     Running   20 (3h42m ago)   102d
local-path-storage     local-path-provisioner-6d76485965-x655t                  1/1     Running   20 (3h42m ago)   102d
metallb-system         controller-867dbd646d-bxgp2                              1/1     Running   18 (3h42m ago)   92d
metallb-system         speaker-2dm5w                                            1/1     Running   32 (3h41m ago)   92d
metallb-system         speaker-95ngl                                            1/1     Running   25 (3h41m ago)   92d
metallb-system         speaker-r4shw                                            1/1     Running   14 (3h41m ago)   7d20h
monitoring             alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2     Running   42 (3h42m ago)   105d
monitoring             monitoring-grafana-7b79557ddd-562hl                      3/3     Running   57 (3h42m ago)   105d
monitoring             monitoring-kube-prometheus-operator-69c59c45f9-6pmbs     1/1     Running   23 (3h42m ago)   105d
monitoring             monitoring-kube-state-metrics-559db896bf-w7jpq           1/1     Running   33 (3h42m ago)   105d
monitoring             monitoring-prometheus-node-exporter-6qhrx                1/1     Running   21 (3h42m ago)   105d
monitoring             monitoring-prometheus-node-exporter-dgkvk                1/1     Running   22 (3h42m ago)   105d
monitoring             monitoring-prometheus-node-exporter-xsh9q                1/1     Running   7 (3h42m ago)    7d20h
monitoring             prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   38 (3h42m ago)   105d
portfolio              portfolio-6dc87bd4db-7m9f2                               1/1     Running   16 (3h42m ago)   92d
portfolio              portfolio-6dc87bd4db-qj44m                               1/1     Running   16 (3h42m ago)   92d
tigera-operator        tigera-operator-85dbff4478-chw9h                         1/1     Running   24 (3h42m ago)   115d
```

## Servicios de tipo balanceador

```console
$ kubectl get svc -A --field-selector spec.type=LoadBalancer
NAMESPACE              NAME                                  TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
envoy-gateway-system   envoy-portfolio-mi-gateway-c5b29929   LoadBalancer   10.110.175.192   192.168.18.240   80:30964/TCP,443:30434/TCP   92d
```

## Pasarelas y rutas

```console
$ kubectl get gateway,httproute -A
NAMESPACE   NAME                                           CLASS   ADDRESS          PROGRAMMED   AGE
portfolio   gateway.gateway.networking.k8s.io/mi-gateway   eg      192.168.18.240   True         92d

NAMESPACE   NAME                                                    HOSTNAMES                           AGE
forja       httproute.gateway.networking.k8s.io/forgejo             ["forja.sierraalta.internal"]       76m
portfolio   httproute.gateway.networking.k8s.io/portfolio-route     ["portfolio.sierraalta.internal"]   92d
portfolio   httproute.gateway.networking.k8s.io/redirigir-a-https                                       7h46m
```

## Volumenes persistentes

```console
$ kubectl get pv,pvc -A
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                                                                                               STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/pvc-478e8a06-8704-4740-987d-533db040525d   2Gi        RWO            Delete           Bound    monitoring/monitoring-grafana                                                                                       local-path     <unset>                          102d
persistentvolume/pvc-51a0e35b-3d0e-4c4e-b1cd-8e6a6074db24   5Gi        RWO            Delete           Bound    forja/datos-postgresql-0                                                                                            local-path     <unset>                          179m
persistentvolume/pvc-6ebf3676-0376-4754-9d10-78f9abbee013   5Gi        RWO            Delete           Bound    monitoring/prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0   local-path     <unset>                          102d
persistentvolume/pvc-7275922b-e9a3-4245-85e7-eb169b40093e   8Gi        RWO            Delete           Bound    forja/forgejo-datos                                                                                                 local-path     <unset>                          76m

NAMESPACE    NAME                                                                                                                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
forja        persistentvolumeclaim/datos-postgresql-0                                                                                       Bound    pvc-51a0e35b-3d0e-4c4e-b1cd-8e6a6074db24   5Gi        RWO            local-path     <unset>                 179m
forja        persistentvolumeclaim/forgejo-datos                                                                                            Bound    pvc-7275922b-e9a3-4245-85e7-eb169b40093e   8Gi        RWO            local-path     <unset>                 76m
monitoring   persistentvolumeclaim/monitoring-grafana                                                                                       Bound    pvc-478e8a06-8704-4740-987d-533db040525d   2Gi        RWO            local-path     <unset>                 105d
monitoring   persistentvolumeclaim/prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0   Bound    pvc-6ebf3676-0376-4754-9d10-78f9abbee013   5Gi        RWO            local-path     <unset>                 105d
```

## Versiones de los componentes

```console
$ kubectl version -o yaml
clientVersion:
  buildDate: "2026-09-24T08:45:22Z"
  compiler: gc
  gitCommit: f78e722310e50bcaca9276be22276d9e91d91308
  gitTreeState: archive
  gitVersion: v1.37.1
  goVersion: go1.27.1-X:nodwarf5
  major: "1"
  minor: "37"
  platform: linux/amd64
kustomizeVersion: v5.8.1
serverVersion:
  buildDate: "2026-06-11T18:09:09Z"
  compiler: gc
  emulationMajor: "1"
  emulationMinor: "36"
  gitCommit: 24e2b02af5543d7910c2bb074c7264df5a8f0467
  gitTreeState: clean
  gitVersion: v1.36.2
  goVersion: go1.26.4
  major: "1"
  minCompatibilityMajor: "1"
  minCompatibilityMinor: "35"
  minor: "36"
  platform: linux/amd64

```

---

Capturas de interfaz grafica pendientes de adjuntar a esta fase:

- [ ] 
