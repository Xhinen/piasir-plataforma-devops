# Documento 8

# Ampliación del subsistema de almacenamiento y recuperación del sistema de copias de seguridad

**Proyecto:** Plataforma DevOps autoalojada para los servicios internos de una entidad local
**Autor:** Alberto Mira · **Fase del proyecto:** 9 (primera parte) · **Fecha de ejecución:** 4 y 5 de octubre de 2026

---

## Cómo usar este documento

Está escrito para que puedas pasarlo a la memoria con el mínimo trabajo de reescritura. La estructura sigue el orden real de ejecución, cada apartado explica primero *por qué* se hace algo y después *cómo* se hizo, y los comandos aparecen con su salida real.

Los bloques marcados así indican dónde conviene insertar una imagen:

> **📷 CAPTURA N — Título**
> **Dónde se obtiene:** ubicación exacta.
> **Qué debe verse:** el contenido concreto.
> **Pie de figura sugerido:** el texto que va debajo de la imagen.

Al final, en el anexo B, tienes el índice completo de capturas para que puedas hacerlas todas de una sentada.

---

## 1. Introducción y objetivos

La fase 9 del proyecto parte de una premisa que conviene explicitar porque gobierna todo lo que sigue: **antes de modificar una infraestructura en funcionamiento hay que conocer su estado real y garantizar que existe una vía de retorno**. Dicho en términos operativos, antes de actualizar el clúster de Kubernetes hacen falta dos cosas: un inventario fiable y unas copias de seguridad verificadas.

El inventario reveló que ninguna de las dos condiciones se cumplía. El sistema de copias llevaba setenta y cuatro días sin ejecutarse y el almacenamiento disponible era insuficiente para las cargas previstas en las fases siguientes. Esta primera parte de la fase 9 se dedica, por tanto, a resolver ambos problemas antes de tocar nada del clúster.

**Objetivos concretos:**

1. Levantar un inventario reproducible del estado de la plataforma y conservarlo como evidencia previa a cualquier modificación.
2. Diagnosticar las limitaciones de capacidad del subsistema de almacenamiento.
3. Evaluar la viabilidad de reutilizar hardware disponible aplicando criterios objetivos de estado y no suposiciones.
4. Ampliar el almacenamiento con separación física entre datos originales y copias de seguridad.
5. Restablecer el sistema de copias, corregir su causa de fallo y verificar su funcionamiento con una copia completa.

---

## 2. Marco teórico

### 2.1 Jerarquía de almacenamiento y criticidad del dato

No todos los datos tienen las mismas exigencias. Un sistema de almacenamiento bien diseñado los clasifica en al menos dos ejes:

- **Por patrón de acceso.** Las escrituras sincronizadas y de baja latencia —el registro de etcd en el plano de control de Kubernetes, el diario de una base de datos relacional— exigen almacenamiento de estado sólido. Un disco mecánico introduce latencias de búsqueda de milisegundos que, en el caso de etcd, se traducen en elecciones de líder fallidas y avisos de operaciones lentas, no en una simple pérdida de rendimiento.
- **Por criticidad y reproducibilidad.** Una imagen de contenedor se puede reconstruir desde su código fuente. Los documentos subidos por los usuarios, no. Colocar ambos en el mismo soporte, con las mismas garantías, es desperdiciar recursos en un caso y asumir riesgos innecesarios en el otro.

De aquí se deriva el diseño adoptado: unidad de estado sólido para sistemas operativos y bases de datos, disco mecánico para copias de seguridad y datos masivos reproducibles.

### 2.2 Deduplicación y la regla 3-2-1

Proxmox Backup Server no almacena copias completas sucesivas. Divide cada disco en fragmentos de tamaño variable, calcula el resumen criptográfico de cada uno y guarda únicamente los que no existen ya en el almacén. Dos consecuencias prácticas:

- El espacio ocupado crece mucho más despacio que el volumen lógico respaldado. En este proyecto, 80,0 GiB lógicos ocupan 11,9 GiB reales, un factor de deduplicación de 6,70.
- El espacio no se libera al eliminar un snapshot. Los fragmentos siguen en disco hasta que el recolector de basura (*garbage collection*) comprueba que ninguna copia los referencia. **Una política de retención sin recolector programado no libera nada**, y ese es precisamente un fallo que este proyecto ya había sufrido.

La regla 3-2-1 establece tres copias del dato, en dos soportes distintos, con una fuera de las instalaciones. Antes de esta intervención el proyecto no cumplía ni siquiera la segunda condición: original y copia convivían en el mismo disco físico, de modo que un único fallo de hardware las destruía a la vez.

### 2.3 SMART y criterios de aceptación de un disco usado

La tecnología SMART expone contadores internos del disco. Para decidir si una unidad usada es apta, cuatro atributos resultan determinantes y todos deben valer cero:

| Atributo | Qué indica |
|---|---|
| `Reallocated_Sector_Ct` | Sectores defectuosos ya sustituidos por reservas |
| `Current_Pending_Sector` | Sectores sospechosos pendientes de reasignar |
| `Offline_Uncorrectable` | Lecturas irrecuperables detectadas en verificación |
| `Reported_Uncorrect` | Errores no corregidos comunicados al sistema operativo |

El contador `Power_On_Hours` es más informativo que la antigüedad del modelo: el desgaste mecánico es proporcional a las horas de giro, no a los años transcurridos.

Conviene añadir una advertencia metodológica que se aplicó en este caso. Los atributos SMART solo reportan errores encontrados durante accesos reales; no garantizan que no existan sectores defectuosos en zonas nunca leídas. Por eso la verificación debe completarse con un **test extendido**, que recorre toda la superficie del disco.

> **📷 CAPTURA 1 — Esquema de almacenamiento por niveles**
> **Dónde se obtiene:** no es una captura, es un diagrama que debes dibujar (draw.io, Excalidraw o Mermaid).
> **Qué debe verse:** dos bloques de disco. En el SSD: discos de sistema de las VMs, etcd, PostgreSQL. En el disco mecánico: datastore de PBS y datos masivos. Flecha de copia desde el SSD hacia el disco mecánico.
> **Pie de figura sugerido:** "Figura 1. Distribución del almacenamiento por patrón de acceso y criticidad."

---

## 3. Inventario del estado inicial

### 3.1 Metodología

Se desarrolló un script de inventario (anexo A) de solo lectura que recoge, para cada nodo, el sistema operativo, los recursos, los runtimes de contenedores, el estado del clúster, los requisitos de kubeadm y la configuración de seguridad. Se ejecutó en los tres nodos y se complementó con seis comandos en el hipervisor.

El valor de automatizar esta recogida no es solo la comodidad: **garantiza que la fotografía del "antes" y la del "después" se tomen con el mismo criterio**, lo que permite comparar sin ambigüedades.

```bash
bash inventario.sh > inventario-$(hostname).txt
```

> **📷 CAPTURA 2 — Ejecución del inventario**
> **Dónde se obtiene:** terminal, conectado por SSH a `docker-01`.
> **Qué debe verse:** la cabecera del script con el nombre del nodo y la fecha, y al menos las secciones de sistema operativo y recursos.
> **Pie de figura sugerido:** "Figura 2. Ejecución del script de inventario sobre el nodo docker-01."

### 3.2 Resultados

**Hipervisor Proxmox VE:**

| Elemento | Valor |
|---|---|
| Versión | Proxmox VE 9.2.0, kernel 7.0.14-11-pve, pve-manager 9.2.10 |
| Memoria | 31 GiB totales, 13 GiB disponibles |
| Almacenamiento físico | Un único SSD Kingston SV300S37A120G de 111,8 GB |
| Pool ZFS | 36,5 GiB libres |
| VMs en marcha | docker-01 (8 GiB), k8s-master (8 GiB), k8s-worker (8 GiB) |
| VMs detenidas | dc01 (4 GiB), cli-win (3 GiB) |
| Contenedor LXC | pbs (104), **detenido** |

**Nodos:**

| Nodo | SO | CPU/RAM | Disco | Kubernetes |
|---|---|---|---|---|
| docker-01 | Ubuntu 24.04.4 LTS | 4 vCPU / 7,7 GiB | 29 GiB, 53 % usado | Docker 29.6.2, clúster kind residual |
| k8s-master | Ubuntu 24.04.4 LTS | 2 vCPU / 7,7 GiB | 24 GiB, 48 % usado | kubelet y kubeadm 1.36.2 |
| k8s-worker | Ubuntu 24.04.4 LTS | 2 vCPU / 7,7 GiB | 24 GiB, 59 % usado | kubelet y kubeadm 1.36.2 |

Comprobaciones superadas en ambos nodos del clúster: swap desactivada, los dos módulos de kernel requeridos cargados, reenvío de IP activo, fail2ban y actualizaciones automáticas en funcionamiento. El Gateway responde en `192.168.18.240` con estado `PROGRAMMED=True`.

> **📷 CAPTURA 3 — Estado del clúster antes de la intervención**
> **Dónde se obtiene:** terminal en `k8s-master`.
> **Qué debe verse:** salida de `kubectl get nodes -o wide` con los dos nodos en `Ready` y versión v1.36.2.
> **Pie de figura sugerido:** "Figura 3. Estado del clúster de Kubernetes previo a la intervención."

### 3.3 Diagnóstico

El inventario identificó tres problemas, ordenados por gravedad.

**Primero, el sistema de copias llevaba 74 días inactivo.** El contenedor de PBS estaba detenido y el almacenamiento asociado figuraba como `inactive`. Los únicos snapshots existentes databan del 22 de julio.

**Segundo, el almacenamiento era insuficiente para las fases siguientes.** Con 36,5 GiB libres en el único disco del sistema era inviable alojar la forja de código con su base de datos y su registro de imágenes, más el servicio de almacenamiento de documentos. A esto se añadía un riesgo estructural: los discos virtuales suman 170 GB asignados sobre un disco físico de 110 GB mediante aprovisionamiento fino, de modo que **agotar el pool no afectaría a un servicio sino a las tres máquinas virtuales simultáneamente**.

**Tercero, el datastore de copias estaba infradimensionado.** Veinte GiB totales al 61 % de ocupación, con 7,8 GiB libres para tres máquinas virtuales con histórico. Este hallazgo explica retrospectivamente un incidente anterior del proyecto, en el que el recolector de basura quedó bloqueado por falta de espacio: no fue un suceso aislado, sino la consecuencia previsible de un dimensionado incorrecto.

> **📷 CAPTURA 4 — Almacenamiento antes de la ampliación**
> **Dónde se obtiene:** terminal del host Proxmox.
> **Qué debe verse:** salida de `pvesm status` con `pbs-tfg` al 61 % y, debajo, `lsblk` mostrando un único disco físico.
> **Pie de figura sugerido:** "Figura 4. Situación del almacenamiento previa a la ampliación: un único disco físico y el almacén de copias al 61 %."

---

## 4. Liberación de recursos previa

Antes de añadir hardware se aplicó un principio elemental de administración: **primero se recupera lo que se está desperdiciando**.

Se detectó un clúster de pruebas creado con kind durante la fase 4 del proyecto, con 111 días de antigüedad, su propio controlador de entrada desplegado y un balanceador en estado pendiente que nunca llegaría a resolverse. Había cumplido su función formativa y estaba documentado, de modo que podía eliminarse sin pérdida.

```bash
kind delete cluster --name aprendizaje
docker image prune -a
```

**Resultado:** 1,287 GB de imágenes liberadas dentro de la máquina virtual y, sobre todo, 4,4 GiB recuperados en el pool del hipervisor, que pasó de 36,5 a 41,0 GiB libres. La ocupación de `docker-01` bajó del 53 % al 38 %.

Merece la pena señalar por qué el espacio se liberó también en el host. Al borrar ficheros dentro de una máquina virtual, el sistema invitado marca los bloques como libres, pero el hipervisor no se entera salvo que el disco virtual tenga activada la opción de descarte (`discard`). Que aquí sí ocurriera confirma que las máquinas virtuales están correctamente configuradas en ese aspecto, algo que se pasa por alto con frecuencia.

> **📷 CAPTURA 5 — Liberación de recursos**
> **Dónde se obtiene:** terminal en `docker-01`.
> **Qué debe verse:** la salida de `kind delete cluster` seguida de `docker image prune -a` con la línea "Total reclaimed space", y un `df -h /` final.
> **Pie de figura sugerido:** "Figura 5. Eliminación del clúster de prácticas y recuperación de espacio en docker-01."

---

## 5. Evaluación del hardware disponible

### 5.1 Planteamiento

Se disponía de un disco mecánico reutilizable. La pregunta no era si tenía capacidad suficiente —sobraba— sino si su estado permitía confiarle copias de seguridad. Aquí rige un principio que no admite excepciones: **el soporte de las copias debe ser más fiable que aquello que protege, nunca menos**.

### 5.2 Identificación y análisis SMART

```bash
sudo smartctl -i -H -A /dev/sdc
```

| Dato | Valor |
|---|---|
| Modelo | Seagate Barracuda 7200.10, ST3250820AS |
| Número de serie | 3QE08JMT |
| Capacidad | 250.059.350.016 bytes |
| Salud general | **PASSED** |
| `Power_On_Hours` | **5000** |
| `Reallocated_Sector_Ct` | **0** |
| `Current_Pending_Sector` | **0** |
| `Offline_Uncorrectable` | **0** |
| `Reported_Uncorrect` | **0** |
| `Spin_Retry_Count` | 0 |
| `UDMA_CRC_Error_Count` | 0 |
| Temperatura | 35 °C |

El modelo corresponde a una serie de 2006, lo que inicialmente llevó a descartar la unidad. **El dato que invirtió la decisión fue el de horas de funcionamiento**: 5.000 horas equivalen a unos 208 días de giro. Una unidad de veinte años de antigüedad con ese contador ha pasado prácticamente toda su vida almacenada, no en servicio. Como el desgaste mecánico depende de las horas de giro y no del calendario, la unidad se encuentra lejos de su límite.

Conviene documentar también una lectura que induce a error con frecuencia. Los atributos `Raw_Read_Error_Rate` y `Seek_Error_Rate` mostraban valores en bruto de 9.806.443 y 945.140.736.495 respectivamente. En los discos Seagate ese campo codifica conjuntamente un contador de errores y el total de operaciones realizadas, por lo que el número absoluto carece de significado directo. La interpretación correcta compara las columnas `VALUE` y `THRESH`: 105 frente a 6 y 61 frente a 30, ambas holgadamente por encima del umbral de fallo.

> **📷 CAPTURA 6 — Análisis SMART del disco**
> **Dónde se obtiene:** terminal del equipo de trabajo, con el disco conectado.
> **Qué debe verse:** la salida de `sudo smartctl -i -H -A /dev/sdc` completa, o al menos desde "START OF INFORMATION SECTION" hasta el atributo 199. Debe leerse `PASSED` y los ceros en los atributos 5, 197 y 198.
> **Pie de figura sugerido:** "Figura 6. Informe SMART del disco evaluado: salud correcta y 5.000 horas de funcionamiento."

### 5.3 Test extendido

```bash
sudo smartctl -t long /dev/sdc      # 92 minutos
sudo smartctl -l selftest /dev/sdc
```

```
Num  Test_Description    Status                  Remaining  LifeTime(hours)
# 1  Extended offline    Completed without error    00%         5000
```

El test recorrió los 250 GB sector por sector sin un solo error de lectura. Con esto, la unidad quedó aceptada.

Nota operativa: la columna se llama `Remaining`, no progreso. Durante la ejecución muestra el porcentaje **pendiente**, de modo que `90%` significa que acaba de empezar. Además, el disco informa en tramos del 10 %, por lo que no existe un seguimiento más fino que diez actualizaciones a lo largo de la prueba.

> **📷 CAPTURA 7 — Resultado del test extendido**
> **Dónde se obtiene:** terminal del equipo de trabajo.
> **Qué debe verse:** la salida de `sudo smartctl -l selftest /dev/sdc` con la línea `Completed without error` y `00%`.
> **Pie de figura sugerido:** "Figura 7. Test extendido superado: verificación completa de la superficie del disco."

### 5.4 Decisión y justificación

Se acepta la unidad, con tres consideraciones que deben constar:

1. El planteamiento correcto no es "disco fiable frente a disco poco fiable", sino **un disco frente a dos**. Con las copias en el mismo soporte que los originales, un único fallo lo destruye todo. Trasladarlas a una segunda unidad, aunque sea más antigua, mejora objetivamente la situación.
2. La decisión se toma sobre datos verificados, no sobre suposiciones. Tanto la hipótesis inicial de descarte por antigüedad como su revisión posterior quedan documentadas, porque el razonamiento tiene más valor que la conclusión.
3. El riesgo asumido se vigila: en la fase 15 se activará el colector `smartmon` de node_exporter para que Prometheus supervise los atributos del disco, con alerta si `Reallocated_Sector_Ct` o `Current_Pending_Sector` dejan de ser cero.

---

## 6. Preparación del disco

El disco se preparó en un equipo independiente antes de instalarlo en el servidor, de forma que el tiempo de parada del hipervisor se redujera al mínimo imprescindible. La tabla de particiones GPT y los sistemas de ficheros ext4 son portables entre sistemas Linux, así que el trabajo previo es plenamente aprovechable.

### 6.1 Identificación segura

```bash
ls -l /dev/disk/by-id/ | grep -i 3QE08JMT
set DISCO /dev/disk/by-id/ata-ST3250820AS_3QE08JMT
```

**Esta es la precaución más importante de todo el procedimiento.** Las letras de dispositivo (`/dev/sda`, `/dev/sdb`) se asignan en el orden en que el kernel detecta los discos y cambian al añadir o quitar hardware. Trabajar con la ruta por identificador, que incorpora el número de serie, elimina la posibilidad de formatear la unidad equivocada. En un servidor con tres máquinas virtuales en producción, ese error no tiene vuelta atrás.

La prueba de que la precaución no era teórica llegó después: en el equipo de preparación el disco era `sdc`, mientras que al instalarlo en el servidor pasó a ser `sdb`.

### 6.2 Particionado

Se detectó que el entorno de escritorio había montado automáticamente la partición NTFS preexistente. Un disco montado no se puede reparticionar, así que el primer paso fue desmontarlo.

```bash
udisksctl unmount -b /dev/sdc1
sudo wipefs -a $DISCO-part1
sudo wipefs -a $DISCO
sudo sgdisk --zap-all $DISCO
sudo sgdisk -n 1:0:+150G -t 1:8300 -c 1:"pbs-datastore" $DISCO
sudo sgdisk -n 2:0:0     -t 2:8300 -c 2:"bulk-data"     $DISCO
sudo partprobe $DISCO
```

**Justificación de las dos particiones.** Podría haberse creado una sola que abarcara el disco completo, pero separar el almacén de copias de los datos masivos establece un límite físico entre ambos. Si el histórico de copias creciera sin control no podría invadir el espacio de los datos de usuario, ni al contrario. Es una decisión de diseño deliberada, no una consecuencia del procedimiento.

### 6.3 Formateo

```bash
sudo mkfs.ext4 -L pbs-datastore -m 0 -E lazy_itable_init=0,lazy_journal_init=0 $DISCO-part1
sudo mkfs.ext4 -L bulk-data     -m 0 -E lazy_itable_init=0,lazy_journal_init=0 $DISCO-part2
```

Dos opciones merecen explicación:

- `-m 0` elimina el 5 % de bloques que ext4 reserva para el superusuario. Esa reserva evita que un disco lleno deje el sistema inoperable, lo que tiene sentido en la partición raíz pero no en un volumen de datos: aquí serían unos 11 GiB inutilizados entre ambas particiones.
- `lazy_itable_init=0,lazy_journal_init=0` fuerza la inicialización completa de las tablas de inodos en el momento del formateo. Por defecto ext4 lo difiere a un proceso en segundo plano tras el primer montaje, lo que habría provocado escrituras del disco por su cuenta justo durante las primeras copias de seguridad.

**Resultado:**

| Partición | Tamaño | Etiqueta | UUID |
|---|---|---|---|
| 1 | 150 GiB | `pbs-datastore` | `3b42bbb5-bb89-4b11-a085-bf4d2c02a703` |
| 2 | 82,9 GiB | `bulk-data` | `405c0721-fb18-4fca-a50b-8e006ae28759` |

> **📷 CAPTURA 8 — Disco preparado**
> **Dónde se obtiene:** terminal del equipo de trabajo.
> **Qué debe verse:** la salida conjunta de `lsblk -o NAME,SIZE,FSTYPE,LABEL` y `sudo blkid` para las dos particiones, con las etiquetas y los UUID.
> **Pie de figura sugerido:** "Figura 8. Disco particionado y formateado, con las dos particiones etiquetadas y sus identificadores únicos."

---

## 7. Integración en el hipervisor

### 7.1 Parada ordenada del servidor

```bash
qm shutdown 103        # k8s-worker
qm shutdown 102        # k8s-master
qm shutdown 101        # docker-01
pct shutdown 104       # PBS
shutdown -h now
```

El orden no es arbitrario. Se detiene primero el nodo de trabajo y después el plano de control, de modo que el control-plane siga disponible mientras el worker se retira limpiamente. Un apagado brusco de un nodo con etcd puede dejar su base de datos en un estado que requiera reparación manual.

### 7.2 Montaje persistente

```bash
mkdir -p /mnt/pbs-store /mnt/bulk
cp /etc/fstab /etc/fstab.bak

cat >> /etc/fstab <<'EOF'
UUID=3b42bbb5-bb89-4b11-a085-bf4d2c02a703  /mnt/pbs-store  ext4  defaults,nofail  0  2
UUID=405c0721-fb18-4fca-a50b-8e006ae28759  /mnt/bulk       ext4  defaults,nofail  0  2
EOF

systemctl daemon-reload
mount -a
findmnt --verify --verbose
```

Tres decisiones a documentar:

- **Montaje por UUID.** Como se anticipó, el disco que en el equipo de preparación era `sdc` pasó a ser `sdb` en el servidor. Un `fstab` escrito con letras de dispositivo habría provocado un fallo de arranque.
- **Opción `nofail`.** Sin ella, si el disco fallara o se desconectara, el servidor no completaría el arranque y quedaría en modo de emergencia. En un hipervisor que aloja tres máquinas virtuales, eso convierte un disco perdido en un servidor inaccesible.
- **Verificación previa con `findmnt --verify`.** Un error de sintaxis en `fstab` solo se manifiesta en el siguiente reinicio, cuando ya es tarde. Esta orden lo detecta antes.

El resultado fue `Success, no errors or warnings detected`, con 147 GiB disponibles en `/mnt/pbs-store` y 82 GiB en `/mnt/bulk`.

> **📷 CAPTURA 9 — Disco integrado en el hipervisor**
> **Dónde se obtiene:** terminal del host Proxmox, tras instalar el disco.
> **Qué debe verse:** `lsblk -o NAME,SIZE,SERIAL,MODEL,FSTYPE,LABEL` mostrando el disco como `sdb` con sus dos particiones etiquetadas, seguido de `df -h /mnt/pbs-store /mnt/bulk`.
> **Pie de figura sugerido:** "Figura 9. Disco reconocido por el hipervisor y montado de forma persistente. Obsérvese el cambio de identificador de sdc a sdb respecto a la figura 8."

> **📷 CAPTURA 10 — Validación del fstab**
> **Dónde se obtiene:** terminal del host Proxmox.
> **Qué debe verse:** la salida de `findmnt --verify --verbose` terminando en "Success, no errors or warnings detected".
> **Pie de figura sugerido:** "Figura 10. Validación de la configuración de montaje antes del siguiente reinicio."

### 7.3 Acceso desde el contenedor de PBS

Proxmox Backup Server se ejecuta dentro de un contenedor LXC y no tiene visibilidad sobre el sistema de ficheros del host. Es necesario enlazar el directorio mediante un punto de montaje.

```bash
pct config 104              # comprobar si es unprivileged
pct stop 104
pct set 104 -mp0 /mnt/pbs-store,mp=/mnt/hdd
chown -R 100034:100034 /mnt/pbs-store
pct start 104
```

**El `chown` es el paso crítico y el que más problemas causa.** El contenedor está configurado como *unprivileged*, lo que significa que los identificadores de usuario del interior se desplazan 100.000 posiciones al mapearse sobre el host. PBS escribe como el usuario `backup`, que en Debian es el UID 34; visto desde el host, ese usuario es el 100034. Si el directorio no se ajusta, el contenedor lo ve como propiedad de `nobody:nogroup` y la creación del datastore falla con un error de permisos que no sugiere su verdadera causa.

Comprobación desde dentro del contenedor:

```
root@pbs:~# ls -la /mnt/hdd
drwxr-xr-x 3 backup backup  4096 Oct  5 08:47 .
root@pbs:~# id backup
uid=34(backup) gid=34(backup) groups=34(backup),26(tape)
```

Que aparezca `backup backup` y no `nobody nogroup` confirma que el mapeo es correcto.

> **📷 CAPTURA 11 — Punto de montaje en el contenedor**
> **Dónde se obtiene:** terminal del host, tras `pct enter 104`.
> **Qué debe verse:** `df -h /mnt/hdd`, `ls -la /mnt/hdd` con propietario `backup backup`, e `id backup` mostrando uid=34.
> **Pie de figura sugerido:** "Figura 11. Verificación del mapeo de identificadores en el contenedor no privilegiado."

---

## 8. Configuración de Proxmox Backup Server

### 8.1 Creación del datastore

```bash
proxmox-backup-manager datastore create tfg-store /mnt/hdd/tfg-store
proxmox-backup-manager acl update /datastore/tfg-store DatastorePowerUser \
  --auth-id 'root@pam!pve-backup'
proxmox-backup-manager acl list
```

Se reutiliza el token de API existente en lugar de crear uno nuevo, aplicando el principio de mínimo privilegio ya establecido en la fase 8: Proxmox VE accede al almacén mediante un token con permisos acotados, no con la contraseña del administrador.

El nombre `tfg-store` se eligió teniendo en cuenta que los datastores de PBS **no se pueden renombrar**, y que el anterior debía permanecer operativo hasta validar el nuevo.

### 8.2 Programación del recolector de basura

```bash
proxmox-backup-manager datastore update tfg-store --gc-schedule 'sat 02:00'
```

Un datastore creado por línea de comandos no incorpora ninguna planificación de recolección. Sin ella, la política de retención marcaría los snapshots como eliminados pero el espacio nunca se liberaría, reproduciendo exactamente el fallo que este proyecto ya había documentado. Se programa en sábado de madrugada, fuera de la ventana de copias.

### 8.3 Alta del almacenamiento en Proxmox VE

```bash
pvesm add pbs pbs-tfg-hdd \
  --server 192.168.18.55 \
  --datastore tfg-store \
  --username 'root@pam!pve-backup' \
  --fingerprint '4e:a1:88:...:e0:29' \
  --content backup \
  --password "$(cat /etc/pve/priv/storage/pbs-tfg.pw)"
```

El último argumento merece mención en la memoria como buena práctica: en lugar de escribir el secreto del token en la línea de órdenes, se lee del fichero donde Proxmox ya lo custodia. Así la credencial no queda registrada en el historial del intérprete de comandos, que es una vía de fuga de secretos más habitual de lo que suele suponerse.

> **📷 CAPTURA 12 — Almacenamiento nuevo dado de alta**
> **Dónde se obtiene:** terminal del host Proxmox.
> **Qué debe verse:** `pvesm status` con las cuatro entradas, incluida `pbs-tfg-hdd` en estado `active` con unos 146 GiB y ocupación próxima a cero.
> **Pie de figura sugerido:** "Figura 12. Almacén de copias ampliado: 146,6 GiB frente a los 20 GiB anteriores."

### 8.4 Reconfiguración del trabajo de copia

```bash
pvesh set /cluster/backup/backup-c5f22ce6-c292 --storage pbs-tfg-hdd
```

Se mantuvieron el resto de parámetros: ejecución diaria a las 03:00, modo *snapshot* y retención de 3 copias diarias, 2 semanales y 1 mensual.

---

## 9. Verificación: copia completa

El criterio de cierre de esta fase no es que la configuración parezca correcta, sino que **una copia real se complete con éxito**.

```
INFO: starting new backup job: vzdump 101 102 103 --storage pbs-tfg-hdd --mode snapshot
INFO: Backup job finished successfully
TASK OK
```

| VM | Nombre | Volumen | Duración | Velocidad | Datos nulos |
|---|---|---|---|---|---|
| 101 | docker-01 | 30,0 GiB | 1 m 46 s | 289,8 MiB/s | 22,30 GiB (74 %) |
| 102 | k8s-master | 25,0 GiB | 1 m 41 s | 256,0 MiB/s | 17,24 GiB (68 %) |
| 103 | k8s-worker | 25,0 GiB | 1 m 54 s | 224,6 MiB/s | 14,78 GiB (59 %) |
| | **Total** | **80,0 GiB** | **5 m 21 s** | | |

Dos aspectos del registro merecen comentario en la memoria.

**La copia es consistente, no una instantánea en bruto.** El registro muestra, para cada máquina:

```
INFO: issuing guest-agent 'fs-freeze' command
INFO: starting backup via QMP command
INFO: issuing guest-agent 'fs-thaw' command
```

El agente invitado congela el sistema de ficheros del interior mientras se toma la instantánea y lo descongela inmediatamente después. Sin ese mecanismo, la copia capturaría un sistema de ficheros en un estado intermedio, con escrituras a medias, exactamente igual que si se hubiera cortado la corriente. La diferencia entre una copia restaurable y una que tal vez arranque está en esas tres líneas.

**El modo *snapshot* no interrumpe el servicio.** Las tres máquinas virtuales permanecieron en funcionamiento durante toda la operación.

> **📷 CAPTURA 13 — Registro de la copia completa**
> **Dónde se obtiene:** interfaz web de Proxmox, en Datacenter → Backup → el trabajo → pestaña de la tarea; o bien en el registro de tareas del nodo.
> **Qué debe verse:** el final del registro con las tres VMs completadas y la línea `TASK OK`. Si es muy largo, capturar el resumen de cada VM.
> **Pie de figura sugerido:** "Figura 13. Primera copia completa sobre el almacén ampliado, con las tres máquinas virtuales respaldadas sin interrupción de servicio."

> **📷 CAPTURA 14 — Snapshots en el datastore**
> **Dónde se obtiene:** interfaz web de PBS, en `https://192.168.18.55:8007`, apartado Datastore → tfg-store → Content.
> **Qué debe verse:** los tres snapshots con la fecha del 5 de octubre y su tamaño.
> **Pie de figura sugerido:** "Figura 14. Contenido del nuevo almacén tras la primera copia."

---

## 10. Incidencias documentadas

Las incidencias siguen el patrón síntoma → causa raíz → solución → aprendizaje. Son material de defensa de primer orden: demuestran capacidad de diagnóstico, que es lo que distingue a un técnico de alguien que ejecuta instrucciones.

### Incidencia 1 — Pérdida de la clave privada de administración

**Síntoma.** El acceso por SSH a los tres nodos devuelve `Permission denied (publickey)`, sin solicitar contraseña.

**Diagnóstico.** La ejecución con `ssh -v` muestra, para los seis tipos de clave que el cliente prueba por defecto:

```
debug1: no pubkey loaded from /home/xhinen/.ssh/id_ed25519
debug1: identity file /home/xhinen/.ssh/id_ed25519 type -1
```

El valor `type -1` indica que el fichero no existe. El cliente no dispone de ninguna clave que ofrecer. La presencia de un `known_hosts` con entrada para los servidores confirma que la conexión había funcionado antes desde ese equipo.

**Causa raíz.** Ausencia de la clave privada en el equipo de administración, sin copia de respaldo. Al estar desactivada la autenticación por contraseña como parte del endurecimiento de la fase 8, no existía vía alternativa de acceso por red.

**Solución.** Generación de un nuevo par de claves y autorización de la clave pública en cada nodo a través de la consola del hipervisor, que no depende del servicio SSH.

**Aprendizaje.** El endurecimiento de un sistema reduce la superficie de ataque y, simultáneamente, elimina las vías de recuperación alternativas. Un entorno con autenticación exclusivamente por clave exige una política de custodia de esas claves, y un acceso fuera de banda —en este caso la consola del hipervisor— deja de ser una comodidad para convertirse en un requisito operativo.

### Incidencia 2 — Exposición de la clave privada durante su distribución

**Síntoma.** Tras copiar la clave en el servidor, el acceso sigue denegado. La inspección de `authorized_keys` revela:

```
-----BEGIN OPENSSH PRIVATE KEY-----
```

**Causa raíz.** Al distribuir la clave mediante un servidor HTTP temporal se sirvió el directorio `~/.ssh` completo y se descargó el fichero `id_ed25519` en lugar de `id_ed25519.pub`. La omisión de la extensión provocó que se publicara y copiara la **clave privada**.

**Impacto.** La clave privada se transmitió en claro por la red local y quedó escrita en el disco de un servidor. Debe considerarse comprometida.

**Solución.** Revocación del par de claves, generación de uno nuevo con frase de paso, redistribución de la clave pública en los tres nodos mediante sobrescritura de `authorized_keys` —no mediante adición— para eliminar la autorización de la clave antigua, y publicación limitada a un directorio que contuviera exclusivamente el fichero `.pub`.

**Aprendizaje.** Dos lecciones. La primera, de procedimiento: nunca exponer el directorio de claves, sino copiar el fichero público a una ubicación independiente antes de compartirlo. La segunda, de criterio: ante la exposición de una credencial la respuesta correcta es siempre la revocación, por improbable que parezca el aprovechamiento. Una clave expuesta no se reutiliza.

> **📷 CAPTURA 15 — Diagnóstico de la incidencia de SSH**
> **Dónde se obtiene:** terminal del equipo de administración.
> **Qué debe verse:** las líneas de `ssh -v` con `type -1` repetido y el `Permission denied (publickey)` final.
> **Pie de figura sugerido:** "Figura 15. Diagnóstico de la ausencia de claves mediante el modo detallado del cliente SSH."

### Incidencia 3 — Sistema de copias inactivo durante 74 días

**Síntoma.** El inventario revela que los únicos snapshots existentes son del 22 de julio, 74 días antes. El almacenamiento `pbs-tfg` figura como `inactive`.

**Causa raíz.** El contenedor LXC que aloja Proxmox Backup Server no tenía activado el arranque automático. Tras un reinicio del hipervisor el contenedor no volvió a iniciarse y, con él, el almacén de copias quedó inaccesible.

**Solución.**

```bash
pct set 104 -onboot 1
```

**Aprendizaje.** Es el hallazgo más valioso de toda la fase. Un sistema de copias que falla en silencio es **peor que no tener ninguno**, porque genera una confianza que no se corresponde con la realidad: durante dos meses y medio se operó sobre la plataforma creyendo que existía una red de seguridad que no estaba. De aquí se deriva un requisito de diseño que se incorpora a la fase 15: la monitorización no debe vigilar únicamente que una copia *falle*, sino que **no exista copia reciente**. La diferencia es decisiva, porque un trabajo que falla genera un evento mientras que un trabajo que nunca se ejecuta no genera nada.

### Incidencia 4 — Avisos de copia no operativos

**Síntoma.** El trabajo de copia está configurado con `mailnotification failure` y `notification-mode legacy-sendmail`, pero el sistema de correo del hipervisor no está configurado.

**Causa raíz.** Configuración de notificaciones heredada de los valores por defecto, sin un transporte de correo funcional detrás.

**Estado.** Pendiente de resolución en la fase 15, junto con la alerta de ausencia de copia reciente.

**Aprendizaje.** Es la segunda mitad de la incidencia anterior y refuerza la misma idea: la cadena de supervisión solo es tan fuerte como su último eslabón. Un aviso correctamente generado que no llega a un destinatario equivale a no haberlo generado.

### Incidencia 5 — Datastore infradimensionado

**Síntoma.** El almacén de copias dispone de 20 GiB con un 61 % de ocupación y únicamente 7,8 GiB libres, para tres máquinas virtuales que suman 80 GiB lógicos.

**Causa raíz.** Dimensionado inicial insuficiente, sin margen para el histórico de retención ni para el crecimiento previsto del proyecto.

**Solución.** Migración a un almacén de 146,6 GiB sobre disco independiente.

**Aprendizaje.** Este hallazgo explica retrospectivamente el incidente de recolección de basura bloqueada que se documentó en la fase 8. Lo que entonces se interpretó como un suceso puntual era en realidad el síntoma de un problema de dimensionado. Investigar la causa raíz de un incidente, en lugar de limitarse a resolverlo, habría anticipado este problema dos meses antes.

### Incidencia 6 — Montaje automático impidiendo el particionado

**Síntoma.** El disco a preparar aparece con su partición NTFS montada automáticamente por el entorno de escritorio.

**Causa raíz.** El servicio de montaje automático de medios extraíbles detecta y monta cualquier sistema de ficheros reconocible al conectar la unidad.

**Solución.** Desmontaje explícito con `udisksctl unmount` antes de operar sobre el disco.

**Aprendizaje.** Las operaciones sobre dispositivos de bloque requieren comprobar el estado de montaje previamente. Un entorno de escritorio introduce automatismos que no existen en un servidor y que pueden interferir con tareas de administración.

---

## 11. Resultados

| Indicador | Antes | Después |
|---|---|---|
| Discos físicos | 1 (SSD 111,8 GB) | 2 (SSD 111,8 GB + HDD 250 GB) |
| Espacio libre en el pool del sistema | 36,5 GiB | 43,9 GiB |
| Capacidad del almacén de copias | 20 GiB (61 % usado) | 146,6 GiB (8 % usado) |
| Separación física entre original y copia | **No** | **Sí** |
| Copia más reciente | 22 de julio (74 días) | 5 de octubre (mismo día) |
| Arranque automático del servicio de copias | **No** | **Sí** |
| Recolección de basura programada | No, en el almacén nuevo | Sábados a las 02:00 |
| Espacio disponible para datos masivos | 0 | 82 GiB |
| Factor de deduplicación medido | — | 6,70 |

> **📷 CAPTURA 16 — Comparativa final**
> **Dónde se obtiene:** terminal del host Proxmox, al terminar todo el proceso.
> **Qué debe verse:** `pvesm status` final, con `pbs-tfg-hdd` ya con la copia hecha. Compárese con la figura 4.
> **Pie de figura sugerido:** "Figura 16. Estado del almacenamiento tras la ampliación, con el almacén de copias en disco independiente."

---

## 12. Conclusiones y trabajo pendiente

Esta primera parte de la fase 9 no estaba prevista con este alcance. La planificación contemplaba un inventario rápido seguido de la actualización del clúster, y lo que el inventario reveló obligó a detenerse y resolver dos problemas previos. Esa desviación merece defenderse, no disculparse: **actualizar el plano de control de un clúster sin copias de seguridad válidas habría sido una imprudencia**, y el hecho de que el inventario lo detectara justifica por sí solo la metodología de medir antes de actuar.

La plataforma queda ahora con separación física entre datos y copias, un almacén siete veces mayor, el servicio de copias restablecido con arranque automático y recolección programada, y una copia completa verificada de las tres máquinas virtuales.

**Pendiente en la segunda parte de la fase 9:**

1. Actualizar Kubernetes de 1.36.2 a 1.36.4 mediante kubeadm, primero el plano de control y después el nodo de trabajo.
2. Actualizar Envoy Gateway de 1.5.4 a 1.9.x, dado que la versión instalada está fuera del periodo de soporte.
3. Aplicar parches menores a Calico y al motor de contenedores.
4. Retirar el datastore antiguo de 20 GiB una vez consolidado el nuevo, liberando ese espacio del pool del sistema.
5. Dar de alta la partición de datos masivos como almacenamiento de Proxmox, para su uso en las fases posteriores.

**Diferido a fases posteriores:**

- Alerta de ausencia de copia reciente y configuración de un transporte de notificaciones operativo (fase 15).
- Supervisión de los atributos SMART del disco mediante Prometheus (fase 15).
- Traslado de las copias fuera de las instalaciones para completar la regla 3-2-1, que con dos discos en el mismo equipo no puede satisfacerse por completo. Esta limitación debe constar expresamente en la memoria.

---

## Anexo A — Script de inventario

Se adjunta como fichero `inventario.sh`. Es de solo lectura y no modifica configuración alguna. Recoge por cada nodo: sistema operativo y kernel, recursos de CPU, memoria y disco, versiones de los runtimes de contenedores, estado del clúster de Kubernetes con sus nodos, cargas de trabajo, almacenamiento y entrada de tráfico, cumplimiento de los requisitos de kubeadm y estado de los servicios de seguridad.

Para el hipervisor se emplearon seis órdenes complementarias: `pveversion -v`, `free -h`, `pvesm status`, `qm list`, `pct list` y `lsblk`.

**Limitación detectada.** Las comprobaciones de la configuración de SSH (`PermitRootLogin`, `PasswordAuthentication`) devuelven valores vacíos al ejecutarse sin privilegios, ya que `sshd -T` los requiere. Para obtener esos datos el script debe ejecutarse con `sudo`.

---

## Anexo B — Índice de capturas

Lista completa para poder obtenerlas de una vez. Las marcadas como *reconstruible* pueden rehacerse ahora si no se capturaron en su momento; las marcadas como *no reconstruible* corresponden a estados ya superados y, si no se guardaron, deben sustituirse por la transcripción del texto en un bloque de código.

| Nº | Contenido | Origen | ¿Reconstruible? |
|---|---|---|---|
| 1 | Esquema de almacenamiento por niveles | Diagrama propio | Sí |
| 2 | Ejecución del script de inventario | Terminal en docker-01 | Sí |
| 3 | Estado del clúster | Terminal en k8s-master | Sí |
| 4 | Almacenamiento antes de la ampliación | Terminal del host | **No** |
| 5 | Liberación de recursos | Terminal en docker-01 | **No** |
| 6 | Informe SMART | Terminal con el disco conectado | Sí |
| 7 | Test extendido superado | Terminal con el disco conectado | Sí |
| 8 | Disco particionado y formateado | Terminal del equipo de trabajo | Parcial |
| 9 | Disco integrado en el hipervisor | Terminal del host | Sí |
| 10 | Validación del fstab | Terminal del host | Sí |
| 11 | Punto de montaje en el contenedor | Terminal del host, dentro del LXC | Sí |
| 12 | Almacenamiento dado de alta | Terminal del host | Sí |
| 13 | Registro de la copia completa | Interfaz web de Proxmox | Sí |
| 14 | Snapshots en el datastore | Interfaz web de PBS | Sí |
| 15 | Diagnóstico de la incidencia de SSH | Terminal | **No** |
| 16 | Comparativa final | Terminal del host | Sí |

**Recomendación.** Las capturas 6, 7 y 8 se obtuvieron en el equipo de administración con el disco conectado; una vez instalado en el servidor ya no son reproducibles tal cual, aunque el informe SMART sí puede volver a generarse desde el propio hipervisor con `smartctl -a /dev/sdb`, lo que incluso resulta más coherente con el resto del documento.

Para las capturas no reconstruibles, transcribe la salida en un bloque de texto monoespaciado e indícalo en el pie como "transcripción de la salida original". Es una práctica aceptada y preferible a omitir la evidencia.
