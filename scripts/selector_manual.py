#!/usr/bin/env python3
"""
selector_manual.py — Selector de modo para DeckStation
Uso: python3 selector_manual.py <work_dir> <runners_dir> <result_file>
Escribe el resultado en result_file en lugar de stdout.
"""
import sys, os

_BASE = os.path.dirname(os.path.abspath(sys.argv[0]))
os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"
sys.path.insert(0, os.path.join(_BASE, 'libs_py3.14'))

WORK_DIR     = os.path.realpath(sys.argv[1]) if len(sys.argv) > 1 else "."
RUNNERS_DIR  = os.path.realpath(sys.argv[2]) if len(sys.argv) > 2 else "./Apps/PortProton/data/dist"
RESULT_FILE  = sys.argv[3]                   if len(sys.argv) > 3 else "/tmp/ds_result.txt"

def write_result(text):
    with open(RESULT_FILE, 'w') as f:
        f.write(text)

def auto():
    write_result("RESULT:AUTO\n")
    sys.exit(0)

# ── Pygame — igual que updater.py ────────────────────────────────────────────
import pygame

os.environ.setdefault('SDL_VIDEODRIVER', 'x11')
pygame.init()
pygame.joystick.init()

joystick = None
if pygame.joystick.get_count() > 0:
    joystick = pygame.joystick.Joystick(0)
    joystick.init()
    print(f"[selector] Mando detectado: {joystick.get_name()}", file=sys.stderr)
else:
    print("[selector] Sin mando detectado", file=sys.stderr)

pygame.key.set_repeat(200, 80)

# ── Ventana ───────────────────────────────────────────────────────────────────
try:
    info = pygame.display.Info()
    W = min(860, info.current_w - 40)
    H = min(600, info.current_h - 40)
    os.environ['SDL_VIDEO_WINDOW_POS'] = f'{(info.current_w-W)//2},{(info.current_h-H)//2}'
    screen = pygame.display.set_mode((W, H), pygame.NOFRAME)
    pygame.display.set_caption("DeckStation")
except Exception as e:
    print(f"[selector] Error display: {e}", file=sys.stderr)
    auto()

# Override redirect con conexión X11 propia (igual que _run_teclado)
try:
    import ctypes as _ct
    x11 = _ct.cdll.LoadLibrary('libX11.so.6')
    x11.XOpenDisplay.restype = _ct.c_void_p
    dpy = x11.XOpenDisplay(None)
    win = pygame.display.get_wm_info().get('window', 0)
    if dpy and win:
        class XWA(_ct.Structure):
            _fields_ = [('background_pixmap',_ct.c_ulong),('background_pixel',_ct.c_ulong),
                        ('border_pixmap',_ct.c_ulong),('border_pixel',_ct.c_ulong),
                        ('bit_gravity',_ct.c_int),('win_gravity',_ct.c_int),
                        ('backing_store',_ct.c_int),('backing_planes',_ct.c_ulong),
                        ('backing_pixel',_ct.c_ulong),('save_under',_ct.c_int),
                        ('event_mask',_ct.c_long),('do_not_propagate',_ct.c_long),
                        ('override_redirect',_ct.c_int),('colormap',_ct.c_ulong),
                        ('cursor',_ct.c_ulong)]
        wa = XWA(); wa.override_redirect = 1
        x11.XUnmapWindow(_ct.c_void_p(dpy), _ct.c_ulong(win))
        x11.XChangeWindowAttributes(_ct.c_void_p(dpy), _ct.c_ulong(win), _ct.c_ulong(0x200), _ct.byref(wa))
        x11.XMapWindow(_ct.c_void_p(dpy), _ct.c_ulong(win))
        x11.XSetInputFocus.argtypes = [_ct.c_void_p, _ct.c_ulong, _ct.c_int, _ct.c_ulong]
        x11.XSetInputFocus(_ct.c_void_p(dpy), _ct.c_ulong(win), _ct.c_int(1), _ct.c_ulong(0))
        x11.XRaiseWindow(_ct.c_void_p(dpy), _ct.c_ulong(win))
        x11.XFlush(_ct.c_void_p(dpy))
        x11.XCloseDisplay(_ct.c_void_p(dpy))
except Exception as e:
    print(f"[selector] X11 focus: {e}", file=sys.stderr)

# ── Colores y fuentes ─────────────────────────────────────────────────────────
C = {'bg':(18,18,28),'panel':(30,30,45),'sel':(40,120,210),
     'text':(220,220,220),'dim':(110,110,130),'title':(255,200,60),
     'hint':(90,90,110),'border':(55,55,75)}
b = max(14, H // 30)
F = {'h': pygame.font.SysFont('DejaVu Sans', b+4, bold=True),
     'n': pygame.font.SysFont('DejaVu Sans', b),
     's': pygame.font.SysFont('DejaVu Sans', b-2),
     'xs':pygame.font.SysFont('DejaVu Sans', b-4)}

def draw_header(title, sub=''):
    pygame.draw.rect(screen, C['panel'], (0,0,W,62))
    pygame.draw.line(screen, C['border'], (0,62),(W,62),1)
    screen.blit(F['h'].render(title, True, C['title']), (16,10))
    if sub: screen.blit(F['s'].render(sub, True, C['dim']), (16,40))

def draw_list(items, sel, y0=70):
    ih = F['n'].get_height() + 14
    vis = max(1, (H-y0-36)//ih)
    start = max(0, sel - vis//2)
    for i, item in enumerate(items[start:start+vis], start):
        r = pygame.Rect(16, y0+(i-start)*ih, W-32, ih-2)
        pygame.draw.rect(screen, C['sel'] if i==sel else C['panel'], r, border_radius=5)
        screen.blit(F['n'].render(str(item)[:72], True, (255,255,255) if i==sel else C['text']),
                    (r.x+10, r.y+6))

def draw_hints(hints):
    y = H-30; pygame.draw.line(screen, C['border'], (0,y-4),(W,y-4),1); x=16
    for btn, desc in hints:
        t = F['xs'].render(f"[{btn}] {desc}", True, C['hint'])
        screen.blit(t, (x,y)); x += t.get_width()+20

# ── Lógica de input — igual que updater.py ───────────────────────────────────
clock = pygame.time.Clock()

def get_input():
    """Lee teclado y mando. Devuelve (dy, confirm, cancel)."""
    dy=0; confirm=False; cancel=False
    for ev in pygame.event.get():
        if ev.type == pygame.QUIT:
            cancel = True
        elif ev.type == pygame.KEYDOWN:
            if   ev.key in (pygame.K_UP, pygame.K_LEFT):      dy = -1
            elif ev.key in (pygame.K_DOWN, pygame.K_RIGHT):   dy =  1
            elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER, pygame.K_SPACE): confirm = True
            elif ev.key in (pygame.K_ESCAPE, pygame.K_BACKSPACE): cancel = True
        elif ev.type == pygame.JOYBUTTONDOWN:
            if   ev.button == 0: confirm = True   # A
            elif ev.button == 1: cancel  = True   # B
        elif ev.type == pygame.JOYHATMOTION:
            if   ev.value[1] ==  1: dy = -1       # D-pad arriba
            elif ev.value[1] == -1: dy =  1       # D-pad abajo
        elif ev.type == pygame.JOYAXISMOTION and ev.axis == 1:
            if   ev.value < -0.5: dy = -1
            elif ev.value >  0.5: dy =  1
    return dy, confirm, cancel

# ── Pantalla 1: Modo ──────────────────────────────────────────────────────────
def screen_modo():
    sel = 0
    items = [("🔍  Modo Automático", "Detección automática del ejecutable"),
             ("🖊  Modo Manual",      "Eliges tú el ejecutable y el runner")]
    while True:
        dy, confirm, cancel = get_input()
        if dy:      sel = (sel + dy) % len(items)
        if confirm: return sel
        if cancel:  return None
        screen.fill(C['bg'])
        draw_header("DeckStation Pro — Configuración",
                    "No se encontró configuración. ¿Cómo quieres proceder?")
        bh = F['h'].get_height() + F['s'].get_height() + 26
        bw = min(W-60, 620); y0 = H//2 - (len(items)*(bh+14))//2
        for i,(label,desc) in enumerate(items):
            r = pygame.Rect(W//2-bw//2, y0+i*(bh+14), bw, bh)
            pygame.draw.rect(screen, C['sel'] if i==sel else C['panel'], r, border_radius=8)
            pygame.draw.rect(screen, C['border'], r, 1, border_radius=8)
            screen.blit(F['h'].render(label,True,(255,255,255) if i==sel else C['text']),(r.x+14,r.y+10))
            screen.blit(F['s'].render(desc, True,(200,200,200) if i==sel else C['dim']), (r.x+14,r.y+10+F['h'].get_height()+4))
        draw_hints([("↑↓","Mover"),("Enter/A","Confirmar"),("Esc/B","Cancelar")])
        pygame.display.flip(); clock.tick(60)

# ── Pantalla 2: Ficheros ──────────────────────────────────────────────────────
def screen_browser():
    current = WORK_DIR; sel = 0
    def items_de(path):
        out = []
        try:
            for n in sorted(os.listdir(path)):
                f = os.path.join(path, n)
                if os.path.isdir(f):              out.append(('📁 '+n, f, 'dir'))
                elif n.lower().endswith('.exe'):  out.append(('⚙  '+n, f, 'exe'))
        except Exception: pass
        return out
    while True:
        items = items_de(current)
        dy, confirm, cancel = get_input()
        if dy and items: sel = max(0, min(sel+dy, len(items)-1))
        if confirm and items:
            _, full, kind = items[sel]
            if kind == 'dir': current = full; sel = 0
            else: return full
        if cancel:
            p = os.path.dirname(current)
            if os.path.realpath(p).startswith(WORK_DIR) and p != current: current=p; sel=0
            else: return None
        screen.fill(C['bg'])
        draw_header("Elegir ejecutable", os.path.relpath(current, os.path.dirname(WORK_DIR)))
        if not items: screen.blit(F['n'].render("(carpeta vacía)",True,C['dim']),(20,90))
        else: draw_list([i[0] for i in items], sel)
        draw_hints([("↑↓","Mover"),("Enter/A","Entrar/Seleccionar"),("Esc/B","Subir")])
        pygame.display.flip(); clock.tick(60)

# ── Pantalla 3: Runner ────────────────────────────────────────────────────────
def screen_runner():
    runners = []
    if os.path.isdir(RUNNERS_DIR):
        for n in sorted(os.listdir(RUNNERS_DIR)):
            if os.path.isdir(os.path.join(RUNNERS_DIR, n)): runners.append(n)
    if not runners: runners = ["WINE_LG_11-1"]
    sel = 0
    while True:
        dy, confirm, cancel = get_input()
        if dy:      sel = max(0, min(sel+dy, len(runners)-1))
        if confirm: return runners[sel]
        if cancel:  return None
        screen.fill(C['bg'])
        draw_header("Elegir runner de Wine / Proton", RUNNERS_DIR)
        draw_list(runners, sel)
        draw_hints([("↑↓","Mover"),("Enter/A","Confirmar"),("Esc/B","Volver")])
        pygame.display.flip(); clock.tick(60)

# ── Main ──────────────────────────────────────────────────────────────────────
try:
    modo = screen_modo()
    if modo != 1:
        pygame.quit(); auto()

    exe = screen_browser()
    if not exe:
        pygame.quit(); auto()

    runner = screen_runner()
    if not runner:
        pygame.quit(); auto()

    pygame.quit()
    write_result(f"RESULT:MANUAL\n{exe}\n{runner}\n")
except Exception as e:
    import traceback
    traceback.print_exc(file=sys.stderr)
    try: pygame.quit()
    except Exception: pass
    auto()
