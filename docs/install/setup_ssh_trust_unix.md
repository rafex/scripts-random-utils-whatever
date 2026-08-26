# setup_ssh_trust_unix.sh

Genera una clave SSH `ed25519` local y, opcionalmente, instala solamente la
clave pública en `authorized_keys` de otra máquina.

- **Ruta:** `scripts/install/setup_ssh_trust_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** `bash`, `ssh`, `ssh-keygen`

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Ejecutar como usuario normal, no como root.
- Tener SSH funcionando en ambas máquinas.
- Para instalar la clave remotamente, poder iniciar una conexión SSH inicial
  con contraseña o con una clave ya autorizada.
- La huella de la máquina remota debe verificarse en el primer prompt de SSH.

## Uso

Genera o revisa la clave local:

```sh
just setup-ssh-trust --check
just setup-ssh-trust --plan
just setup-ssh-trust --apply
```

Instala la clave pública de la máquina actual en otra máquina:

```sh
just setup-ssh-trust --apply --target rafex@192.168.3.91
```

Para confianza bidireccional ejecuta el proceso desde la otra máquina:

```sh
just setup-ssh-trust --apply --target rafex@192.168.3.174
```

La primera conexión puede pedir la contraseña del usuario remoto. Después,
valida el enlace:

```sh
ssh -o BatchMode=yes rafex@192.168.3.91 'hostname'
ssh -o BatchMode=yes rafex@192.168.3.174 'hostname'
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--target <usuario@host>` | — | Instala la pública en ese host remoto |
| `--key <archivo>` | — | Ruta de la clave local |
| `--comment <texto>` | — | Comentario para una clave nueva |
| `--check` | — | Diagnostica la clave y el acceso sin cambios |
| `--plan` | — | Muestra el flujo previsto sin cambios |
| `--dry-run` | — | Alias de `--plan` |
| `--apply` | — | Genera la clave y/o la instala remotamente |
| `--print-public` | — | Imprime la clave pública y termina |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `SSH_TRUST_TARGET` | vacío | Host remoto equivalente a `--target` |
| `SSH_TRUST_KEY` | `~/.ssh/id_ed25519` | Ruta equivalente a `--key` |
| `SSH_TRUST_COMMENT` | `usuario@hostname` | Comentario equivalente a `--comment` |

Los argumentos CLI tienen prioridad sobre las variables de entorno. No se
aceptan passphrases ni contraseñas mediante variables.

## Ejemplos

### MacBook hacia ThinkPad

```sh
just setup-ssh-trust --apply --target rafex@192.168.3.91
```

### ThinkPad hacia MacBook

```sh
just setup-ssh-trust --apply --target rafex@192.168.3.174
```

### Mostrar únicamente la clave pública

```sh
just setup-ssh-trust --print-public
```

### Ruta de clave alternativa

```sh
SSH_TRUST_KEY="$HOME/.ssh/id_ed25519_trust" \
  just setup-ssh-trust --apply --target rafex@192.168.3.91
```

## Protecciones de seguridad

- Usa `ed25519` y no reemplaza claves existentes.
- La clave privada nunca se transmite al host remoto.
- La clave pública se añade de forma idempotente a `authorized_keys`.
- Ajusta `.ssh` a `0700`, la privada a `0600`, la pública a `0644` y
  `authorized_keys` a `0600`.
- Mantiene la verificación interactiva de la huella SSH del host remoto.
- No usa `StrictHostKeyChecking=no` ni `ssh-copy-id` obligatorio.
- La passphrase de una clave nueva la solicita directamente `ssh-keygen`.
- El acceso remoto se prueba con `BatchMode=yes` sin escribir archivos.

## Fallos conocidos

### `Permission denied (publickey,password)`

**Causa:** el usuario remoto no permite autenticación inicial o la contraseña
  no es correcta.

**Solución:** verifica `ssh usuario@host` manualmente, habilita temporalmente
  autenticación por contraseña o instala la pública por consola.

### `Host key verification failed`

**Causa:** la huella guardada en `known_hosts` no coincide con la máquina.

**Solución:** verifica la identidad del host antes de corregir o retirar la
  entrada antigua de `~/.ssh/known_hosts`.

### `clave privada ausente`

**Causa:** existe una `.pub` sin su clave privada correspondiente.

**Solución:** conserva la pública como referencia y genera otra clave con una
  ruta distinta usando `--key`; el script no sobrescribe archivos.

## Changelog

### [Unreleased]

- **feat:** generación ed25519 e instalación segura de confianza SSH entre
  macOS y Linux.
