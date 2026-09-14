#!/bin/bash
#
# KSM Compressor/Decompressor v8.3 (Lote Total + Sudo Persistente)
#

# --- Configuración ---
COMPRESION="zstd"
NIVEL_ZSTD="6"
BLOQUE="512K"
# Ajusta esta ruta si tu script no está en la raíz de DeckStation
PORTPROTON_PATH="$(dirname "$(realpath "$0")")/Apps/PortProton/data/scripts/start.sh"
SUDO_ALIVE_STARTED=false
# --------------------

# --- Función: Mantener Sudo Activo ---
keep_sudo_alive() {
    if [ "$SUDO_ALIVE_STARTED" = false ]; then
        echo "🔑 Solicitando permisos de administrador (solo una vez) para procesos desatendidos..."
        sudo -v
        (while true; do sudo -n -v 2>/dev/null; sleep 120; done) &
        SUDO_KEEP_ALIVE_PID=$!
        trap 'kill $SUDO_KEEP_ALIVE_PID 2>/dev/null' EXIT
        SUDO_ALIVE_STARTED=true
        echo "✅ Sesión de administrador asegurada. El proceso no se interrumpirá."
    fi
}

# --- Función: Inyección de Perfil Maestro ---
inject_universal_profile() {
    local ppdb_file="$1"
    cat > "$ppdb_file" << 'EOF'
export PW_WINE_USE="PROTON_LG_10-28"
export PW_PREFIX_NAME="DEFAULT"
export PW_VULKAN_USE="3"
export PW_MANGOHUD="0"
export PW_MANGOHUD_USER_CONF="0"
export PW_VKBASALT="0"
export PW_VKBASALT_USER_CONF="0"
export PW_DGVOODOO2="0"
export PW_USE_ESYNC="0"
export PW_USE_FSYNC="0"
export PW_USE_NTSYNC="1"
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
export PW_USE_NATIVE_WAYLAND="0"
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
EOF
}

# --- Funciones Base ---
create_autorun() {
    local game_folder="$1"
    mapfile -t exes < <(find "$game_folder" -type f -iname "*.exe")
    if [ ${#exes[@]} -eq 0 ]; then echo "ADVERTENCIA: No se encontraron archivos .exe."; return; fi
    echo "Se han encontrado los siguientes archivos .exe:"
    for i in "${!exes[@]}"; do printf "  %s) %s\n" "$((i+1))" "${exes[$i]#"$game_folder/"}"; done
    echo "  0) Omitir / No crear autorun.cmd"
    read -p "Introduce el número del ejecutable principal: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#exes[@]} ]; then echo "Opción no válida. Omitiendo."; return; fi
    if [ "$choice" -eq 0 ]; then echo "Omitiendo creación de autorun.cmd."; return; fi

    local selected_exe_path="${exes[$((choice-1))]}"
    local cmd_value=$(basename "$selected_exe_path")
    local dir_full_path=$(dirname "$selected_exe_path")

    if [[ "$cmd_value" == *" "* ]]; then cmd_value="\"$cmd_value\""; fi

    local autorun_file="$game_folder/autorun.cmd"
    echo "# Creado por KSM Compressor" > "$autorun_file"

    if [ "$dir_full_path" != "$game_folder" ]; then
        local dir_relative_path="${dir_full_path#"$game_folder/"}"
        if [[ "$dir_relative_path" == *" "* ]]; then dir_relative_path="\"$dir_relative_path\""; fi
        echo "DIR=$dir_relative_path" >> "$autorun_file"
    fi
    echo "CMD=$cmd_value" >> "$autorun_file"
    echo "ÉXITO: Se ha creado 'autorun.cmd'."

    local ppdb_file="${selected_exe_path}.ppdb"
    echo "Generando perfil universal DeckStation en $(basename "$ppdb_file")..."
    inject_universal_profile "$ppdb_file"
    echo "ÉXITO: Perfil inyectado de forma limpia."
}

compress_folder() {
    keep_sudo_alive
    local target_path=$1; local delete_original=$2
    if [ "$IN_BATCH_MODE" != "true" ]; then
        read -p "¿Deseas crear o actualizar el archivo autorun.cmd? (S/n): " confirm_autorun
        if [[ $confirm_autorun != "n" && $confirm_autorun != "N" ]]; then create_autorun "$target_path"; fi
    fi
    local source_dir_name=$(basename "$target_path" .pc)
    source_dir_name=${source_dir_name%_taller}
    local output_parent_dir=$(dirname "$target_path")
    local output_file="$output_parent_dir/${source_dir_name}.wsquashfs"

    echo "--- Comprimiendo: $(basename "$target_path") ---"
    sudo chattr -R -i "$target_path" 2>/dev/null || true

    [ -f "$output_file" ] && rm -f "$output_file"

    if sudo mksquashfs "$target_path" "$output_file" -comp "$COMPRESION" -b "$BLOQUE" -Xcompression-level "$NIVEL_ZSTD" -no-xattrs -progress; then
        sudo chown $USER:$USER "$output_file"; echo "ÉXITO: Comprimido a $(basename "$output_file")"
        if [ "$delete_original" = true ]; then sudo rm -rf "$target_path"; echo "INFO: Carpeta de origen eliminada."; fi
    else echo "ERROR: Falló la compresión de $(basename "$target_path")"; fi; echo ""
}

decompress_file() {
    keep_sudo_alive
    local target_file=$1; local delete_original=$2; local base_name=$(basename "$target_file" .wsquashfs); local output_parent_dir=$(dirname "$target_file"); local output_dir="$output_parent_dir/${base_name}.pc"
    echo "--- Descomprimiendo: $(basename "$target_file") ---"

    if unsquashfs -f -d "$output_dir" "$target_file"; then
        sudo chown -R $USER:$USER "$output_dir"
        echo "ÉXITO: Descomprimido en $(basename "$output_dir")"
        if [ "$delete_original" = true ]; then rm "$target_file"; echo "INFO: Archivo de origen eliminado."; fi
    else echo "ERROR: Falló la descompresión de $(basename "$target_file")"; fi; echo ""
}

# --- Funciones de Taller y Lotes ---
batch_process_all() {
    keep_sudo_alive
    local target_dir="$1"
    echo "=================================================="
    echo "🔄 INICIANDO LOTE TOTAL (INYECCIÓN Y COMPRESIÓN)"
    echo "Directorio: $target_dir"
    echo "=================================================="

    local count=0
    local del_all_pc="n"

    # Preguntar si hay carpetas .pc para no interrumpir luego el proceso
    if ls "$target_dir"/*.pc 1> /dev/null 2>&1; then
        read -p "¿Deseas ELIMINAR las carpetas '.pc' originales tras comprimirlas con éxito? (s/N): " del_all_pc
    fi

    # 1. Procesar archivos .wsquashfs
    for wsq in "$target_dir"/*.wsquashfs; do
        [ -e "$wsq" ] || continue
        ((count++))
        local base_name=$(basename "$wsq" .wsquashfs)
        local temp_dir="$target_dir/${base_name}_taller.pc"

        echo "-> [$count] Extrayendo e inyectando: $base_name.wsquashfs"
        rm -rf "$temp_dir"
        if ! unsquashfs -f -d "$temp_dir" "$wsq" >/dev/null; then
            echo "❌ ERROR: No se pudo extraer $base_name. Saltando."
            continue
        fi

        local exe_path=""
        if [ -f "$temp_dir/autorun.cmd" ]; then
            local r_dir=$(grep -i "^DIR=" "$temp_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            local r_cmd=$(grep -i "^CMD=" "$temp_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            if [ -n "$r_dir" ]; then
                exe_path="$temp_dir/$r_dir/$r_cmd"
            else
                exe_path="$temp_dir/$r_cmd"
            fi
        else
            exe_path=$(find "$temp_dir" -type f -iname "*.exe" | head -n 1)
        fi

        if [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
            echo "⚠️ No se detectó un .exe claro. Saltando inyección."
        else
            local ppdb_path="${exe_path}.ppdb"
            inject_universal_profile "$ppdb_path"
            echo "✅ Perfil universal inyectado."
        fi

        echo "📦 Reempaquetando..."
        sudo chattr -R -i "$temp_dir" 2>/dev/null || true
        rm -f "$wsq"
        if sudo mksquashfs "$temp_dir" "$wsq" -comp "$COMPRESION" -b "$BLOQUE" -Xcompression-level "$NIVEL_ZSTD" -no-xattrs >/dev/null; then
            sudo chown $USER:$USER "$wsq"
            echo "✅ Empaquetado exitoso."
        else
            echo "❌ Falló el empaquetado de $base_name."
        fi

        sudo rm -rf "$temp_dir"
        echo "--------------------------------------------------"
    done

    # 2. Procesar carpetas .pc
    for pc_dir in "$target_dir"/*.pc; do
        [ -e "$pc_dir" ] || continue
        [ -d "$pc_dir" ] || continue
        ((count++))
        local base_name=$(basename "$pc_dir" .pc)

        echo "-> [$count] Inyectando y Comprimiendo Carpeta: $base_name.pc"

        local exe_path=""
        if [ -f "$pc_dir/autorun.cmd" ]; then
            local r_dir=$(grep -i "^DIR=" "$pc_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            local r_cmd=$(grep -i "^CMD=" "$pc_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            if [ -n "$r_dir" ]; then
                exe_path="$pc_dir/$r_dir/$r_cmd"
            else
                exe_path="$pc_dir/$r_cmd"
            fi
        else
            exe_path=$(find "$pc_dir" -type f -iname "*.exe" | head -n 1)
        fi

        if [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
            echo "⚠️ No se detectó un .exe claro. Saltando inyección."
        else
            local ppdb_path="${exe_path}.ppdb"
            inject_universal_profile "$ppdb_path"
            echo "✅ Perfil universal inyectado."
        fi

        echo "📦 Comprimiendo a .wsquashfs..."
        local out_wsq="$target_dir/${base_name}.wsquashfs"
        sudo chattr -R -i "$pc_dir" 2>/dev/null || true
        rm -f "$out_wsq"
        if sudo mksquashfs "$pc_dir" "$out_wsq" -comp "$COMPRESION" -b "$BLOQUE" -Xcompression-level "$NIVEL_ZSTD" -no-xattrs >/dev/null; then
            sudo chown $USER:$USER "$out_wsq"
            echo "✅ Compresión exitosa."
            if [[ "$del_all_pc" == "s" || "$del_all_pc" == "S" ]]; then
                sudo rm -rf "$pc_dir"
                echo "🗑️ Carpeta original eliminada."
            fi
        else
            echo "❌ Falló la compresión."
        fi
        echo "--------------------------------------------------"
    done

    if [ "$count" -eq 0 ]; then
        echo "No se encontraron archivos .wsquashfs ni carpetas .pc."
    else
        echo "🎉 PROCESO POR LOTES COMPLETADO ($count elementos procesados)."
    fi
}

debug_folder() {
    keep_sudo_alive
    local target_dir=$1
    echo "=================================================="
    echo "🛠️ INICIANDO MODO TALLER EN CARPETA: $(basename "$target_dir")"
    echo "=================================================="

    while true; do
        local exe_path=""
        if [ -f "$target_dir/autorun.cmd" ]; then
            local r_dir=$(grep -i "^DIR=" "$target_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            local r_cmd=$(grep -i "^CMD=" "$target_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            if [ -n "$r_dir" ]; then
                exe_path="$target_dir/$r_dir/$r_cmd"
            else
                exe_path="$target_dir/$r_cmd"
            fi
        else
            exe_path=$(find "$target_dir" -type f -iname "*.exe" | head -n 1)
        fi

        local ppdb_path="${exe_path}.ppdb"

        echo ""
        echo "--------------------------------------------------"
        echo "🔧 MODO TALLER ACTIVO (CARPETA): $(basename "$target_dir")"
        if [ -n "$exe_path" ]; then
            echo "🎯 Ejecutable actual: $(basename "$exe_path")"
        else
            echo "⚠️ No se detectó ejecutable. ¡Inyecta la configuración primero!"
        fi
        echo "--------------------------------------------------"
        echo "  1) 🎮 PROBAR EL JUEGO (Lanzar con PortProton)"
        echo "  2) 📝 EDITAR ARCHIVO PPDB A MANO (nano)"
        echo "  3) 💉 CREAR AUTORUN E INYECTAR PERFIL DECKSTATION"
        echo "  4) 📦 COMPRIMIR EN .WSQUASHFS Y FINALIZAR"
        echo "  0) 🚪 SALIR DEL TALLER (Sin comprimir)"
        echo "--------------------------------------------------"
        read -p "Elige una opción: " opt

        case $opt in
            1)
                if [ ! -f "$PORTPROTON_PATH" ]; then
                    echo "❌ ERROR: No se encuentra PortProton en: $PORTPROTON_PATH"
                elif [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
                    echo "❌ ERROR: No se encontró el ejecutable. Usa la opción 3 primero."
                else
                    echo "🚀 Lanzando juego... Cierra el juego por completo para regresar al taller."
                    export START_FROM_STEAM=1
                    "$PORTPROTON_PATH" "$exe_path"
                    echo "✅ Pruebas finalizadas. Entorno liberado."
                fi
                ;;
            2)
                if [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
                    echo "❌ ERROR: Primero usa la opción 3 para definir el ejecutable."
                else
                    if [ ! -f "$ppdb_path" ]; then
                        echo "⚠️ No existe $ppdb_path. Se creará uno vacío."
                        touch "$ppdb_path"
                    fi
                    nano "$ppdb_path"
                    echo "💾 Cambios aplicados de forma local."
                fi
                ;;
            3)
                create_autorun "$target_dir"
                ;;
            4)
                echo "📦 Iniciando compresión definitiva..."
                export IN_BATCH_MODE="true"
                compress_folder "$target_dir" false
                echo "✅ Proceso completado. Saliendo del taller."
                break
                ;;
            0)
                echo "🚪 Saliendo del taller sin comprimir."
                break
                ;;
            *)
                echo "Opción no válida."
                ;;
        esac
    done
}

debug_repack_file() {
    keep_sudo_alive
    local target_file=$1
    local base_name=$(basename "$target_file" .wsquashfs)
    local output_parent_dir=$(dirname "$target_file")
    local taller_dir="$output_parent_dir/${base_name}_taller.pc"

    echo "=================================================="
    echo "🛠️ INICIANDO MODO TALLER PARA: $base_name"
    echo "=================================================="
    echo "Extrayendo juego al taller temporal..."

    rm -rf "$taller_dir"
    if ! unsquashfs -f -d "$taller_dir" "$target_file" >/dev/null; then
        echo "❌ ERROR: No se pudo extraer el archivo."
        return
    fi
    sudo chown -R $USER:$USER "$taller_dir"

    local exe_path=""
    while true; do
        if [ -f "$taller_dir/autorun.cmd" ]; then
            local r_dir=$(grep -i "^DIR=" "$taller_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            local r_cmd=$(grep -i "^CMD=" "$taller_dir/autorun.cmd" | cut -d'=' -f2 | tr -d '"\r')
            if [ -n "$r_dir" ]; then
                exe_path="$taller_dir/$r_dir/$r_cmd"
            else
                exe_path="$taller_dir/$r_cmd"
            fi
        else
            exe_path=$(find "$taller_dir" -type f -iname "*.exe" | head -n 1)
        fi

        local ppdb_path="${exe_path}.ppdb"

        echo ""
        echo "--------------------------------------------------"
        echo "🔧 MODO TALLER ACTIVO (WSQUASHFS): $(basename "$target_file")"
        echo "--------------------------------------------------"
        echo "  1) 🎮 PROBAR EL JUEGO (Lanzar con PortProton)"
        echo "  2) 📝 EDITAR ARCHIVO PPDB A MANO (nano)"
        echo "  3) 💉 RE-INYECTAR CONFIGURACIÓN MAESTRA DECKSTATION"
        echo "  4) 📦 REEMPAQUETAR Y FINALIZAR (Sobrescribir original)"
        echo "  0) ❌ CANCELAR Y LIMPIAR TALLER"
        echo "--------------------------------------------------"
        read -p "Elige una opción: " opt

        case $opt in
            1)
                if [ ! -f "$PORTPROTON_PATH" ]; then
                    echo "❌ ERROR: No se encuentra PortProton en: $PORTPROTON_PATH"
                elif [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
                    echo "❌ ERROR: No se encontró el ejecutable $exe_path"
                else
                    echo "🚀 Lanzando juego... Cierra el juego por completo para regresar al taller."
                    export START_FROM_STEAM=1
                    "$PORTPROTON_PATH" "$exe_path"
                    echo "✅ Pruebas finalizadas. Entorno liberado."
                fi
                ;;
            2)
                if [ ! -f "$ppdb_path" ]; then
                    echo "⚠️ No existe $ppdb_path. Se creará uno vacío."
                    touch "$ppdb_path"
                fi
                nano "$ppdb_path"
                echo "💾 Cambios aplicados de forma local."
                ;;
            3)
                create_autorun "$taller_dir"
                ;;
            4)
                echo "📦 Reempaquetando volumen... (Esto sobrescribirá tu archivo original)"
                export IN_BATCH_MODE="true"
                compress_folder "$taller_dir" true
                echo "✅ Compresión concluida con éxito. Saliendo del taller."
                break
                ;;
            0)
                echo "🧹 Eliminando directorios temporales..."
                sudo rm -rf "$taller_dir"
                echo "🚪 Operación abortada."
                break
                ;;
            *)
                echo "Opción no válida."
                ;;
        esac
    done
}

# --- LÓGICA PRINCIPAL (MENÚ INICIAL) ---
if [ -z "$1" ]; then
    echo "===================================================="
    echo "        GESTOR KSM - MENÚ PRINCIPAL"
    echo "===================================================="
    echo "  1) Seleccionar CARPETA (.pc)"
    echo "  2) Seleccionar ARCHIVO (.wsquashfs)"
    echo "  3) 🚀 INYECCIÓN LOTE TOTAL (Procesa .wsquashfs y .pc)"
    echo "  0) Salir"
    echo "===================================================="
    read -p "Elige una opción: " sel_tipo

    case $sel_tipo in
        1)
            SELECCION=$(kdialog --getexistingdirectory "Selecciona la carpeta a tratar" 2>/dev/null || zenity --file-selection --directory --title="Selecciona la carpeta a tratar" 2>/dev/null)
            ;;
        2)
            SELECCION=$(kdialog --getopenfilename "$PWD" "*.wsquashfs" 2>/dev/null || zenity --file-selection --file-filter="*.wsquashfs" --title="Selecciona el archivo .wsquashfs" 2>/dev/null)
            ;;
        3)
            SELECCION=$(kdialog --getexistingdirectory "Selecciona la carpeta que contains los juegos" 2>/dev/null || zenity --file-selection --directory --title="Selecciona la carpeta de los juegos" 2>/dev/null)
            if [ -n "$SELECCION" ]; then
                batch_process_all "$SELECCION"
                read -p "Presiona Enter para salir..."
                exit 0
            fi
            ;;
        *)
            echo "Operación cancelada."; exit 0
            ;;
    esac

    if [ -z "$SELECCION" ]; then
        echo "No se seleccionó ningún elemento. Saliendo."; exit 0
    fi

    set -- "$SELECCION"
fi

# Escenario 1: Operaciones sobre un ÚNICO ARCHIVO .wsquashfs
if [ "$#" -eq 1 ] && [ -f "$1" ] && [[ "$1" == *.wsquashfs ]]; then
    INPUT_PATH="$1"
    echo "----------------------------------------------------"
    echo "Se ha detectado el archivo comprimido: '$(basename "$INPUT_PATH")'"
    echo "¿Qué deseas hacer?"
    echo "  1) Descomprimir este archivo a carpeta '.pc'"
    echo "  2) 🔧 Entrar en MODO TALLER (Probar, editar y reempaquetar)"
    echo "  0) Cancelar"
    echo "----------------------------------------------------"
    read -p "Elige una opción: " choice

    case $choice in
        1)
            decompress_file "$INPUT_PATH" false
            ;;
        2)
            debug_repack_file "$INPUT_PATH"
            ;;
        *)
            echo "Operación cancelada."
            ;;
    esac
    read -p "--- Proceso finalizado. Presiona Enter para salir. ---"; exit 0
fi

# Escenario 2: Operaciones sobre una ÚNICA CARPETA
if [ "$#" -eq 1 ] && [ -d "$1" ]; then
    INPUT_PATH="$1"
    echo "----------------------------------------------------"
    echo "Se ha detectado la carpeta: '$(basename "$INPUT_PATH")'"
    echo "¿Qué deseas hacer?"
    echo "  1) 📦 Comprimir directamente esta carpeta"
    echo "  2) 🔧 Entrar en MODO TALLER (Probar, editar e inyectar)"
    echo "  3) 🚀 LOTE TOTAL en esta carpeta (Procesa todo lo que hay dentro)"
    echo "  0) Cancelar"
    echo "----------------------------------------------------"
    read -p "Elige una opción: " choice

    case $choice in
        1)
            export IN_BATCH_MODE="false"
            TARGET_PATH="$INPUT_PATH"
            if [[ "$INPUT_PATH" != *.pc ]]; then
                NEW_PATH="${INPUT_PATH}.pc"; echo "AVISO: La carpeta no termina en '.pc'."
                read -p "Se renombrará a '$(basename "$NEW_PATH")'. ¿Continuar? (S/n): " confirm_rename
                if [[ $confirm_rename != "n" && $confirm_rename != "N" ]]; then mv "$INPUT_PATH" "$NEW_PATH"; TARGET_PATH="$NEW_PATH"; else echo "Cancelado."; exit 0; fi
            fi
            compress_folder "$TARGET_PATH" false
            ;;
        2)
            TARGET_PATH="$INPUT_PATH"
            if [[ "$INPUT_PATH" != *.pc ]]; then
                NEW_PATH="${INPUT_PATH}.pc"; echo "AVISO: La carpeta no termina en '.pc'."
                read -p "Se renombrará a '$(basename "$NEW_PATH")'. ¿Continuar? (S/n): " confirm_rename
                if [[ $confirm_rename != "n" && $confirm_rename != "N" ]]; then mv "$INPUT_PATH" "$NEW_PATH"; TARGET_PATH="$NEW_PATH"; else echo "Cancelado."; exit 0; fi
            fi
            debug_folder "$TARGET_PATH"
            ;;
        3)
            batch_process_all "$INPUT_PATH"
            ;;
        *)
            echo "Operación cancelada."
            ;;
    esac
    read -p "--- Proceso finalizado. Presiona Enter para salir. ---"; exit 0
fi

# Escenario 3: Ejecución en lote por Arrastre múltiple
export IN_BATCH_MODE="false"
echo "--- Procesando elementos individuales ---"
for ITEM in "$@"; do
    TARGET_PATH="$ITEM"
    if [[ -d "$ITEM" && "$ITEM" != *.pc ]]; then
        NEW_PATH="${ITEM}.pc"; echo "AVISO: La carpeta '$(basename "$ITEM")' no termina en '.pc'."
        read -p "Se renombrará a '$(basename "$NEW_PATH")'. ¿Continuar? (S/n): " confirm_rename
        if [[ $confirm_rename != "n" && $confirm_rename != "N" ]]; then mv "$ITEM" "$NEW_PATH"; TARGET_PATH="$NEW_PATH"; echo "Carpeta renombrada."; else echo "Operación cancelada."; continue; fi
    fi
    if [ -d "$TARGET_PATH" ]; then
        compress_folder "$TARGET_PATH" false
    elif [[ -f "$TARGET_PATH" && "$TARGET_PATH" == *.wsquashfs ]]; then
        decompress_file "$TARGET_PATH" false
    else echo "ADVERTENCIA: '$ITEM' no es un elemento válido. Omitiendo."; fi
done
read -p "--- Todas las tareas han finalizado. Presiona Enter para salir. ---"
exit 0
