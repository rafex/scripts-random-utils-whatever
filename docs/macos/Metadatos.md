# Archivos `._*` en macOS (AppleDouble)

Esos archivos `._nombre` son **AppleDouble**: macOS los crea para guardar metadatos que otros sistemas de archivos no soportan bien, por ejemplo:

```
._archivo.txt
._foto.jpg
._carpeta
```

Normalmente contienen cosas como:

- resource fork
- Finder info
- etiquetas
- atributos extendidos
- metadatos de cuarentena

En discos/volúmenes que no son APFS/HFS+, como exFAT, FAT32, algunos montajes SMB/NFS, USBs, volúmenes compartidos con Linux o contenedores, macOS no puede guardar todos esos metadatos de forma nativa y los escribe en archivos separados `._`.

## Verlos

```sh
find /ruta/del/volumen -name '._*'
```

## Borrarlos

Para borrar todos los `._` dentro de una ruta:

```sh
find /ruta/del/volumen -name '._*' -type f -delete
```

También puedes usar:

```sh
dot_clean /ruta/del/volumen
```

`dot_clean` intenta fusionar o limpiar esos archivos AppleDouble.

## Evitar que aparezcan en volúmenes de red

Para volúmenes de red puedes desactivar parte de esta basura de Finder:

```sh
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
```

Y para USB o discos externos:

```sh
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
```

Después reinicia Finder:

```sh
killall Finder
```

Eso ayuda mucho con archivos como `.DS_Store`.

> **Ojo:** no garantiza eliminar todos los `._*`, porque algunos los crean las APIs de macOS cuando una app escribe atributos extendidos en un sistema de archivos que no los soporta.

## Para copiar sin metadatos de macOS

Cuando copies a Linux, USB, contenedores o volúmenes montados, usa `COPYFILE_DISABLE=1`:

```sh
COPYFILE_DISABLE=1 cp -R carpeta /ruta/destino/
```

Con rsync:

```sh
COPYFILE_DISABLE=1 rsync -av --exclude='._*' --exclude='.DS_Store' carpeta/ /ruta/destino/
```

## Para limpiar atributos extendidos antes de copiar

```sh
xattr -rc carpeta
```

Luego copias:

```sh
COPYFILE_DISABLE=1 cp -R carpeta /ruta/destino/
```

## Recomendación práctica

```sh
xattr -rc carpeta
COPYFILE_DISABLE=1 rsync -av --exclude='._*' --exclude='.DS_Store' carpeta/ /ruta/destino/
dot_clean /ruta/destino
find /ruta/destino -name '._*' -type f -delete
```

Para un volumen que usas con Linux/contenedores, lo más efectivo es copiar con `COPYFILE_DISABLE=1` y limpiar con `dot_clean` o `find` cuando aparezcan.
