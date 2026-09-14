#!/usr/bin/env bash

# =============================================================================
# run_squashfs_wrapper.sh — Wrapper universal de squashfs para ES-DE
# =============================================================================
#
# Intercepta cualquier ROM que ES-DE intente lanzar:
#
#   - Si NO es squashfs/.wsquashfs → ejecuta el emulador directamente.
#   - Si ES squashfs → monta con squashfuse, detecta el contenido y lanza
#     el emulador con la ruta correcta (archivo o carpeta según el sistema).
#
# Uso en es_systems.xml:
#   <command label="...">%STARTDIR%/run_squashfs_wrapper.sh %ROM% <emulador> [args...] %ROM%</command>
#
# Requisitos:
#   - squashfuse en el mismo directorio que este script
#   - fusermount (o fusermount3) disponible en PATH
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROM_PATH="$1"
shift  # El resto: emulador + sus argumentos (con %ROM% al final)

LOG_DIR="$(dirname "$ROM_PATH")/logs"
LOG_FILE="$LOG_DIR/squashfs_wrapper.log"
mkdir -p "$LOG_DIR"

# log() escribe SOLO al fichero, nunca a stdout
# (evita contaminar la captura $() en find_rom_in_mount)
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# =============================================================================
# TABLA DE PRIORIDADES
# Orden: se usa el primer match encontrado.
# Formato por línea: "extension:modo"
#   modo=file   → pasar el archivo directamente al emulador
#   modo=dir    → pasar la carpeta que contiene el archivo al emulador
#   modo=root   → pasar la raíz del montaje al emulador
# =============================================================================
declare -a PRIORITY_TABLE=(
    # --- Estructuras especiales: buscar archivo, pasar carpeta padre ---
    "EBOOT.BIN:dir"        # PS3 (RPCS3)
    "default.xex:dir"      # Xbox 360 (Xenia)
    "default.xbe:dir"      # Xbox OG
    "boot.elf:dir"         # PS2 homebrew
    "BOOT.ELF:dir"

    # --- Archivos únicos pasados directamente ---
    "iso:file"
    "ISO:file"
    "xiso:file"
    "XISO:file"
    "chd:file"
    "CHD:file"
    "cue:file"
    "CUE:file"
    "gdi:file"
    "GDI:file"
    "rvz:file"
    "RVZ:file"
    "wbfs:file"
    "WBFS:file"
    "nsp:file"
    "NSP:file"
    "xci:file"
    "XCI:file"
    "nes:file"
    "NES:file"
    "sfc:file"
    "SFC:file"
    "smc:file"
    "SMC:file"
    "gb:file"
    "GB:file"
    "gbc:file"
    "GBC:file"
    "gba:file"
    "GBA:file"
    "nds:file"
    "NDS:file"
    "3ds:file"
    "3DS:file"
    "z64:file"
    "Z64:file"
    "n64:file"
    "N64:file"
    "v64:file"
    "V64:file"
    "gcm:file"
    "GCM:file"
    "dol:file"
    "DOL:file"
    "psx:file"
    "PSX:file"
    "pbp:file"
    "PBP:file"
    "bin:file"
    "BIN:file"
    "img:file"
    "IMG:file"
    "mdf:file"
    "MDF:file"
    "nrg:file"
    "NRG:file"
    "rom:file"
    "ROM:file"
    "fig:file"
    "FIG:file"
    "swc:file"
    "SWC:file"
    "smd:file"
    "SMD:file"
    "gen:file"
    "GEN:file"
    "md:file"
    "MD:file"
    "gg:file"
    "GG:file"
    "pce:file"
    "PCE:file"
    "ngp:file"
    "NGP:file"
    "ws:file"
    "WS:file"
    "wsc:file"
    "WSC:file"
    "lnx:file"
    "LNX:file"
    "a52:file"
    "A52:file"
    "a78:file"
    "A78:file"
    "col:file"
    "COL:file"
    "int:file"
    "INT:file"
    "vec:file"
    "VEC:file"
    "dsk:file"
    "DSK:file"
    "adf:file"
    "ADF:file"
    "hdf:file"
    "HDF:file"
    "msu:file"
    "MSU:file"
    "m3u:file"
    "M3U:file"
    "exe:file"
    "EXE:file"
    "elf:file"
    "ELF:file"
    "pkg:file"
    "PKG:file"
    "vpk:file"
    "VPK:file"
    "rpx:file"             # Wii U (Cemu)
    "RPX:file"
)

# =============================================================================
# FUNCIÓN: buscar ROM dentro del montaje usando la tabla de prioridades
# IMPORTANTE: todos los log() llevan >&2 para no contaminar la captura $()
# =============================================================================
find_rom_in_mount() {
    local mount_dir="$1"

    for entry in "${PRIORITY_TABLE[@]}"; do
        local ext="${entry%%:*}"
        local mode="${entry##*:}"

        # Buscar por extensión (*.ext) o por nombre exacto (EBOOT.BIN, etc.)
        local found
        found=$(find "$mount_dir" -type f -name "*.$ext" 2>/dev/null | head -n 1)
        if [[ -z "$found" ]]; then
            found=$(find "$mount_dir" -type f -name "$ext" 2>/dev/null | head -n 1)
        fi

        if [[ -n "$found" ]]; then
            log "Match en tabla: '$found' (ext/nombre=$ext, modo=$mode)" >&2
            case "$mode" in
                file) echo "$found" ;;
                dir)  echo "$(dirname "$found")" ;;
                root) echo "$mount_dir" ;;
            esac
            return 0
        fi
    done

    # Sin match: contar archivos totales
    local file_count
    file_count=$(find "$mount_dir" -type f 2>/dev/null | wc -l)
    log "Sin match en tabla. Archivos totales en montaje: $file_count" >&2

    if [[ "$file_count" -eq 1 ]]; then
        local single
        single=$(find "$mount_dir" -type f 2>/dev/null | head -n 1)
        log "Un solo archivo, pasando directamente: '$single'" >&2
        echo "$single"
    else
        log "Múltiples archivos sin match conocido, pasando raíz del montaje: '$mount_dir'" >&2
        echo "$mount_dir"
    fi
}

# =============================================================================
# DETECCIÓN DE FUSERMOUNT
# =============================================================================
detect_fusermount() {
    if command -v fusermount3 &>/dev/null; then
        echo "fusermount3"
    elif command -v fusermount &>/dev/null; then
        echo "fusermount"
    else
        log "ADVERTENCIA: no se encontró fusermount ni fusermount3 en PATH"
        echo "fusermount"
    fi
}

# =============================================================================
# INICIO
# =============================================================================
log "======== INICIO ========"
log "ROM_PATH: '$ROM_PATH'"
log "Argumentos emulador ($#): '$*'"

# --- ROM normal: ejecutar directo sin hacer nada ---
case "${ROM_PATH,,}" in
    *.squashfs|*.wsquashfs)
        log ">>> Detectado squashfs, procediendo a montar"
        ;;
    *)
        log "ROM normal (${ROM_PATH##*.}), ejecutando directo"
        exec "$@"
        ;;
esac

# --- Calcular rutas de montaje ---
SQUASHFS_NAME="$(basename "$ROM_PATH")"
SQUASHFS_NAME="${SQUASHFS_NAME%.*}"   # quitar extensión (.squashfs o .wsquashfs)

MOUNT_BASE="$(dirname "$ROM_PATH")/tmp_mount"
MOUNT_DIR="$MOUNT_BASE/$SQUASHFS_NAME"
log "MOUNT_DIR: '$MOUNT_DIR'"

# --- Verificar que el archivo existe ---
if [[ ! -f "$ROM_PATH" ]]; then
    log "ERROR: archivo no encontrado: '$ROM_PATH'"
    exit 1
fi

FUSERMOUNT=$(detect_fusermount)
log "fusermount detectado: $FUSERMOUNT"

# --- Montar ---
if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
    log "Ya montado, reutilizando"
else
    mkdir -p "$MOUNT_DIR"
    log "Montando con squashfuse..."
    "$SCRIPT_DIR/squashfuse" "$ROM_PATH" "$MOUNT_DIR"
    FUSE_EXIT=$?
    log "squashfuse exit code: $FUSE_EXIT"
    if [[ $FUSE_EXIT -ne 0 ]]; then
        log "ERROR: squashfuse falló (código $FUSE_EXIT)"
        rmdir "$MOUNT_DIR" 2>/dev/null
        exit 1
    fi
fi

# --- Listar contenido (máx. 3 niveles para no saturar el log) ---
log "Contenido de '$MOUNT_DIR':"
find "$MOUNT_DIR" -maxdepth 3 | while read -r f; do log "  $f"; done

# --- Detectar qué pasar al emulador ---
TARGET=$(find_rom_in_mount "$MOUNT_DIR")
log "TARGET para el emulador: '$TARGET'"

if [[ -z "$TARGET" ]]; then
    log "ERROR: no se pudo determinar qué lanzar dentro del squashfs"
    "$FUSERMOUNT" -u "$MOUNT_DIR" 2>/dev/null
    rmdir "$MOUNT_DIR" 2>/dev/null
    exit 1
fi

# --- Sustituir la ruta del .squashfs por TARGET en los args del emulador ---
EMULATOR_CMD=()
for arg in "$@"; do
    if [[ "$arg" == "$ROM_PATH" ]]; then
        EMULATOR_CMD+=("$TARGET")
    else
        EMULATOR_CMD+=("$arg")
    fi
done

log "Comando final: '${EMULATOR_CMD[*]}'"
log "======== LANZANDO EMULADOR ========"

"${EMULATOR_CMD[@]}"
EXIT_CODE=$?

log "======== EMULADOR CERRADO (exit: $EXIT_CODE) ========"

"$FUSERMOUNT" -u "$MOUNT_DIR" 2>/dev/null
rmdir "$MOUNT_DIR" 2>/dev/null
log "Desmontado. Fin."

exit $EXIT_CODE
