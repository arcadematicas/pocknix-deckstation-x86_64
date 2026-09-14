# Guía de Instalación — Pocknix DeckStation x86_64

## Requisitos previos

- **Sistema**: Arch Linux (x86_64) o compatible
- **Espacio**: ~5 GB libres para emuladores base (más según ROMs)
- **Conexión**: Internet para descargar emuladores
- **Dependencias**:
  - `python` y `python-requests`
  - `gamemode` (opcional pero recomendado)
  - `curl` o `wget`

## Instalación del paquete

### Opción 1: Compilar desde PKGBUILD

```bash
# Clonar el repo
git clone https://github.com/arcadematicas/pocknix-deckstation-x86_64.git
cd pocknix-deckstation-x86_64

# Compilar el paquete
makepkg -si
```

Esto instalará:
- `/opt/deckstation/` — Directorio base
- `/usr/bin/deckstation` — Comando del sistema
- Scripts de gestión en `/opt/deckstation/scripts/`
- Configs en `/opt/deckstation/configs/`

### Opción 2: Instalación manual

Si no usas Arch Linux:

```bash
# Crear directorio base
sudo mkdir -p /opt/deckstation

# Copiar archivos
sudo cp -r scripts/ /opt/deckstation/
sudo cp -r configs/ /opt/deckstation/
sudo cp -r evmapy/ /opt/deckstation/
sudo cp overlay/usr/bin/deckstation /usr/local/bin/deckstation

# Hacer ejecutables los scripts
sudo chmod +x /opt/deckstation/scripts/*.sh
sudo chmod +x /opt/deckstation/scripts/*.py
```

## Emuladores

Los emuladores (AppImages) **NO están en el repo** por su tamaño (~98 GB).
Hay que colocarlos en `/opt/deckstation/Apps/`:

- Opción A: copiarlos desde una instalación existente de DeckStation
- Opción B: descargarlos de sus fuentes oficiales (versiones x86_64)

El repo solo incluye **configuraciones** (portables, rutas relativas).

## Uso básico

### Lanzar DeckStation

```bash
deckstation
```

Esto:
1. Calcula la raíz de DeckStation dinámicamente
2. Crea la estructura de `saves/` y `logs/`
3. Configura symlinks de compatibilidad
4. Lanza ES-DE (`DeckStation.AppImage`)

### Updater (launcher.sh)

El actualizador multi-python se lanza con:

```bash
/opt/deckstation/scripts/launcher.sh
```

Descarga un Python portable standalone y ejecuta `Updater/updater.py`.

### Compresor KSM

```bash
/opt/deckstation/scripts/compresorKSM.sh
```

### Mapeo de mandos

```bash
python3 /opt/deckstation/scripts/mapeador.py
```

### Estructura de directorios

```
/opt/deckstation/
├── Apps/           # Emuladores (x86_64)
├── saves/          # Saves del usuario
├── logs/           # Logs de ejecución
├── configs/        # Configuraciones
├── evmapy/         # Mapeo de mandos
├── settings/       # Settings del sistema
├── Media/          # Assets multimedia
├── wsquashfs/      # Contenedores comprimidos
└── scripts/        # Scripts de gestión
```

## Troubleshooting

### "deckstation: command not found"

```bash
# Verificar instalación
ls -la /usr/bin/deckstation

# Si no existe, crear symlink manual
sudo ln -sf /opt/deckstation/scripts/DeckStation.sh /usr/local/bin/deckstation
```

### "No se encontró ningún launcher"

Los emuladores no están instalados en `Apps/`:

```bash
ls -la /opt/deckstation/Apps/
```

### Problemas de permisos

```bash
# Reparar permisos
sudo chown -R $(whoami) /opt/deckstation/
sudo chmod -R 755 /opt/deckstation/

# Para usar sin sudo
sudo usermod -aG video $(whoami)
sudo usermod -aG input $(whoami)
```

### Logs para diagnóstico

```bash
cat /opt/deckstation/logs/launcher.log
cat /opt/deckstation/update/update.log
```

## Desinstalación

### Solo emuladores
```bash
rm -rf /opt/deckstation/Apps/
```

### Todo el sistema
```bash
sudo rm -rf /opt/deckstation/
sudo rm /usr/bin/deckstation
```

### Con el gestor de paquetes
```bash
sudo pacman -R pocknix-deckstation-x86_64
```

## Notas finales

- **No toca el sistema**: DeckStation es completamente portable
- **Configs persistentes**: Se mantienen entre actualizaciones
- **Versión ARM**: existe un repo hermano para aarch64 (`arcadematicas/pocknix-deckstation`)
