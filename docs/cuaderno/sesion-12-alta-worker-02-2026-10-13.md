# Sesión 12 — Alta de k8s-worker-02 con Ansible y cierre del bloque 3 — 2026-10-13

**Duración:** 12/10 de 20:00 a 20:30 y 13/10 de 18:25 a 19:35 (≈1 h 40 min) ⟨ajustar⟩
**Fase / RFTP:** F10 · R03F01T01, R03F01T02P01, R03F02T01P01
**Estado al empezar:** Roles de Ansible escritos y validados en modo comprobación
contra los tres nodos existentes. El nodo `k8s-worker-02` existía como máquina
virtual con Ubuntu Server recién instalado y la clave pública distribuida, pero
sin configurar y fuera del clúster.
**Objetivo de la sesión:** Configurar el nodo nuevo únicamente con los roles,
incorporarlo al clúster y demostrar la idempotencia con una segunda ejecución
sin cambios.

---

## Lo que hice

Ejecución real de los roles sobre el nodo nuevo, sin ninguna orden manual sobre
la máquina más allá de la instalación del sistema operativo:

```console
$ ansible-playbook -i inventario/produccion.ini playbooks/nodo-kubernetes.yml --limit k8s-worker-02
PLAY RECAP
k8s-worker-02 : ok=34  changed=22  unreachable=0  failed=0
Playbook run took 0 days, 0 hours, 0 minutes, 48 seconds
```

Segunda ejecución inmediata, para la prueba de idempotencia:

```console
$ ansible-playbook -i inventario/produccion.ini playbooks/nodo-kubernetes.yml --limit k8s-worker-02
PLAY RECAP
k8s-worker-02 : ok=31  changed=0  unreachable=0  failed=0
```

Generación del testigo de incorporación desde el plano de control y unión del
nodo (la orden lleva testigo y huella del certificado de la autoridad, de modo
que no se transcribe aquí ni se versiona):

```console
$ ssh k8smaster@192.168.18.54 "sudo kubeadm token create --print-join-command"
```

```console
# en k8s-worker-02
$ sudo kubeadm join 192.168.18.54:6443 --token <omitido> --discovery-token-ca-cert-hash <omitido>
[kubelet-check] The kubelet is healthy after 501.179074ms
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.
```

Comprobación del clúster al día siguiente, una vez desplegados los agentes de
red en el nodo nuevo:

```console
$ kubectl get nodes -o wide
NAME            STATUS   ROLES           AGE    VERSION   INTERNAL-IP     OS-IMAGE             KERNEL-VERSION   CONTAINER-RUNTIME
k8s-master      Ready    control-plane   109d   v1.36.2   192.168.18.54   Ubuntu 24.04.5 LTS   6.8.0-146        containerd://2.4.1
k8s-worker      Ready    <none>          109d   v1.36.2   192.168.18.53   Ubuntu 24.04.5 LTS   6.8.0-146        containerd://2.4.1
k8s-worker-02   Ready    <none>          22h    v1.36.2   192.168.18.58   Ubuntu 24.04.4 LTS   6.8.0-100        containerd://2.4.1
```

Recogida de evidencias y captura de pantalla:

```console
$ ./scripts/evidencias.sh 10 alta-nodo-worker-02
```

---

## Lo que falló

### Problema 1 — El nodo no podía unirse al clúster: el runtime no exponía la interfaz CRI

#### Síntoma

```
[preflight] Some fatal errors occurred:
        [ERROR CRI]: could not connect to the container runtime: validate CRI v1
        runtime API for endpoint "unix:///var/run/containerd/containerd.sock":
        rpc error: code = Unimplemented desc = unknown service runtime.v1.RuntimeService
        [ERROR ContainerRuntimeVersion]: (mismo error)
```

El servicio de containerd estaba activo y el socket existía. Respondía, pero no
al servicio que kubeadm le pedía.

#### Qué probé

- Comprobar que el servicio estaba activo y que el socket existía: lo estaban,
  así que el problema no era de arranque ni de permisos.
- Revisar la versión instalada: 2.4.1, la correcta y la misma que en los otros
  dos nodos, de modo que tampoco era un desfase de versión.
- Comparar el `/etc/containerd/config.toml` del nodo nuevo con el de un nodo que
  sí funcionaba. **Aquí apareció la diferencia**: el del nodo nuevo era mucho más
  corto e incluía `disabled_plugins = ["cri"]`.

#### Causa raíz

Dos hechos que solo fallan al coincidir.

El paquete `containerd.io` instala su propio fichero de configuración con la
interfaz de contenedores desactivada, porque su destinatario previsto es Docker,
que no la usa.

Y la tarea del rol que generaba la configuración estaba condicionada con
`creates: /etc/containerd/config.toml`, es decir, se omitía si el fichero ya
existía. Existía, puesto en su sitio por el propio paquete. La tarea siguiente,
que ajustaba `SystemdCgroup` con `lineinfile` y `backrefs: true`, buscaba un
parámetro que en esa configuración recortada no aparece, y al no encontrarlo
tampoco modificaba nada. Ninguna de las dos tareas dio error: las dos informaron
`ok`.

Los dos nodos antiguos no lo manifestaban porque su configuración se generó a
mano en junio, antes de escribir el rol.

#### Solución

Invertir el criterio del rol: la configuración deja de parchearse y pasa a
derivarse completa de la que el propio runtime declara como predeterminada
—que sí incluye la interfaz CRI—, modificando sobre ella únicamente el gestor de
grupos de control antes de escribirla.

```yaml
- name: Obtener la configuracion predeterminada que declara el runtime
  ansible.builtin.command:
    cmd: containerd config default
  register: containerd_configuracion_defecto
  changed_when: false

- name: Escribir la configuracion con el gestor de grupos de control de systemd
  ansible.builtin.copy:
    content: "{{ containerd_configuracion_defecto.stdout | regex_replace('SystemdCgroup = false', 'SystemdCgroup = true') }}\n"
    dest: /etc/containerd/config.toml
    mode: "0644"
  notify: Reiniciar containerd
```

Como la salida de `containerd config default` es determinista, la idempotencia
se conserva: en la segunda pasada el contenido coincide y no se escribe nada.

Se añadió además una comprobación explícita de que el complemento figura cargado
y en servicio, precedida de `meta: flush_handlers` para que el reinicio pendiente
se aplique antes de verificar.

#### Aprendizaje

Dos lecciones distintas, y conviene no mezclarlas.

Sobre la condición `creates`: una tarea que se omite cuando el fichero existe
presupone que el único origen posible de ese fichero es ella misma. En cuanto un
paquete lo instala por su cuenta, la condición protege exactamente el contenido
que había que corregir, y lo hace en silencio, informando `ok`. **Una tarea que
no se ejecuta no es una tarea que no haga falta.**

Sobre el alcance de las pruebas: la ejecución en modo comprobación contra los
nodos existentes había dado por buenos estos dos pasos, porque sobre una máquina
ya configurada a mano el estado deseado y el real coincidían por casualidad.
Validar la automatización contra lo que ya funciona demuestra que no rompe nada;
solo construir desde cero demuestra que construye. De aquí sale el criterio de
que ningún rol se considera terminado hasta haberse probado sobre una máquina
recién instalada.

→ Recogido en la memoria como **incidencia 14**.

### Problema 2 — Falso positivo en la prueba de idempotencia

#### Síntoma

Tras corregir el rol, la ejecución de verificación devolvía `changed=1` en lugar
del `changed=0` esperado. La única tarea con cambio era
`comun : Actualizar el indice de paquetes`.

#### Causa raíz

Esa tarea lleva `cache_valid_time: 3600`: refresca el índice de paquetes si tiene
más de una hora. Entre una ejecución y la siguiente había pasado un día, de modo
que refrescó y lo informó como cambio. No es un fallo de idempotencia —ninguna de
las 31 tareas que describen el estado del sistema tocó nada—, pero sí un informe
engañoso.

#### Solución

Declarar la tarea como operación sin efecto observable, con su justificación en
el propio código:

```yaml
  changed_when: false
```

#### Aprendizaje

Si la automatización informa de cambios que no son cambios, el administrador
aprende a ignorar esos avisos y acaba por no advertir los que sí importan. El
valor de un `changed=0` está precisamente en que sea infrecuente y significativo.

### Problema 3 — Intento de repetir una incorporación ya realizada

#### Síntoma

Al retomar el trabajo al día siguiente, sin recordar que el nodo ya se había
unido, se lanzó de nuevo `kubeadm join`:

```
[ERROR FileAvailable--etc-kubernetes-kubelet.conf]: /etc/kubernetes/kubelet.conf already exists
[ERROR Port-10250]: Port 10250 is in use
[ERROR FileAvailable--etc-kubernetes-pki-ca.crt]: /etc/kubernetes/pki/ca.crt already exists
```

#### Causa raíz

Ninguna: el nodo ya era miembro del clúster y su kubelet estaba en marcha. Las
comprobaciones previas detectaron que la operación ya estaba hecha.

#### Aprendizaje

`kubeadm join` no es idempotente, y por eso comprueba y falla en lugar de
sobrescribir la identidad del nodo. Es la misma preocupación que resuelve Ansible,
abordada al revés: donde una herramienta declarativa comprueba y no hace nada, una
imperativa comprueba y se niega. Mejor un error claro que un nodo con certificados
a medias. Si alguna vez hiciera falta repetir la incorporación de verdad, el
camino es `kubeadm reset` en el nodo y `kubectl delete node` en el plano de
control, nunca `--ignore-preflight-errors`.

---

## Decisiones tomadas

- **Derivar la configuración del runtime en lugar de parchearla.** Se descartó
  corregir el fichero que instala el paquete (añadiendo o quitando líneas sueltas)
  porque eso ata el rol a la forma exacta de un fichero que no controlamos y que
  puede cambiar con cualquier versión del paquete. Se opta por generarla entera a
  partir de la predeterminada del propio runtime y modificar un solo parámetro.

- **Qué se considera un cambio en la automatización.** La tarea de actualización
  del índice de paquetes informaba de cambio en cada ejecución posterior a la
  primera hora. Se decide declararla como tarea sin efecto observable
  (`changed_when: false`), en lugar de aceptar el falso positivo o eliminar la
  caducidad de la caché. Criterio: solo se informan como cambio las operaciones
  que modifican el estado declarado de la máquina; el mantenimiento de cachés no
  lo es.

- **Verificar dentro del rol y no fuera.** Se añade al rol una comprobación de que
  el complemento CRI está cargado, en lugar de confiar en que el fallo aparezca
  más adelante al ejecutar `kubeadm`. Un rol que deja la máquina en un estado
  inservible debe fallar él mismo, y no veinte minutos después, en otra
  herramienta y con un mensaje que no apunta a su verdadera causa.

- **Sistema operativo del nodo nuevo: Ubuntu Server 24.04 LTS.** Se mantiene la
  misma distribución que los nodos existentes, pese a haber considerado Debian y
  Rocky, para que el alta del nodo pruebe los roles y no la portabilidad entre
  distribuciones. Diversificar el sistema base habría introducido una segunda
  variable en la única prueba que acredita el requisito.

---

## Verificación

**`R03F01T02P01` — Idempotencia.** Segunda ejecución del mismo manual sobre el
nodo ya configurado:

```console
$ ansible-playbook -i inventario/produccion.ini playbooks/nodo-kubernetes.yml --limit k8s-worker-02
PLAY RECAP
k8s-worker-02 : ok=32  changed=0  unreachable=0  failed=0  skipped=1
```

**`R03F02T01P01` — Tiempo de alta.** Configuración desatendida del nodo en 48
segundos, frente a aproximadamente una hora del alta completa (instalación
interactiva del sistema operativo y direccionamiento incluidos) y frente a la
tarde que consumió el procedimiento manual de junio.

**Incorporación al clúster.** Tres nodos en estado `Ready`, con el nodo nuevo
ejecutando la misma versión de Kubernetes y del runtime que los anteriores:

```console
$ kubectl get nodes -o wide
k8s-master      Ready   control-plane   109d   v1.36.2   containerd://2.4.1
k8s-worker      Ready   <none>          109d   v1.36.2   containerd://2.4.1
k8s-worker-02   Ready   <none>          22h    v1.36.2   containerd://2.4.1
```

- [x] Evidencias recogidas: `./scripts/evidencias.sh 10 alta-nodo-worker-02`
- [x] Captura de pantalla: `evidencias/fase-10/f10-02-cluster-tres-nodos-ready.png`
- [ ] Captura de la idempotencia con el rol corregido:
      `evidencias/fase-10/f10-01-idempotencia-changed-0.png`
- [ ] Commit hecho

---

## Pendiente para la próxima

- Repetir y capturar la prueba de idempotencia tras aplicar `changed_when: false`,
  para que la evidencia corresponda al código que está en el repositorio y no al
  anterior.
- Trasladar a la memoria la incidencia 14 y el párrafo de cierre de la fase 10
  (el que sustituye al «se incorporarán en la entrega siguiente»), y renumerar las
  ilustraciones usando títulos automáticos y referencias cruzadas de Word.
- **Bloque 4 — reconstrucción de los nodos existentes.** Primero `k8s-worker`:
  drenarlo, sacarlo del clúster, recrear la máquina y aplicarle los roles. Con el
  clúster a dos nodos, comprobar que las cargas siguen sirviendo: es una prueba
  real de alta disponibilidad y conviene documentarla con la captura del servicio
  respondiendo. Después `k8s-master`, planificándolo para un rato en que no haga
  falta nada en marcha.
- Anotar que el nodo nuevo arrancó con Ubuntu 24.04.4 y kernel 6.8.0-100 frente a
  24.04.5 y 6.8.0-146 de los otros dos: la imagen de instalación de junio ya no es
  la que se descarga hoy. Un `apt upgrade` lo alinea sin tocar los paquetes
  retenidos, y esa ejecución mostrando los paquetes en espera es, en sí, la prueba
  de que la retención de la incidencia 12 funciona.

---

## Tiempo real dedicado

| Código RFTP | Estimado | Real | Desviación |
|---|---|---|---|
| R03F01T01 — Escritura y validación de los roles | 4 h | ⟨rellenar⟩ | |
| R03F01T02 — Alta del nodo e idempotencia | 3 h | ⟨rellenar⟩ | |

> Causa de la desviación, si la hay: depuración del rol del runtime de
> contenedores contra una máquina recién instalada, no prevista en la estimación
> inicial.
