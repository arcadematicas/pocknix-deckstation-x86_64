#!/usr/bin/env bash

set -e

echo "👉 Script iniciado: Iniciando maquinaria suiza..."

# =================================================
# 🛠️ PIEZA 1: MANTENIMIENTO EVMAPY LIBRERÍAS
# =================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
LIB_DIR="$DIR/libs_py$PY_VER"
EVMAPY_DIR="$DIR/evmapy"

# Descarga de motor si falta
if [ ! -d "$EVMAPY_DIR" ]; then
    echo "[+] Descargando motor evmapy..."
    curl -L -k -s "https://github.com/batocera-linux/evmapy/archive/refs/heads/master.zip" -o evmapy.zip
    unzip -q evmapy.zip && mv evmapy-master evmapy && rm evmapy.zip
fi

# Instalación de dependencias si faltan
if [ ! -d "$LIB_DIR/evdev" ]; then
    echo "[+] Preparando entorno Python $PY_VER..."
    mkdir -p "$LIB_DIR"
    curl -L -s https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    export PYTHONPATH="$LIB_DIR"
    python3 get-pip.py --target="$LIB_DIR" --no-setuptools --no-wheel --quiet
    python3 -m pip install --target="$LIB_DIR" evdev-binary --no-cache-dir --quiet
    rm get-pip.py 2>/dev/null
fi

# Inyección de rutas en el mapeador.py original (Corregido y Portable)
if [ -f "$DIR/mapeador.py" ]; then
    sed -i '/sys.path.insert/d' "$DIR/mapeador.py"
    sed -i '/import sys, os/d' "$DIR/mapeador.py"
    sed -i '/_BASE_DIR/d' "$DIR/mapeador.py"
    sed -i "1i import sys, os; _BASE_DIR = os.path.dirname(os.path.abspath(sys.argv[0])); sys.path.insert(0, os.path.join(_BASE_DIR, 'libs_py$PY_VER')); sys.path.insert(0, os.path.join(_BASE_DIR, 'evmapy'))" "$DIR/mapeador.py"
fi

# =================================================
# 📂 PIEZA 2: RUTAS Y ENTORNO
# =================================================
INPUT_PATH="$1"
SCRIPT_DIR="$DIR"
PORTPROTON="$SCRIPT_DIR/Apps/PortProton/data/scripts/start.sh"
DEFAULT_PPDB="$SCRIPT_DIR/settings/PortProton/default.ppdb"
FINAL_DIR="$SCRIPT_DIR/ROMs/windows"
MOUNT_BASE="$SCRIPT_DIR/wsquashfs/tmp_mount"
BUILD_BASE="$SCRIPT_DIR/wsquashfs/build_ws"
OVERLAY_BASE="$SCRIPT_DIR/wsquashfs/overlays"

mkdir -p "$BUILD_BASE" "$MOUNT_BASE" "$OVERLAY_BASE" "$FINAL_DIR"

_cleanup() {
    exec 3>&- 2>/dev/null || true
    [[ -n "${MAPEADOR_PID:-}" ]] && kill "$MAPEADOR_PID" 2>/dev/null || true
    [[ -n "${EXTRACT_DIR:-}" ]] && rm -rf "$EXTRACT_DIR" 2>/dev/null || true
    [[ -n "${WORK_DIR:-}" && "${WORK_DIR:-}" != "${EXTRACT_DIR:-}" ]] && rm -rf "$WORK_DIR" 2>/dev/null || true
    
    # 🗑️ LIMPIEZA ADICIONAL: Borrar overlay generado al salir del juego para ahorrar espacio
    if [[ -n "${NAME:-}" && -d "$OVERLAY_BASE/$NAME" ]]; then
        echo "[+] Purgando archivos generados en el Overlay para ahorrar espacio..."
        rm -rf "$OVERLAY_BASE/$NAME" 2>/dev/null || true
    fi
}
trap _cleanup EXIT

progress_pipe() {
    zenity --progress --title="DeckStation Pro" --text="Ajustando engranajes..." --percentage=0 --auto-close --no-cancel 2>/dev/null
}
exec 3> >(progress_pipe)
progress() { echo "$1" >&3; echo "# $2" >&3; }

# =================================================
# 🔍 FUNCIÓN: Detección inteligente de EXE
# =================================================
find_game_exe() {
    local ROOT="$1"
    local EXE=""

    local EXCLUSIONES="! -iname UnityCrashHandler* ! -iname UnityPlayer.exe ! -iname UE4PrereqSetup* ! -iname UE5PrereqSetup* ! -iname unins* ! -iname *setup* ! -iname vcredist* ! -iname vc_redist* ! -iname dxsetup* ! -iname dotnetfx* ! -iname oalinst* ! -iname physx* ! -iname *Crash* ! -iname *Prerequisite* ! -iname iexplore.exe ! -iname winecfg* ! -iname notepad* ! -iname wordpad* ! -iname mspaint* ! -iname calc* ! -iname write* ! -iname wmplayer.exe"

    EXE=$(find "$ROOT" -type f -iname "*.exe" \( -ipath "*/Binaries/Win64/*" -o -ipath "*/Binaries/Win32/*" -o -ipath "*/Win64/*" -o -ipath "*/Win32/*" \) ! -ipath "*/windows/*" ! -ipath "*/Windows/*" $EXCLUSIONES 2>/dev/null | head -n1)
    [[ -n "$EXE" ]] && echo "$EXE" && return

    EXE=$(find "$ROOT" -maxdepth 1 -type f -iname "*.exe" $EXCLUSIONES 2>/dev/null | head -n1)
    [[ -n "$EXE" ]] && echo "$EXE" && return
    
    if [ -d "$ROOT/drive_c" ]; then
        EXE=$(find "$ROOT/drive_c" -maxdepth 1 -type f -iname "*.exe" $EXCLUSIONES 2>/dev/null | head -n1)
        [[ -n "$EXE" ]] && echo "$EXE" && return
    fi

    local DATA_DIR
    DATA_DIR=$(find "$ROOT" -maxdepth 5 -type d \( -iname "*_Data" -o -iname "*.Data" \) 2>/dev/null | head -n1)
    if [[ -n "$DATA_DIR" ]]; then
        local UNITY_NAME
        UNITY_NAME=$(basename "$DATA_DIR" | sed 's/[_.]Data$//i')
        EXE=$(find "$(dirname "$DATA_DIR")" -maxdepth 1 -type f -iname "${UNITY_NAME}.exe" 2>/dev/null | head -n1)
        [[ -n "$EXE" ]] && echo "$EXE" && return
    fi

    EXE=$(find "$ROOT" -type f -iname "*.exe" ! -ipath "*/windows/*" ! -ipath "*/Windows/*" ! -ipath "*/system32/*" 2>/dev/null | head -n1)
    echo "$EXE"
}

# =================================================
# 🛠️ FUNCIÓN: Parseo de autorun.cmd
# =================================================
parse_autorun() {
    local FILE="$1"
    R_DIR=""; R_CMD=""; R_CMD_BASE=""
    [[ ! -f "$FILE" ]] && return
    local CONTENT
    if file "$FILE" | grep -qi "UTF-16"; then
        CONTENT=$(iconv -f UTF-16 -t UTF-8 "$FILE" 2>/dev/null)
    else
        CONTENT=$(cat "$FILE")
    fi
    CONTENT=$(echo "$CONTENT" | tr -d '\r' | sed 's/\\/\//g')

    R_DIR=$(echo "$CONTENT" | grep -i "^DIR=" | head -n1 | sed -e 's/^[Dd][Ii][Rr]=//' -e 's/^"//' -e 's/"$//' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
    R_CMD=$(echo "$CONTENT" | grep -i "^CMD=" | head -n1 | sed -e 's/^[Cc][Mm][Dd]=//' -e 's/^"//' -e 's/"$//' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
    R_CMD_BASE=$(basename "$R_CMD" 2>/dev/null || true)
}

# =================================================
# 🚀 PIEZA 3: LÓGICA DE CARGA (SH / CARPETA / SQUASH)
# =================================================
if [[ "$INPUT_PATH" == *.sh ]]; then
    progress 100 "Lanzando script rebelde..."
    exec 3>&-
    bash "$INPUT_PATH"
    exit 0
fi

if [[ -d "$INPUT_PATH" ]]; then
    if [[ "$INPUT_PATH" == *.AppImage || "$INPUT_PATH" == *.appimage ]]; then
        chmod +x "$INPUT_PATH"
        IS_SQUASH=false
        NAME="$(basename "$INPUT_PATH")"
    else
        LAUNCHER=$(find "$INPUT_PATH" -maxdepth 1 -type f -name "*.sh" | head -n1)
        if [[ -n "$LAUNCHER" ]]; then
            exec 3>&-
            bash "$LAUNCHER"
            exit 0
        fi
        IS_SQUASH=false
        NAME="$(basename "$INPUT_PATH")"
        LAUNCH_PATH=$(find "$INPUT_PATH" -type f -iname "*.exe" ! -iname "*crash*" ! -iname "*unity*" | head -n1)
    fi
else
    IS_SQUASH=true
    ARCHIVE_REGEX="\.(zip|7z|rar)(\.001)?$|\.part[0-9]+\.rar$|\.r[0-9]{2}$|\.z01"

    if [[ "$INPUT_PATH" =~ $ARCHIVE_REGEX ]]; then
        BASE_DIR="$(dirname "$INPUT_PATH")"
        NAME_RAW=$(basename "$INPUT_PATH")
        
        # 🔥 ANCLA DE PURGA UNIVERSAL: Aísla el nombre base eliminando cualquier tipo de parte numérica o extensión
        ORIGINAL_MATCH_PREFIX="${INPUT_PATH%.0*}"
        ORIGINAL_MATCH_PREFIX="${ORIGINAL_MATCH_PREFIX%.part*}"
        ORIGINAL_MATCH_PREFIX="${ORIGINAL_MATCH_PREFIX%.zip}"
        ORIGINAL_MATCH_PREFIX="${ORIGINAL_MATCH_PREFIX%.7z}"
        ORIGINAL_MATCH_PREFIX="${ORIGINAL_MATCH_PREFIX%.rar}"

        GAME_NAME="${NAME_RAW%.001}"
        GAME_NAME="${GAME_NAME%.zip}"; GAME_NAME="${GAME_NAME%.7z}"; GAME_NAME="${GAME_NAME%.z01}"
        GAME_NAME="${GAME_NAME%.rar}"
        GAME_NAME=$(echo "$GAME_NAME" | sed 's/\.part[0-9][0-9]*$//; s/\.r[0-9][0-9]$//')

        GAME_NAME=$(echo "$GAME_NAME" \
            | sed 's/[-_ ]*[vV][0-9][0-9]*\(\.[0-9][0-9]*\)*[[:alnum:]_.]*//g' \
            | sed 's/[-_ ]*[build][0-9][0-9]*\(\.[0-9][0-9]*\)*[[:alnum:]_.]*//g' \
            | sed 's/[-_ ]*[Build][0-9][0-9]*\(\.[0-9][0-9]*\)*[[:alnum:]_.]*//g' \
            | sed 's/[-_ ]*\(P2P\|CODEX\|SKIDROW\|REPACK\|FitGirl\|GOG\|DODI\|KaOs\|RAZOR\|CPY\|PLAZA\|FLT\|TENOKE\|TiNYiSO\|EMPRESS\|ElAmigos\|DAZA\|DARKSiDERS\)//gi' \
            | sed 's/[-_ ]*\[[0-9]\{4\}\][-_ ]*/ /g' \
            | sed 's/[-_ ]*([0-9]\{4\})[-_ ]*/ /g' \
            | sed 's/[-_.]*$//' \
            | sed 's/  */ /g; s/^ //; s/ $//')
        EXTRACT_DIR="$BUILD_BASE/${GAME_NAME}_extract"
        rm -rf "$EXTRACT_DIR"; mkdir -p "$EXTRACT_DIR"
        progress 15 "Descomprimiendo y limpiando..."

        # Extracción vía 7z
        if 7z x "$INPUT_PATH" -o"$EXTRACT_DIR" -y; then
            echo "[+] Extracción completada con éxito. Ejecutando purga inmediata de almacenamiento..."

            # 🛠️ PURGA RADICAL COMPLETA: Borra usando el prefijo universal aislado (.z01, .part1.rar, .001, etc.)
            rm -f "${ORIGINAL_MATCH_PREFIX}"* 2>/dev/null || true
            
            # Barrido secundario de seguridad basado en el nombre filtrado del juego
            find "$BASE_DIR" -maxdepth 1 -type f -name "${GAME_NAME}*" | while read -r archivo; do
                ext_file="${archivo##*.}"
                ext_lower="${ext_file,,}"
                case "$ext_lower" in
                    zip|7z|rar|001|002|003|004|005|z01|z02|z03|z04|z05)
                        rm -f "$archivo"
                        ;;
                    *)
                        if [[ "$(basename "$archivo")" == *".part"*".rar" || "$(basename "$archivo")" == *".r"[0-9][0-9] ]]; then
                            rm -f "$archivo"
                        fi
                        ;;
                esac
            done
        else
            echo "❌ ERROR: La descompresión falló o fue interrumpida. Conservando archivos fuente."
            exit 1
        fi

        WSQUASHFS_PATH=$(find "$EXTRACT_DIR" -type f -iname "*.wsquashfs" | head -n1)
    else
        WSQUASHFS_PATH="$INPUT_PATH"
    fi

    if [[ -f "$WSQUASHFS_PATH" ]]; then
        TARGET_WSQUASHFS_NAME="$(basename "$WSQUASHFS_PATH")"
        NAME="$(basename "$WSQUASHFS_PATH" .wsquashfs)"
    else
        TARGET_WSQUASHFS_NAME="${GAME_NAME}.wsquashfs"
        NAME="$GAME_NAME"
    fi

    FINAL_WSQUASHFS="$FINAL_DIR/$TARGET_WSQUASHFS_NAME"

    if [[ ! -f "$WSQUASHFS_PATH" ]]; then
        [[ -z "$EXTRACT_DIR" ]] && echo "❌ Error: SquashFS no encontrado" && exit 1
        echo "ℹ️  Sin wsquashfs, empaquetando contenido extraído directamente..."
        HAS_PPDB=""
    else
        echo "[+] Escaneando integridad del SquashFS original en busca de configuraciones existentes..."
        if unsquashfs -l "$WSQUASHFS_PATH" 2>/dev/null | grep -iv "/windows/" | grep -iv "/system32/" | grep -iv "/syswow64/" | grep -qi "\.ppdb"; then
            HAS_PPDB=$(unsquashfs -l "$WSQUASHFS_PATH" 2>/dev/null | grep -iv "/windows/" | grep -iv "/system32/" | grep -iv "/syswow64/" | grep -i "\.ppdb" | head -n1)
            echo "[+] ¡Configuración existente detectada! Respetando perfil original: $(basename "$HAS_PPDB")"
        else
            HAS_PPDB=""
            echo "[-] No se detectó ningún .ppdb nativo en el SquashFS. Se programará la inyección base."
        fi
    fi

    if [[ -z "$HAS_PPDB" ]]; then
        if [[ -f "$WSQUASHFS_PATH" ]]; then
            WORK_DIR="$BUILD_BASE/${NAME}_build"
            rm -rf "$WORK_DIR"; mkdir -p "$WORK_DIR"
            progress 40 "Analizando e Inyectando archivos de configuración..."
            unsquashfs -f -d "$WORK_DIR" "$WSQUASHFS_PATH"
        else
            WORK_DIR="$EXTRACT_DIR"
            progress 40 "Empaquetando e inyectando archivos..."
        fi
        chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true

        T_EXE=$(find_game_exe "$WORK_DIR")

        if [[ -f "$T_EXE" ]]; then
            if [[ -f "$DEFAULT_PPDB" ]]; then
                cp -f "$DEFAULT_PPDB" "${T_EXE}.ppdb"
            else
                echo "⚠️  default.ppdb no encontrado en: $DEFAULT_PPDB — usando configuración base"
                cat > "${T_EXE}.ppdb" << 'PPDB_EOF'
export PW_WINE_USE="WINE_LG_11-1"
export PW_PREFIX_NAME="DEFAULT"
export PW_VULKAN_USE="6"
export PW_MANGOHUD="0"
export PW_VKBASALT="0"
export PW_DGVOODOO2="0"
export PW_USE_ESYNC="0"
export PW_USE_FSYNC="0"
export PW_USE_NTSYNC="0"
export PW_USE_RAY_TRACING="0"
export PW_USE_NVAPI_AND_DLSS="0"
export PW_USE_OPTISCALER="0"
export PW_USE_LS_FRAME_GEN="0"
export PW_WINE_FULLSCREEN_FSR="1"
export PW_HIDE_NVIDIA_GPU="0"
export PW_VIRTUAL_DESKTOP="0"
export PW_USE_TERMINAL="0"
export PW_GUI_DISABLED_CS="0"
export PW_USE_GAMEMODE="1"
export PW_USE_INHIBIT_SLEEP="1"
export PW_USE_D3D_EXTRAS="1"
export PW_FIX_VIDEO_IN_GAME="0"
export PW_REDUCE_PULSE_LATENCY="0"
export PW_USE_US_LAYOUT="0"
export PW_USE_GSTREAMER="1"
export PW_USE_SHADER_CACHE="1"
export PW_USE_WINE_DXGI="0"
export PW_USE_EAC_AND_BE="1"
export PW_USE_SYSTEM_VK_LAYERS="0"
export PW_USE_OBS_VKCAPTURE="0"
export PW_DISABLE_COMPOSITING="0"
export PW_USE_RUNTIME="1"
export PW_DINPUT_PROTOCOL="0"
export PW_USE_GALLIUM_ZINK="0"
export PW_USE_GALLIUM_NINE="0"
export PW_USE_WINED3D_VULKAN="0"
export PW_USE_DXVK_HDR="0"
export PW_GAMESCOPE="0"
export PW_RUN_AFTER_EXE=""
export PW_RUN_AFTER_DELAY="3"
export PW_WINDOWS_VER="10"
export PW_DLL_INSTALL=""
export WINEDLLOVERRIDES=""
export PW_WINE_CPU_TOPOLOGY="disabled"
export PW_MESA_GL_VERSION_OVERRIDE="disabled"
export PW_VKD3D_FEATURE_LEVEL="disabled"
export PW_LOCALE_SELECT="disabled"
export PW_MESA_VK_WSI_PRESENT_MODE="disabled"
export SOUND_DRIVER_USE="disabled"
export PW_CPU_NUMA_NODE_INDEX="disabled"
export PW_TASKSET_SLR=""
PPDB_EOF
            fi
        fi

        if [[ -n "$T_EXE" && ! -f "$WORK_DIR/autorun.cmd" ]]; then
            EXE_DIR_ABS=$(dirname "$T_EXE")
            EXE_NAME=$(basename "$T_EXE")
            REL_DIR=$(realpath --relative-to="$WORK_DIR" "$EXE_DIR_ABS" 2>/dev/null)
            if [[ -n "$REL_DIR" && "$REL_DIR" != "." ]]; then
                printf 'DIR="%s"\r\nCMD="%s"\r\n' "$REL_DIR" "$EXE_NAME" > "$WORK_DIR/autorun.cmd"
            else
                printf 'CMD="%s"\r\n' "$EXE_NAME" > "$WORK_DIR/autorun.cmd"
            fi
        fi

        progress 85 "Reempaquetando SquashFS..."
        mksquashfs "$WORK_DIR" "$FINAL_WSQUASHFS" -comp zstd -b 1M -noappend
        [[ "$WORK_DIR" != "$EXTRACT_DIR" ]] && rm -rf "$WORK_DIR"
        rm -rf "$OVERLAY_BASE/${NAME}"
    else
        [ "$(realpath "$WSQUASHFS_PATH")" != "$(realpath "$FINAL_WSQUASHFS")" ] && mv -f "$WSQUASHFS_PATH" "$FINAL_WSQUASHFS"
    fi
    [ -d "$EXTRACT_DIR" ] && rm -rf "$EXTRACT_DIR"
fi

# =================================================
# 🛠️ PIEZA 4: MONTAJE OVERLAYFS Y SELECCIÓN DE RUTA
# =================================================
if [ "$IS_SQUASH" = true ]; then
    MOUNT_RO=$(realpath -m "$MOUNT_BASE/${NAME}_ro")
    MOUNT_RW=$(realpath -m "$MOUNT_BASE/${NAME}")
    U_DIR=$(mkdir -p "$OVERLAY_BASE/${NAME}/data" && realpath "$OVERLAY_BASE/${NAME}/data")
    W_DIR=$(mkdir -p "$OVERLAY_BASE/${NAME}/work" && realpath "$OVERLAY_BASE/${NAME}/work")

    find "$U_DIR" -maxdepth 1 -type f -iname "*.ppdb" -delete 2>/dev/null || true
    chmod -R u+rwX "$U_DIR" 2>/dev/null || true
    rm -rf "$W_DIR" && mkdir -p "$W_DIR"
    chmod 755 "$OVERLAY_BASE/${NAME}" "$U_DIR" "$W_DIR" 2>/dev/null || true

    mkdir -p "$MOUNT_RO" "$MOUNT_RW"
    fusermount -u "$MOUNT_RW" 2>/dev/null || true
    fusermount -u "$MOUNT_RO" 2>/dev/null || true

    progress 98 "Montando capas de sistema..."
    "$DIR/squashfuse" "$FINAL_WSQUASHFS" "$MOUNT_RO"

    if ! "$DIR/fuse-overlayfs" -o lowerdir="$MOUNT_RO",upperdir="$U_DIR",workdir="$W_DIR",squash_to_uid=$(id -u) "$MOUNT_RW"; then
        echo "⚠️ Falló OverlayFS, modo Solo Lectura activado"
        L_BASE="$MOUNT_RO"
    else
        L_BASE="$MOUNT_RW"
        chmod -R u+rwX "$L_BASE/drive_c" 2>/dev/null || true
    fi

    F_PPDB=$(find "$L_BASE" -type f -iname "*.ppdb" \( -ipath "*/Binaries/Win64/*" -o -ipath "*/Binaries/Win32/*" -o -ipath "*/Win64/*" -o -ipath "*/Win32/*" \) 2>/dev/null | head -n1)

    [[ -z "$F_PPDB" ]] && F_PPDB=$(find "$L_BASE" -maxdepth 1 -type f -iname "*.ppdb" 2>/dev/null | head -n1)

    [[ -z "$F_PPDB" && -d "$L_BASE/drive_c" ]] && F_PPDB=$(find "$L_BASE/drive_c" -maxdepth 1 -type f -iname "*.ppdb" 2>/dev/null | head -n1)

    if [[ -z "$F_PPDB" ]]; then
        F_PPDB=$(find "$L_BASE" -type f -iname "*.ppdb" ! -ipath "*/windows/*" ! -ipath "*/Windows/*" ! -ipath "*/system32/*" 2>/dev/null | head -n1)
    fi

    if [[ -n "$F_PPDB" ]]; then
        LAUNCH_PATH="${F_PPDB%.ppdb}"
        echo "[+] Localizado PPDB legítimo en: $F_PPDB"
    else
        M_AUTO=$(find "$L_BASE" -type f -iname "autorun.cmd" 2>/dev/null | head -n1)
        if [[ -f "$M_AUTO" ]]; then
            parse_autorun "$M_AUTO"
            if [[ -n "$R_CMD_BASE" ]]; then
                [[ -n "$R_DIR" ]] && LAUNCH_PATH=$(find "$L_BASE" -ipath "*${R_DIR}*" -iname "$R_CMD_BASE" 2>/dev/null | head -n1)
                [[ -z "$LAUNCH_PATH" ]] && LAUNCH_PATH=$(find "$L_BASE" -iname "$R_CMD_BASE" 2>/dev/null | head -n1)
            fi
        fi
        [[ -z "$LAUNCH_PATH" ]] && LAUNCH_PATH=$(find_game_exe "$L_BASE")
    fi
else
    LAUNCH_PATH="$(realpath "$INPUT_PATH")"
fi

if [[ -z "$LAUNCH_PATH" ]]; then
    echo "❌ Error Crítico: No se pudo determinar ningún ejecutable válido para iniciar."
    exit 1
fi

# =================================================
# 🎮 PIEZA 5: MAPEADOR Y EJECUCIÓN FINAL
# =================================================
trap 'fusermount -u "$MOUNT_RW" 2>/dev/null; fusermount -u "$MOUNT_RO" 2>/dev/null; [ -n "$MAPEO_PID" ] && kill "$MAPEO_PID" 2>/dev/null' EXIT

F_KEYS=""
if [ "$IS_SQUASH" = false ] && [[ "$INPUT_PATH" == *.AppImage || "$INPUT_PATH" == *.appimage ]]; then
    [ -f "${INPUT_PATH%.*}.keys" ] && F_KEYS="${INPUT_PATH%.*}.keys"
    [ -f "$INPUT_PATH.keys" ] && F_KEYS="$INPUT_PATH.keys"
else
    [ -f "$(dirname "$FINAL_WSQUASHFS")/$NAME.keys" ] && F_KEYS="$(dirname "$FINAL_WSQUASHFS")/$NAME.keys"
    [ -f "$FINAL_WSQUASHFS.keys" ] && F_KEYS="$FINAL_WSQUASHFS.keys"
fi

if [ -n "$F_KEYS" ]; then
    echo "[+] Engranando mapeador portable para: $F_KEYS"
    export PYTHONPATH="$LIB_DIR:$EVMAPY_DIR"
    python3 "$DIR/mapeador.py" "$F_KEYS" &
    MAPEO_PID=$!
    sleep 2
fi

progress 100 "¡Maquinaria lista! Lanzando juego..."
export START_FROM_STEAM=1

if [ "$IS_SQUASH" = true ]; then
    "$PORTPROTON" "$(realpath "$LAUNCH_PATH")"
else
    if [[ "$INPUT_PATH" == *.AppImage || "$INPUT_PATH" == *.appimage ]]; then
        "$INPUT_PATH"
    else
        "$PORTPROTON" "$(realpath "$LAUNCH_PATH")"
    fi
fi
