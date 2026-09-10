#!/usr/bin/env python3
"""Procedural chibi sprite sheets in the Hermes/petdex atlas contract
(192×208 cells, 8 columns, 9 Codex rows, 6 frames). Drawn at 48×52 with
pycairo (no antialiasing) and upscaled ×4 nearest-neighbour for a pixel look.

  generate.py [outdir]      -> hanna/spritesheet.png + pet.json, and
                               hanna-jacket/spritesheet.png (outfit layer, transparent body)
Model: Hanna — short black hair with a red streak, green eyes, dark skin,
coral crop top, black leggings with a red side stripe, white shoes; jacket =
black track jacket with red trim (separate layer)."""
import json, math, os, sys
import cairo

W, H, SCALE = 48, 52, 4
COLS, FRAMES = 8, 6
ROWS = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"]
SKIN, SKIN_D = (0.72, 0.47, 0.30), (0.55, 0.34, 0.20)
HAIR, STREAK = (0.10, 0.09, 0.11), (0.95, 0.25, 0.25)
EYE, WHITE = (0.20, 0.80, 0.55), (0.98, 0.98, 0.98)
TOP, TOP_D = (0.98, 0.45, 0.45), (0.15, 0.13, 0.15)
LEG, STRIPE, SHOE = (0.12, 0.11, 0.13), (0.95, 0.30, 0.30), (0.96, 0.96, 0.96)
JACKET, TRIM, ZIP = (0.18, 0.17, 0.20), (0.95, 0.30, 0.30), (0.75, 0.75, 0.78)


def rect(cr, x, y, w, h, c):
    cr.set_source_rgb(*c); cr.rectangle(round(x), round(y), round(w), round(h)); cr.fill()


def disc(cr, x, y, r, c):
    cr.set_source_rgb(*c); cr.arc(x, y, r, 0, 2 * math.pi); cr.fill()


def pose(state, f):
    """-> dict of pose parameters for state/frame (0..5)."""
    t = f / FRAMES
    p = {"dy": 0, "lean": 0, "larm": 0, "rarm": 0, "lleg": 0, "rleg": 0, "blink": False, "mouth": "smile",
         "extra": None, "face": 1, "crouch": 0, "headdown": 0, "hand_chin": False, "hand_head": False}
    if state == "idle":
        p["dy"] = round(math.sin(t * 2 * math.pi)) ; p["blink"] = f == 4
    elif state in ("running-right", "running", "running-left"):
        p["lean"] = 2; p["lleg"] = round(4 * math.sin(t * 2 * math.pi)); p["rleg"] = -p["lleg"]
        p["larm"] = -p["lleg"] * 6; p["rarm"] = p["lleg"] * 6; p["dy"] = -abs(round(2 * math.sin(t * 2 * math.pi)))
        if state == "running-left": p["face"] = -1
    elif state == "waving":
        p["rarm"] = 150 + round(25 * math.sin(t * 2 * math.pi)); p["mouth"] = "open"
    elif state == "jumping":
        seq = [2, 0, -7, -10, -7, 0]; p["dy"] = seq[f]; p["crouch"] = 2 if f in (0, 5) else 0
        p["larm"] = p["rarm"] = 160 if f in (2, 3, 4) else 20; p["mouth"] = "open"
    elif state == "failed":
        p["headdown"] = 3; p["dy"] = 2; p["mouth"] = "sad"; p["larm"] = p["rarm"] = -10
        p["extra"] = "sweat" if f % 2 == 0 else None; p["blink"] = f in (2, 3)
    elif state == "waiting":
        p["rleg"] = -2 if f % 2 == 0 else 0; p["larm"] = 90; p["mouth"] = "flat"; p["blink"] = f == 3
        p["extra"] = "dots" if f < 3 else None
    elif state == "review":
        p["hand_chin"] = True; p["mouth"] = "flat"; p["extra"] = ["q1", "q2", "q3", None, None, None][f]
    return p


def draw_arm(cr, sx, sy, angle, face, length=9, c=SKIN, w=3):
    """Arm from shoulder (sx,sy); angle 0 = hanging down, 180 = straight up; positive swings forward."""
    a = math.radians(angle) * face
    ex, ey = sx + math.sin(a) * length, sy + math.cos(math.radians(angle)) * length
    cr.set_source_rgb(*c); cr.set_line_width(w); cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.move_to(sx, sy); cr.line_to(ex, ey); cr.stroke()
    return ex, ey


def draw_sleeve(cr, sx, sy, angle, face, length=8):
    """Jacket sleeve: black to just short of the hand, red cuff at the wrist end."""
    ex, ey = draw_arm(cr, sx, sy, angle, face, length=length, c=JACKET, w=4)
    a = math.radians(angle) * face
    cx_, cy_ = sx + math.sin(a) * (length - 2), sy + math.cos(math.radians(angle)) * (length - 2)
    cr.set_source_rgb(*TRIM); cr.set_line_width(4); cr.move_to(cx_, cy_); cr.line_to(ex, ey); cr.stroke()


def draw_body(cr, p, jacket_only=False):
    face = p["face"]; cx = 24 + p["lean"] * face; dy = p["dy"]; crouch = p["crouch"]
    top_y = 24 + dy + crouch
    hip_y = 33 + dy + crouch
    # legs + shoes (skipped on the jacket layer)
    if not jacket_only:
        for side, off in ((-1, p["lleg"]), (1, p["rleg"])):
            lx = cx + side * 3 - 1
            rect(cr, lx, hip_y, 3, 12 - crouch + (0 if off >= 0 else 0), LEG)
            rect(cr, lx + (2 if side * face > 0 else 0), hip_y, 1, 10 - crouch, STRIPE)
            rect(cr, lx - 1 + off // 2, hip_y + 12 - crouch, 5, 3, SHOE)
    # back arm
    bx, by = cx - 6 * face, top_y + 2
    back_arm = p["larm"] if face > 0 else p["rarm"]
    front_arm = p["rarm"] if face > 0 else p["larm"]
    if jacket_only: draw_sleeve(cr, bx, by, back_arm, -face)
    else: draw_arm(cr, bx, by, back_arm, -face, c=SKIN_D)
    # torso
    if jacket_only:
        rect(cr, cx - 7, top_y - 1, 14, 11, JACKET)                  # jacket body (open)
        rect(cr, cx - 2, top_y - 1, 4, 11, (0, 0, 0)); cr.set_operator(cairo.OPERATOR_CLEAR); cr.rectangle(cx - 2, top_y - 1, 4, 11); cr.fill(); cr.set_operator(cairo.OPERATOR_OVER)
        rect(cr, cx - 3, top_y - 1, 1, 11, TRIM); rect(cr, cx + 2, top_y - 1, 1, 11, TRIM)
        rect(cr, cx - 7, top_y - 2, 14, 2, TRIM)                      # collar
        rect(cr, cx - 7, top_y + 9, 14, 1, ZIP)
    else:
        rect(cr, cx - 6, top_y, 12, 6, TOP)                           # crop top
        rect(cr, cx - 6, top_y + 6, 12, 1, TOP_D)
        rect(cr, cx - 2, top_y, 4, 2, WHITE)
        rect(cr, cx - 6, top_y + 7, 12, 2, SKIN)                      # midriff
        rect(cr, cx - 5, hip_y, 10, 2, LEG)                           # waistband
        rect(cr, cx + 2 * face, top_y + 7, 2, 2, TOP_D)               # clover tattoo hint
    # head
    hx, hy = cx + face * 1, 14 + dy + crouch + p["headdown"]
    if not jacket_only:
        disc(cr, hx, hy, 8, SKIN)
        # hair: cap + fringe with red streak
        cr.set_source_rgb(*HAIR); cr.arc(hx, hy - 1, 8.5, math.pi, 2 * math.pi); cr.fill()
        rect(cr, hx - 8, hy - 2, 16, 3, HAIR)
        rect(cr, hx + (2 if face > 0 else -6), hy - 2, 4, 4, HAIR)
        rect(cr, hx + (5 if face > 0 else -8), hy - 4, 3, 8, STREAK)   # red streak
        rect(cr, hx - 8, hy - 1, 2, 5, HAIR)
        # eyes
        if p["blink"]:
            rect(cr, hx - 4, hy + 1, 3, 1, TOP_D); rect(cr, hx + 1, hy + 1, 3, 1, TOP_D)
        else:
            rect(cr, hx - 4, hy, 3, 3, WHITE); rect(cr, hx + 1, hy, 3, 3, WHITE)
            rect(cr, hx - 3 + (1 if face > 0 else 0), hy + 1, 2, 2, EYE); rect(cr, hx + 2 + (1 if face > 0 else 0), hy + 1, 2, 2, EYE)
        # mouth
        m = p["mouth"]
        if m == "smile": rect(cr, hx - 1, hy + 5, 3, 1, SKIN_D)
        elif m == "open": rect(cr, hx - 1, hy + 4, 3, 2, TOP_D)
        elif m == "sad": rect(cr, hx - 1, hy + 5, 3, 1, SKIN_D); rect(cr, hx - 2, hy + 4, 1, 1, SKIN_D); rect(cr, hx + 2, hy + 4, 1, 1, SKIN_D)
        else: rect(cr, hx - 1, hy + 5, 2, 1, SKIN_D)
    # front arm
    fx, fy = cx + 6 * face, top_y + 2
    if p["hand_chin"]:
        if jacket_only: draw_sleeve(cr, fx, fy, 120, face, length=7)
        else: ex, ey = draw_arm(cr, fx, fy, 120, face, length=8); disc(cr, ex, ey, 2, SKIN)
    else:
        if jacket_only: draw_sleeve(cr, fx, fy, front_arm, face)
        else: ex, ey = draw_arm(cr, fx, fy, front_arm, face); disc(cr, ex, ey, 2, SKIN)
    # extras (body sheet only)
    if not jacket_only and p["extra"]:
        e = p["extra"]
        if e == "sweat": rect(cr, hx + 9, hy - 2, 2, 3, (0.4, 0.7, 1.0))
        elif e == "dots": [rect(cr, hx + 10 + i * 3, hy - 6, 2, 2, WHITE) for i in range(3)]
        elif e.startswith("q"):
            n = int(e[1]); rect(cr, hx + 9, hy - 8 - n, 2, 5, WHITE); rect(cr, hx + 9, hy - 1 - n, 2, 1, WHITE)


def render(outdir, jacket_only):
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W * COLS, H * len(ROWS))
    cr = cairo.Context(surf); cr.set_antialias(cairo.ANTIALIAS_NONE)
    for r, state in enumerate(ROWS):
        for f in range(FRAMES):
            cr.save(); cr.translate(f * W, r * H); cr.rectangle(0, 0, W, H); cr.clip()
            draw_body(cr, pose(state, f), jacket_only); cr.restore()
    small = os.path.join(outdir, "_small.png"); surf.write_to_png(small)
    os.system(f"magick '{small}' -filter point -resize {SCALE * 100}% '{os.path.join(outdir, 'spritesheet.png')}' && rm -f '{small}'")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    base = out; jacket = os.path.join(os.path.dirname(out), "hanna-jacket")
    os.makedirs(jacket, exist_ok=True)
    render(base, False); render(jacket, True)
    json.dump({"id": "hanna", "displayName": "Hanna", "description": "Procedural chibi Hanna: short black hair with a red streak, green eyes, coral crop top, black leggings. Generated by generate.py.", "spritesheetPath": "spritesheet.png", "createdBy": "generate.py"}, open(os.path.join(base, "pet.json"), "w"), indent=2)
    json.dump({"id": "hanna-jacket", "displayName": "Hanna — track jacket", "description": "Outfit layer for hanna: black track jacket with red trim, transparent body. Same atlas, drawn in lock-step.", "spritesheetPath": "spritesheet.png", "layer": True, "createdBy": "generate.py"}, open(os.path.join(jacket, "pet.json"), "w"), indent=2)
    print("wrote", base, jacket)


if __name__ == "__main__":
    main()
