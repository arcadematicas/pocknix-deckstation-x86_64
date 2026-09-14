# DeckStation x86_64

**Sistema de emulación portable para arquitectura x86_64 (PC / Steam Deck)**

> **DeckStation** es un proyecto independiente de emulación portable.
> Creado por **stshunz** — https://github.com/stshunz
> Esta es la versión original (x86_64) y más completa.

---

## ¿Qué es?

DeckStation x86_64 es el sistema de emulación portable original, diseñado para PC
y Steam Deck. Incluye un sistema de actualización propio, gestión de ROMs, mapeo de
mandos avanzado y configuraciones para más de 20 emuladores.

Es un proyecto **independiente de cualquier sistema operativo**: no depende de
ninguna distribución concreta y todo queda autocontenido en su propia carpeta.

## Filosofía

- **Todo autocontenido**: Todo vive dentro de `/opt/deckstation/`
- **Nada en el sistema host**: No toca `/home/`, `/etc/` ni configs del usuario
- **Portable**: Mover el directorio funciona en otro dispositivo
- **Sin dependencias del sistema**: Se auto-descarga todo lo necesario
- **Modular**: Cada emulador es independiente

## Arquitecturas

| Arquitectura | Estado |
|---|---|
| **x86_64** | ✅ Este repo — versión original y más completa |
| **aarch64 (ARM64)** | ❌ Ver repo `deckstation-arm` |
| **armv7h (ARM32)** | ❌ Ver repo `deckstation-arm` |

## Estructura del repo

```
deckstation-x86_64/
├── README.md
├── .gitignore
├── PKGBUILD                        # Paquete Arch (x86_64)
├── deckstation-x86_64.install
├── scripts/                        # Scripts del sistema
│   ├── DeckStation.sh              # Launcher portable
│   ├── launcher.sh                 # Launcher multi-python (Updater)
│   ├── mapeador.py                 # Mapeador de mandos
│   ├── selector_manual.py          # Selector manual
│   ├── compresorKSM.sh             # Compresor de ROMs (KSM)
│   ├── PortProton_wsquashfs.sh     # Wrapper wsquashfs para PortProton
│   ├── run_squashfs_wrapper.sh     # Wrapper squashfs
│   └── Gestor KSM.desktop          # Acceso directo al gestor KSM
├── evmapy/                         # Mapeo de mandos (evmapy)
├── configs/                        # Configs portable de emuladores
│   ├── es-de/                      #   ES-DE: custom_systems/, settings/, scrapers/
│   ├── retroarch/                  #   retroarch.cfg + config/ (92 sistemas)
│   └── <emulador>/                 #   Configs por emulador
└── docs/
    └── INSTALACION.md
```

## Estructura en ejecución (`/opt/deckstation/`)

```
/opt/deckstation/
├── DeckStation.AppImage         # La AppImage principal (ES-DE)
├── DeckStation.sh               # Script de lanzamiento
├── Apps/                        # Emuladores (x86_64)
├── saves/                       # Saves del usuario
├── logs/                        # Logs de ejecución
├── Media/                       # Assets multimedia (NO en git)
├── settings/                    # Configuraciones
├── wsquashfs/                   # Contenedores comprimidos (NO en git)
├── bezels/                      # Bezels (NO en git)
├── scripts/                     # Scripts de gestión
└── configs/                     # Configs del sistema
```

## Extras (vs la versión ARM)

- **`launcher.sh`** — launcher multi-python con **Updater** auto-descargable
- **`compresorKSM.sh`** + **Gestor KSM** — compresión de ROMs en contenedores
- **`wsquashfs/`** + `run_squashfs_wrapper.sh` — sistema de compresión squashfs
- **OpenROM** — gestor de ROMs portable
- **`evmapy/`** + `mapeador.py` — mapeo avanzado de mandos
- **`bezels/`** — bezels para RetroArch
- **ES-DE completo** — `es_input.xml`, collections, gamelists, themes, media
- **RetroArch** — configs para **92 sistemas**

## Cómo funciona

1. **Instalación**: El paquete Arch instala la estructura base en `/opt/deckstation/`
2. **Setup**: Los emuladores se colocan en `Apps/` (se descargan o copian aparte)
3. **Uso**: `deckstation` lanza el sistema completo
4. **Actualización**: El Updater (`launcher.sh`) gestiona las actualizaciones

## Instalación

### Arch Linux (x86_64)
```bash
# Compilar e instalar
makepkg -si

# O instalar desde pre-compilado
sudo pacman -U deckstation-x86_64-*.pkg.tar.zst
```

### Post-instalación
```bash
# Lanzar
deckstation
```

## Licencia

GPL v2+

## Créditos

- **stshunz** — creador original de DeckStation (https://github.com/stshunz)
- **Emuladores**: RetroArch, Dolphin, DuckStation, PPSSPP, RPCS3, etc.
