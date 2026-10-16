# Evidencias de la fase 10 — alta-nodo-worker-02

- Fecha: 2026-10-13 18:54:36 CEST
- Equipo: cachyos-xhinen
- Usuario: xhinen
- Commit: f9a59b4

## Nodos del cluster

```console
$ kubectl get nodes -o wide
NAME            STATUS   ROLES           AGE    VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
k8s-master      Ready    control-plane   109d   v1.36.2   192.168.18.54   <none>        Ubuntu 24.04.5 LTS   6.8.0-146-generic (amd64)   containerd://2.4.1
k8s-worker      Ready    <none>          109d   v1.36.2   192.168.18.53   <none>        Ubuntu 24.04.5 LTS   6.8.0-146-generic (amd64)   containerd://2.4.1
k8s-worker-02   Ready    <none>          22h    v1.36.2   192.168.18.58   <none>        Ubuntu 24.04.4 LTS   6.8.0-100-generic (amd64)   containerd://2.4.1
```

## Pods de todos los espacios

```console
$ kubectl get pods -A
NAMESPACE              NAME                                                     READY   STATUS    RESTARTS       AGE
calico-system          calico-apiserver-55f864f9b8-k4kcn                        1/1     Running   17 (32m ago)   109d
calico-system          calico-apiserver-55f864f9b8-nfs4t                        1/1     Running   17 (32m ago)   109d
calico-system          calico-kube-controllers-787f6dc75b-4pbd6                 1/1     Running   17 (32m ago)   109d
calico-system          calico-node-m9lfj                                        1/1     Running   1 (32m ago)    22h
calico-system          calico-node-qq27x                                        1/1     Running   16 (32m ago)   109d
calico-system          calico-node-zh7jf                                        1/1     Running   17 (32m ago)   109d
calico-system          calico-typha-689657f664-2459l                            1/1     Running   1 (32m ago)    22h
calico-system          calico-typha-689657f664-pnmhg                            1/1     Running   17 (32m ago)   109d
calico-system          csi-node-driver-bdl7x                                    2/2     Running   32 (32m ago)   109d
calico-system          csi-node-driver-kbb2l                                    2/2     Running   2 (32m ago)    22h
calico-system          csi-node-driver-lrmb2                                    2/2     Running   34 (32m ago)   109d
envoy-gateway-system   envoy-gateway-65974d7cbd-db2zf                           1/1     Running   13 (32m ago)   85d
envoy-gateway-system   envoy-portfolio-mi-gateway-c5b29929-7bfdbc7b89-r687x     2/2     Running   20 (32m ago)   85d
kube-system            coredns-589f44dc88-hpx9n                                 1/1     Running   17 (32m ago)   109d
kube-system            coredns-589f44dc88-vxvn2                                 1/1     Running   17 (32m ago)   109d
kube-system            etcd-k8s-master                                          1/1     Running   13 (32m ago)   95d
kube-system            kube-apiserver-k8s-master                                1/1     Running   17 (32m ago)   109d
kube-system            kube-controller-manager-k8s-master                       1/1     Running   14 (32m ago)   95d
kube-system            kube-proxy-g9pgv                                         1/1     Running   13 (32m ago)   95d
kube-system            kube-proxy-jrw87                                         1/1     Running   13 (32m ago)   95d
kube-system            kube-proxy-pblhj                                         1/1     Running   1 (32m ago)    22h
kube-system            kube-scheduler-k8s-master                                1/1     Running   14 (32m ago)   95d
local-path-storage     local-path-provisioner-6d76485965-x655t                  1/1     Running   14 (32m ago)   95d
metallb-system         controller-867dbd646d-bxgp2                              1/1     Running   12 (32m ago)   85d
metallb-system         speaker-2dm5w                                            1/1     Running   20 (31m ago)   85d
metallb-system         speaker-95ngl                                            1/1     Running   15 (32m ago)   85d
metallb-system         speaker-r4shw                                            1/1     Running   2 (31m ago)    22h
monitoring             alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2     Running   30 (32m ago)   98d
monitoring             monitoring-grafana-7b79557ddd-562hl                      3/3     Running   39 (32m ago)   98d
monitoring             monitoring-kube-prometheus-operator-69c59c45f9-6pmbs     1/1     Running   17 (32m ago)   98d
monitoring             monitoring-kube-state-metrics-559db896bf-w7jpq           1/1     Running   27 (32m ago)   98d
monitoring             monitoring-prometheus-node-exporter-6qhrx                1/1     Running   15 (32m ago)   98d
monitoring             monitoring-prometheus-node-exporter-dgkvk                1/1     Running   16 (32m ago)   98d
monitoring             monitoring-prometheus-node-exporter-xsh9q                1/1     Running   1 (32m ago)    22h
monitoring             prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   26 (32m ago)   98d
portfolio              portfolio-6dc87bd4db-7m9f2                               1/1     Running   10 (32m ago)   85d
portfolio              portfolio-6dc87bd4db-qj44m                               1/1     Running   10 (32m ago)   85d
tigera-operator        tigera-operator-85dbff4478-chw9h                         1/1     Running   18 (32m ago)   109d
```

## Servicios de tipo balanceador

```console
$ kubectl get svc -A --field-selector spec.type=LoadBalancer
NAMESPACE              NAME                                  TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)        AGE
envoy-gateway-system   envoy-portfolio-mi-gateway-c5b29929   LoadBalancer   10.110.175.192   192.168.18.240   80:30964/TCP   85d
```

## Pasarelas y rutas

```console
$ kubectl get gateway,httproute -A
NAMESPACE   NAME                                           CLASS   ADDRESS          PROGRAMMED   AGE
portfolio   gateway.gateway.networking.k8s.io/mi-gateway   eg      192.168.18.240   True         85d

NAMESPACE   NAME                                                  HOSTNAMES             AGE
portfolio   httproute.gateway.networking.k8s.io/portfolio-route   ["portfolio.local"]   85d
```

## Volumenes persistentes

```console
$ kubectl get pv,pvc -A
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                                                                                               STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/pvc-478e8a06-8704-4740-987d-533db040525d   2Gi        RWO            Delete           Bound    monitoring/monitoring-grafana                                                                                       local-path     <unset>                          95d
persistentvolume/pvc-6ebf3676-0376-4754-9d10-78f9abbee013   5Gi        RWO            Delete           Bound    monitoring/prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0   local-path     <unset>                          95d

NAMESPACE    NAME                                                                                                                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
monitoring   persistentvolumeclaim/monitoring-grafana                                                                                       Bound    pvc-478e8a06-8704-4740-987d-533db040525d   2Gi        RWO            local-path     <unset>                 98d
monitoring   persistentvolumeclaim/prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0   Bound    pvc-6ebf3676-0376-4754-9d10-78f9abbee013   5Gi        RWO            local-path     <unset>                 98d
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
