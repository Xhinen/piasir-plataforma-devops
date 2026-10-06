#!/usr/bin/env bash
# inventario.sh - Fotografía del estado de un nodo. Solo lectura.
echo "=========================================================="
echo " NODO: $(hostname)   FECHA: $(date -Is)"
echo "=========================================================="
echo "--- Sistema operativo y kernel ---"
. /etc/os-release 2>/dev/null && echo "SO: $PRETTY_NAME"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p 2>/dev/null)"

echo; echo "--- Recursos ---"
echo "CPU: $(nproc) vCPU"
free -h | sed 's/^/  /'
df -hT / 2>/dev/null | sed 's/^/  /'

echo; echo "--- Runtimes de contenedores ---"
if command -v docker >/dev/null; then
  DV=$(docker version --format '{{.Server.Version}}' 2>/dev/null | tr -d '\n')
  echo "  Docker: ${DV:-instalado, pero el demonio no responde}"
fi
command -v containerd >/dev/null && echo "  containerd: $(containerd --version | awk '{print $3}')"
command -v crictl  >/dev/null && echo "  Imágenes en containerd: $(crictl images -q 2>/dev/null | wc -l)"

echo; echo "--- Kubernetes ---"
command -v kubelet >/dev/null && echo "  kubelet: $(kubelet --version | awk '{print $2}')"
command -v kubeadm >/dev/null && echo "  kubeadm: $(kubeadm version -o short)"
if command -v kubectl >/dev/null && [ -f /etc/kubernetes/admin.conf -o -f "$HOME/.kube/config" ]; then
  echo "  --- Nodos ---";     kubectl get nodes -o wide 2>/dev/null | sed 's/^/  /'
  echo "  --- Versiones de imagen por nodo ---"
  kubectl get nodes -o custom-columns=NOMBRE:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion,SO:.status.nodeInfo.osImage 2>/dev/null | sed 's/^/  /'
  echo "  --- Pods que NO estan Running/Completed ---"
  kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | sed 's/^/  /'
  echo "  --- Consumo real por nodo ---"; kubectl top nodes 2>/dev/null | sed 's/^/  /'
  echo "  --- Releases de Helm ---"
  command -v helm >/dev/null && helm list -A 2>/dev/null | sed 's/^/  /'
  command -v helm >/dev/null && echo "  Helm: $(helm version --template '{{.Version}}')"
  echo "  --- Entrada de trafico ---"
  kubectl get gateway,httproute -A 2>/dev/null | sed 's/^/  /'
  kubectl get svc -A --field-selector spec.type=LoadBalancer 2>/dev/null | sed 's/^/  /'
  echo "  --- Almacenamiento ---"
  kubectl get sc,pv 2>/dev/null | sed 's/^/  /'
  kubectl get pvc -A 2>/dev/null | sed 's/^/  /'
fi

echo; echo "--- Requisitos de kubeadm ---"
echo "  Swap activa: $(swapon --show --noheadings 2>/dev/null | wc -l) entradas (debe ser 0)"
echo "  Modulos: $(lsmod | grep -cE '^(overlay|br_netfilter)') de 2"
echo "  net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward 2>/dev/null)"

echo; echo "--- Seguridad ---"
systemctl is-active fail2ban ufw unattended-upgrades 2>/dev/null | paste -sd' ' - | sed 's/^/  fail2ban ufw unattended-upgrades: /'
echo "  PermitRootLogin: $(sshd -T 2>/dev/null | grep -i '^permitrootlogin' | awk '{print $2}')"
echo "  PasswordAuthentication: $(sshd -T 2>/dev/null | grep -i '^passwordauthentication' | awk '{print $2}')"
echo "=========================================================="
