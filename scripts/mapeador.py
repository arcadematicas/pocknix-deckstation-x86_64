import sys, os; _BASE_DIR = os.path.dirname(os.path.abspath(sys.argv[0])); sys.path.insert(0, os.path.join(_BASE_DIR, 'libs_py3.14')); sys.path.insert(0, os.path.join(_BASE_DIR, 'evmapy'))
import evdev
from evdev import ecodes
import json
import select
import time

# Mapeos de ejes analógicos por defecto para mandos estándar
ABS_ESTANDAR = {
    ecodes.ABS_Y:     ("joystick1up",   "joystick1down"),
    ecodes.ABS_X:     ("joystick1left",  "joystick1right"),
    ecodes.ABS_RY:    ("joystick2up",   "joystick2down"),
    ecodes.ABS_RX:    ("joystick2left",  "joystick2right"),
    ecodes.ABS_HAT0Y: ("up",            "down"),
    ecodes.ABS_HAT0X: ("left",          "right"),
}

# CONFIGURACIÓN FÍSICA DE BOTONES, EJES Y UMBRALES
PERFILES = {
    "XBOX_360": {
        "match": ["microsoft", "xbox 360", "360", "x-box 360"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    },
    "XBOX_ONE": {
        "match": ["xbox one", "xbox wireless", "xbox gaming", "input joystick", "x-box one"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    },
    "8BITDO_ULTIMATE": {
        "match": ["ultimate", "ultimate 2c", "2c"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 40,   # Umbral adaptado para rango 0-255 (Centro 127)
        "center": 127       # Desplazamiento del punto muerto central para este mando
    },
    "SONY_DS4": {
        "match": ["sony", "playstation", "wireless controller", "dualshock 4", "ps4"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 316, "r2": 317, "l3": 318, "r3": 319
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    },
    "SONY_PS5": {
        "match": ["dualsense", "ps5"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 314, "r2": 315, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    },
    "8BITDO": {
        "match": ["8bitdo", "8bitdo pro 2", "8bitdo sn30"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    },
    "NINTENDO_SWITCH": {
        "match": ["nintendo", "switch", "pro controller", "joy-con"],
        "ids": {
            "a": 305, "b": 304, "x": 309, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 314, "r2": 315, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    },
    "GENERIC": {
        "match": [],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR,
        "threshold": 16000,
        "center": 0
    }
}

def get_perfil(dev_name):
    name = dev_name.lower()
    for p in PERFILES.values():
        if any(m in name for m in p["match"]):
            return p
    return PERFILES["GENERIC"]

def main():
    try:
        os.nice(-10)
    except:
        pass

    if len(sys.argv) < 2:
        print("Uso: python3 mapeador.py archivo.keys")
        return

    try:
        with open(sys.argv[1], 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error al cargar .keys: {e}")
        return

    pads = []
    for p in evdev.list_devices():
        try:
            dev = evdev.InputDevice(p)
            dev_name = dev.name.lower()
            if any(x in dev_name for x in ["motion", "accelerometer", "gyro", "touchpad", "mouse", "keyboard"]):
                continue
            if ecodes.EV_ABS in dev.capabilities() and ecodes.EV_KEY in dev.capabilities():
                pads.append(dev)
        except:
            continue

    if not pads:
        print("No se encontró ningún mando válido en el sistema.")
        return

    print("[+] Esperando pulsación en el mando (Timeout ampliado: 30s)...")
    device = None
    start_time = time.time()
    
    while not device and (time.time() - start_time) < 30.0:
        r, _, _ = select.select(pads, [], [], 0.1)
        for fd in r:
            try:
                for event in fd.read():
                    if event.type == ecodes.EV_KEY and event.value == 1:
                        device = fd
                        break
            except:
                continue
            if device: break

    if not device:
        print("[-] Timeout alcanzado. Aplicando auto-selección de mando...")
        for pad in pads:
            pad_name = pad.name.lower()
            if any(m in pad_name for m in ["xbox", "360", "microsoft", "8bitdo", "ultimate", "dualsense", "sony", "nintendo", "wireless"]):
                device = pad
                break
        if not device:
            device = pads[0]

    print(f"VINCULADO DE FORMA SEGURA: {device.name}")
    
    perfil_actual = get_perfil(device.name)
    ids = perfil_actual["ids"]
    abs_map_actual = perfil_actual["abs_map"]
    threshold_actual = perfil_actual["threshold"]
    center_actual = perfil_actual["center"]

    map_normal = {}
    map_combos = []
    DIR_KEYS = ["up", "down", "left", "right",
                "joystick1up", "joystick1down", "joystick1left", "joystick1right",
                "joystick2up", "joystick2down", "joystick2left", "joystick2right"]
    map_dirs = {k: [] for k in DIR_KEYS}

    for act in data.get('actions_player1', []):
        trig, target = act['trigger'], act['target']
        t_codes = [getattr(ecodes, t) for t in (target if isinstance(target, list) else [target]) if hasattr(ecodes, t)]

        if isinstance(trig, list):
            map_combos.append({"req": [ids.get(x, x) for x in trig], "outs": t_codes, "active": False})
        elif trig in map_dirs:
            map_dirs[trig] = t_codes
        elif trig in ids:
            map_normal[ids[trig]] = t_codes

    try:
        ui = evdev.UInput(name="Mapeador_KB_Portable")
    except Exception as e:
        print(f"ERROR: No se pudo crear el teclado virtual. {e}")
        return

    pulsados = set()
    ejes_on = {k: False for k in DIR_KEYS}

    while True:
        r, _, _ = select.select([device], [], [], 0.001)
        if r:
            try:
                for event in device.read():
                    if event.type == ecodes.EV_KEY:
                        if event.value == 1:
                            pulsados.add(event.code)
                        elif event.value == 0:
                            pulsados.discard(event.code)

                        for c in map_combos:
                            all_pressed = all(btn in pulsados for btn in c["req"])
                            if all_pressed and not c["active"] and event.value == 1:
                                c["active"] = True
                                for t in c["outs"]: ui.write(ecodes.EV_KEY, t, 1)
                            elif c["active"] and not all_pressed and event.value == 0:
                                c["active"] = False
                                for t in c["outs"]: ui.write(ecodes.EV_KEY, t, 0)

                        in_active_combo = any(event.code in c["req"] and c["active"] for c in map_combos)
                        if not in_active_combo and event.code in map_normal:
                            for t in map_normal[event.code]: ui.write(ecodes.EV_KEY, t, event.value)
                        ui.syn()

                    elif event.type == ecodes.EV_ABS and event.code in abs_map_actual:
                        neg_dir, pos_dir = abs_map_actual[event.code]

                        # Normalizar el valor restando el punto central (0 para Xbox, 127 para Ultimate 2C)
                        val_normalizado = event.value - center_actual

                        neg_active = val_normalizado < -threshold_actual
                        pos_active = val_normalizado > threshold_actual

                        for direction, active in ((neg_dir, neg_active), (pos_dir, pos_active)):
                            if active != ejes_on[direction]:
                                ejes_on[direction] = active
                                for t in map_dirs[direction]:
                                    ui.write(ecodes.EV_KEY, t, 1 if active else 0)
                        ui.syn()

            except (IOError, OSError):
                break

if __name__ == "__main__":
    main()
