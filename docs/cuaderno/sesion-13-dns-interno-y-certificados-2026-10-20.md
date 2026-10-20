# Sesión 13 — <dns interno y certificadis> — 2026-10-20

**Duración:** HH:MM a HH:MM (N h)
**Fase / RFTP:** F10 · R03F01T01
**Estado al empezar:** <una línea: de qué situación partes>
**Objetivo de la sesión:** <una línea: qué quieres tener al acabar>

---

## Lo que hice

Narración en orden, con los comandos tal cual los ejecutaste y la salida
relevante. Sin pulir. Esto no lo lee nadie más que tú.

```console
$ comando
salida
```

---

## Lo que falló

**El apartado más importante del cuaderno.** Un problema por bloque:

### Síntoma
El equipo de administración no resuelve la zona interna, mientras que los
cuatro nodos sí lo hacen con la misma configuración lógica.

    $ resolvectl query portfolio.sierraalta.internal
    resolve call failed: Name 'portfolio.sierraalta.internal' not found

La consulta dirigida explícitamente al servidor sí responde, de modo que el
servidor no es el problema:

    $ dig @192.168.18.51 portfolio.sierraalta.internal +short
    192.168.18.240

### Qué probé
**Primera hipótesis: el servidor interno no estaba declarado.** Lo estaba. Al
añadirlo con `nmcli` quedó el tercero de la lista, detrás de los dos del
router. El resolutor pregunta por orden y el primero, un resolutor público,
respondía que el nombre no existe. Esa respuesta es válida, no un error, así
que la resolución terminaba ahí sin llegar a preguntar al servidor propio.

**Segunda hipótesis: bastaba con reordenar.** Se dejó el servidor interno en
primer lugar y el fallo persistió. `systemd-resolved` conserva el servidor que
venía utilizando hasta que este falla, y recibir un «no existe» no cuenta como
fallo, de modo que seguía consultando al anterior. Vaciar la caché y
reiniciar la selección de servidor tampoco bastó.

**Tercera hipótesis, la correcta: el cliente descartaba el servidor por
protocolo.** La configuración de la distribución exige DNS cifrado sobre TLS,
y el servidor propio solo atiende DNS clásico en el puerto 53. El resolutor
intentaba la conexión cifrada, no la obtenía, y pasaba al siguiente servidor
de la lista sin registrar error alguno. El indicio estaba a la vista desde el
principio, en la línea `Protocols: +DNSOverTLS` y en el sufijo
`#cloudflare-dns.com` que acompañaba a la dirección del servidor en uso.

### Causa raíz
Incompatibilidad de protocolo entre el cliente y el servidor de nombres
propio, enmascarada por un mecanismo de reserva que funcionaba correctamente:
al existir un segundo servidor capaz de responder, el descarte del primero no
producía ningún mensaje de error.

### Solución
Desactivar el cifrado de transporte DNS en la conexión de la red local, donde
existe una zona privada servida por un servidor propio, y declarar ese
servidor en primer lugar.

### Aprendizaje
Tres intentos, tres causas en capas distintas —orden de consulta, estado del
resolutor y protocolo de transporte— y un único síntoma idéntico en los tres
casos. La lección no es ninguna de las tres correcciones, sino que **el
cliente nunca estuvo averiado: hacía exactamente lo que se le había pedido**.
Un fallo silencioso enmascarado por un mecanismo de reserva es más difícil de
diagnosticar que una caída, porque el sistema sigue respondiendo y la
respuesta es plausible.

Se deriva también una limitación conocida de la plataforma: la privacidad del
tráfico DNS y la resolución de una zona privada propia tiran en direcciones
opuestas. La solución completa pasaría por que el servidor interno atendiera
también sobre TLS; mientras tanto, el cifrado se desactiva únicamente en la
red donde existe zona propia. Queda recogido en trabajos futuros.

---

## Decisiones tomadas

Cualquier punto en el que elegiste entre dos opciones. Qué elegiste, qué
descartaste y por qué. Estas líneas van casi literales a la memoria.

---

## Verificación

Qué comprobaste para dar la tarea por cerrada, con el código `P` del RFTP.

```console
$ comando de verificación
salida que lo demuestra
```

- [ ] Evidencias recogidas: `./scripts/evidencias.sh 10 <etiqueta>`
- [ ] Captura de pantalla, si aplica
- [ ] Commit hecho

---

## Pendiente para la próxima

Lo que dejas a medias, con el detalle suficiente para retomarlo sin releer
toda la sesión.

---

## Tiempo real dedicado

| Código RFTP | Estimado | Real | Desviación |
|---|---|---|---|
| R03F01T01 | 4 h | | |

> Anótalo al cerrar la sesión, no al final del mes. La tabla de planificación
> frente a dedicación real de la memoria sale de aquí, y vale un 5 % de la nota.
