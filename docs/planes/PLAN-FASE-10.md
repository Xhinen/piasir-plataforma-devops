# Fase 10 — Automatización con Ansible y reconstrucción del clúster

Plan de trabajo. El orden importa: cada bloque deja el sistema en un estado del
que se puede volver atrás. **No saltes al bloque 4 sin haber cerrado el 3.**

---

## Bloque 0 — Red de seguridad (30 min, hazlo primero)

Nada de lo que viene después es reversible sin esto.

- [ ] Copia completa de las tres máquinas con PBS, al almacén `tfg-store`.
      Proxmox → Datacenter → Backup → ejecutar el trabajo manualmente,
      o desde cada VM: Backup → Backup now, modo `snapshot`, almacén `pbs-tfg-hdd`.
- [ ] Comprobar en PBS → Datastore `tfg-store` → Content que aparecen las tres
      con la fecha de hoy.
- [ ] Pulsar **Verify All** y esperar a que la columna *Verify State* diga `OK`.
- [ ] Capturar esa pantalla y guardarla en `evidencias/`.

**Criterio de salida:** tres copias de hoy, verificadas. Si esto falla, para y
avísame; no sigas.

---

## Bloque 1 — Preparar el terreno (20 min)

- [ ] `git pull` en el repositorio, para partir de lo último.
- [ ] Copiar los ficheros de este paquete sobre `ansible/` del repositorio.
- [ ] Instalar Ansible en tu equipo si no lo tienes: `sudo pacman -S ansible`.
- [ ] Comprobar que llegas a los tres nodos:

```fish
cd ~/GitApps/piasir-plataforma-devops/ansible
ansible -i inventario/produccion.ini todos_los_nodos -m ping
```

Los tres deben responder `pong`. Si alguno falla es cosa de SSH, no de Ansible:
revisa `~/.ssh/config` y los usuarios del inventario, que son distintos en cada
máquina (`kaneda`, `k8smaster`, `k8sworker`).

**Criterio de salida:** tres `pong`.

---

## Bloque 2 — Validar los roles contra lo que ya funciona (1-2 h)

Aquí es donde se descubren los errores, sin romper nada. El modo comprobación
dice qué cambiaría **sin cambiarlo**.

- [ ] Ejecutar en seco contra los nodos actuales:

```fish
ansible-playbook -i inventario/produccion.ini playbooks/site.yml --check --diff
```

- [ ] Leer la salida entera. Cada `changed` es una diferencia entre lo que el rol
      declara y cómo está la máquina de verdad. Para cada uno, decidir:
      ¿el rol está mal escrito, o la máquina está mal configurada?
- [ ] Anotar cada diferencia en el cuaderno de sesión. **Esto es oro para la
      memoria**: documenta la desviación entre lo que creías tener y lo que
      tenías.
- [ ] Corregir los roles hasta que la ejecución en seco salga limpia o con
      diferencias que entiendas y justifiques.

**Criterio de salida:** entiendes cada línea de la salida. No hace falta que
salga todo en verde; hace falta que sepas por qué no.

> Revisa en `group_vars/todos_los_nodos.yml` las tres variables marcadas con
> `# CONFIRMAR`. Las he dejado con el valor que creo correcto, pero no he podido
> comprobarlas contra tus máquinas. Verifícalas antes del bloque 3 con:
> `apt-cache policy containerd.io kubelet` en cualquier nodo.

---

## Bloque 3 — Nodo nuevo desde cero (2-3 h)

El primer uso real de los roles, sobre una máquina que no importa.

- [ ] Crear en Proxmox la VM `k8s-worker-02`: 2 vCPU, 4 GiB, 25 GB,
      Ubuntu Server 24.04 LTS, IP fija `192.168.18.58`.
- [ ] Instalación mínima del sistema, usuario `k8sworker2`, clave pública
      distribuida, nada más a mano.
- [ ] Añadir su línea al inventario (ya está escrita y comentada).
- [ ] Ejecutar primero en seco, luego de verdad:

```fish
ansible-playbook -i inventario/produccion.ini playbooks/nodo-kubernetes.yml --limit k8s-worker-02 --check --diff
ansible-playbook -i inventario/produccion.ini playbooks/nodo-kubernetes.yml --limit k8s-worker-02
```

- [ ] Unir el nodo al clúster con el comando que genera el master:

```fish
ssh k8smaster@192.168.18.54 "sudo kubeadm token create --print-join-command"
```

- [ ] **Prueba de idempotencia** (`R03F01T01P01`, `R03F01T02P01`). Volver a
      ejecutar el mismo playbook. La línea `PLAY RECAP` debe decir `changed=0`.
      Capturar esa pantalla: es la evidencia de la idempotencia.
- [ ] **Cronometrar** el alta completa, de VM inexistente a `Ready`
      (`R03F02T01P01`). Compararlo con lo que tardaste a mano en junio.
- [ ] Recoger evidencias: `./scripts/evidencias.sh 10 alta-nodo-worker-02`
- [ ] Commit con los roles y las evidencias.

**Criterio de salida:** `kubectl get nodes` muestra tres nodos `Ready`, y la
segunda pasada del playbook no cambia nada.

---

## Bloque 4 — Reconstrucción de los nodos existentes (3-4 h)

Ahora sí. Y solo ahora.

- [ ] Verificar una vez más que las copias del bloque 0 están y verificadas.
- [ ] `k8s-worker` primero, que es el prescindible:
      drenarlo, sacarlo del clúster, borrar la VM, crearla de nuevo limpia,
      aplicarle los roles, reincorporarlo.

```fish
kubectl drain k8s-worker --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-worker
```

- [ ] Comprobar que las cargas siguen sirviendo con el clúster a dos nodos.
      **Esto es una prueba de alta disponibilidad real**: documéntala.
- [ ] `k8s-master` después. Aquí el clúster se para: planifícalo para un rato
      en que no necesites nada funcionando.
- [ ] Documentar cada paso en el cuaderno, con la salida de los comandos.

**Criterio de salida:** los tres nodos reconstruidos con Ansible, ninguna orden
manual sobre ellos, y el inventario del script devolviendo lo mismo que antes.

---

## Lo que NO se toca

- `docker-01`. Lleva la monitorización del anfitrión y la construcción de
  imágenes. Si la borras, pierdes las métricas y las capturas durante semanas.
- El contenedor `pbs` (104). Es la red de seguridad.
- Los almacenes `tfg-backups` y `tfg-store`.
- Las máquinas `dc01` y `cli-win`, que son de otro módulo.

---

## Mientras trabajas

Abre la grabación de sesión antes de empezar y ciérrala al acabar:

```fish
script ~/cuaderno/sesion-(date +%F-%H%M).log
# ... trabajas ...
exit
```

Queda todo registrado, lo tuyo y lo que responde la máquina. Luego, con calma,
pasas lo importante a `docs/cuaderno/` usando la plantilla.

Y lo más valioso para la memoria no es lo que salga bien. Es lo que falle, por
qué falló y cómo lo resolviste. Apunta los errores con más detalle que los
aciertos.
