#!/usr/bin/env python3
"""Regenerate the 33x33 Showdown arena in godot/scripts/arena.gd.

The map is a Brawl Stars Showdown map rescaled to Noble Stars' range cap:
theirs is 60x60 tiles against a 10-tile max weapon range, ours is 5.5, so
60 * 0.55 ~= 33. Terrain is authored in one quadrant and rotated four ways,
which makes the draw identical from every spawn; the clump angles are chiral
rather than mirrored so it reads as a pinwheel, not a kaleidoscope.

Densities aim at what real Showdown maps measure: ~20% wall, ~15% bush,
~7% water, 17 power cubes for 10 fighters (Brawl Stars ships 16-20).

  python3 Tools/gen_showdown_map.py            # print the map and its stats
  python3 Tools/gen_showdown_map.py --png x.png  # also render a preview image
  python3 Tools/gen_showdown_map.py --write    # paste it into arena.gd

Every generated map is checked before it is emitted: one connected walkable
region, no tile pinched between walls on both axes, exactly 10 spawns, and no
loot placed off the field.
"""
import sys, os
import math, zlib, struct
from collections import deque, Counter

COL = {'.': (243,170,120), ',': (232,158,110), '#': (150,84,48), 'b': (74,150,74),
       '~': (52,150,220), 'X': (240,190,60), 'S': (225,225,235)}


def render(path, out, px=14):
    rows = [r for r in open(path).read().split('\n') if r]
    h, w = len(rows), len(rows[0])
    W, H = w*px, h*px
    buf = bytearray()
    for y in range(H):
        buf.append(0)
        for x in range(W):
            ch = rows[y//px][x//px]
            c = COL[ch]
            if ch == '.' and ((x//px + y//px) % 2): c = COL[',']
            # inset markers so they read as objects, not floor
            if ch in 'XS':
                ix, iy = x % px, y % px
                if not (3 <= ix < px-3 and 3 <= iy < px-3): c = COL[',']
            if ch == '#':
                ix, iy = x % px, y % px
                if ix == 0 or iy == 0: c = (120,66,38)
            buf += bytes(c)
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(bytes(buf), 9)) + chunk(b'IEND', b'')
    open(out, 'wb').write(png)
    print('wrote', out, W, 'x', H)


N, C = 33, 16
def rot(x, y): return (N - 1 - y, x)
grid = [['.'] * N for _ in range(N)]
def put(x, y, ch):
    if 1 <= x < N-1 and 1 <= y < N-1: grid[y][x] = ch     # never touch the border
def get(x, y): return grid[y][x]
def sym_put(x, y, ch):
    p = (x, y)
    for _ in range(4):
        put(p[0], p[1], ch); p = rot(*p)
def pol(x, y):
    dx, dy = x - C, y - C
    return math.hypot(dx, dy), math.degrees(math.atan2(dy, dx)) % 90.0
def at(r, a): return (int(round(C + r*math.cos(math.radians(a)))),
                      int(round(C + r*math.sin(math.radians(a)))))
def clump(r, a, w, h, ch):
    x0, y0 = at(r, a)
    for dy in range(h):
        for dx in range(w):
            sym_put(x0 + dx - w//2, y0 + dy - h//2, ch)
def arc(r0, r1, spans, ch):
    for y in range(N):
        for x in range(N):
            r, a = pol(x, y)
            if r0 <= r <= r1 and any(lo <= a <= hi for lo, hi in spans):
                if get(x, y) == '.': put(x, y, ch)

for i in range(N):
    grid[0][i] = grid[N-1][i] = '#'
    grid[i][0] = grid[i][N-1] = '#'

# --- concentric cover, gaps deliberately offset ring to ring -------------
arc(6.8,  8.6, [(10, 78)],           'b')   # inner ring, open at the four cardinals
arc(11.8, 13.3, [(0, 38), (58, 90)], 'b')   # outer ring, open on the four diagonals
arc(17.8, 19.2, [(26, 64)],          'b')   # corner thickets
arc(9.6,  11.2, [(0, 12), (78, 90)], '~')   # ponds sitting in the cardinal lanes
arc(15.2, 16.6, [(38, 52)],          '~')   # corner pools

# --- wall clumps on chiral angles: rotational symmetry, no mirror --------
# A wall tile is 2 m against a 1.10 m fighter, so one tile of cover is already
# 1.8 body-widths — where Brawl Stars' cover block is exactly one. Chunky blocks
# would break sightlines far more coarsely than theirs, so most of the cover is
# singles and pairs and only a few clumps are 2x2 or bigger.
for r, a, w, h in [(5.8, 15, 2, 2), (5.8, 63, 2, 2), (9.7, 34, 2, 3),
                   (10.6, 81, 2, 2), (13.2,  7, 2, 2), (14.2, 52, 2, 2),
                   (16.4, 27, 2, 2), (18.2, 68, 2, 2),
                   (17.6, 12, 1, 2), (12.0, 60, 1, 1), (7.6, 78, 1, 1),
                   (11.0, 24, 1, 2), (15.0, 45, 2, 1), (19.0, 33, 1, 1),
                   (8.6,  5, 1, 1), (12.6, 84, 1, 1), (16.0, 58, 2, 1),
                   (20.0, 50, 1, 2)]:
    clump(r, a, w, h, '#')

# --- centre keep --------------------------------------------------------
for dy in range(-3, 4):
    for dx in range(-3, 4):
        cheb, x, y = max(abs(dx), abs(dy)), C+dx, C+dy
        if cheb == 3:
            gate = (abs(dx) <= 1 and abs(dy) == 3) or (abs(dy) <= 1 and abs(dx) == 3)
            put(x, y, '.' if gate else '#')
        elif cheb == 2: put(x, y, 'X' if abs(dx) == 2 and abs(dy) == 2 else '.')
        elif cheb == 1: put(x, y, '~' if abs(dx) == 1 and abs(dy) == 1 else '.')
        else:           put(x, y, 'X')

# --- loot: 5 in the keep, 12 on the field --------------------------------
for r, a in [(7.7, 44), (12.4, 22), (15.0, 62)]:
    bx, by = at(r, a)
    assert 1 <= bx < N-1 and 1 <= by < N-1, ('loot off-field', r, a, bx, by)
    sym_put(bx, by, 'X')

# --- connectivity --------------------------------------------------------
def walkable(ch): return ch not in '#~'
def regions():
    seen, out = set(), []
    for y in range(N):
        for x in range(N):
            if walkable(get(x, y)) and (x, y) not in seen:
                q, comp = deque([(x, y)]), []; seen.add((x, y))
                while q:
                    cx, cy = q.popleft(); comp.append((cx, cy))
                    for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                        n = (cx+dx, cy+dy)
                        if 0 <= n[0] < N and 0 <= n[1] < N and n not in seen and walkable(get(*n)):
                            seen.add(n); q.append(n)
                out.append(comp)
    return sorted(out, key=len, reverse=True)
carves = 0
for _ in range(80):
    comps = regions()
    if len(comps) == 1: break
    main, pocket = set(comps[0]), comps[1]
    prev, q, hit = {}, deque(), None
    for p in pocket:
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (p[0]+dx, p[1]+dy)
            if 1 <= n[0] < N-1 and 1 <= n[1] < N-1 and not walkable(get(*n)) and n not in prev:
                prev[n] = None; q.append(n)
    while q and hit is None:
        cur = q.popleft()
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (cur[0]+dx, cur[1]+dy)
            if not (1 <= n[0] < N-1 and 1 <= n[1] < N-1): continue
            if n in main: hit = cur; break
            if not walkable(get(*n)) and n not in prev: prev[n] = cur; q.append(n)
    if hit is None: break
    node = hit
    while node is not None:
        sym_put(node[0], node[1], '.'); carves += 1; node = prev[node]

# --- open dead ends ------------------------------------------------------
# Showdown is a cornering game, so a one-way alcove is a death sentence rather
# than a hiding place. Every cul-de-sac and every pocket sealed behind a single
# tile gets a second exit knocked through, symmetrically so the four quadrants
# stay identical.
def degree(x, y):
    return sum(1 for n in ((x+1,y),(x-1,y),(x,y+1),(x,y-1))
               if 0 <= n[0] < N and 0 <= n[1] < N and walkable(get(*n)))

def room_around(x, y, k=2):
    return sum(1 for dy in range(-k, k+1) for dx in range(-k, k+1)
               if 0 <= x+dx < N and 0 <= y+dy < N and walkable(get(x+dx, y+dy)))

def breach(x, y):
    """Knock out whichever blocking neighbour opens onto the most space."""
    best = None
    for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
        n = (x+dx, y+dy)
        if not (1 <= n[0] < N-1 and 1 <= n[1] < N-1) or walkable(get(*n)):
            continue
        r = room_around(*n)
        if best is None or r > best[0]:
            best = (r, n)
    if best:
        sym_put(best[1][0], best[1][1], '.')
        return True
    return False

def pockets(limit=8):
    """Groups of at most `limit` tiles reachable only through one tile."""
    cells = [(x, y) for y in range(N) for x in range(N) if walkable(get(x, y))]
    out = []
    for t in cells:
        if degree(*t) < 2:
            continue
        seen, parts = {t}, []
        for s in cells:
            if s in seen: continue
            q, comp = deque([s]), []
            seen.add(s)
            while q:
                c = q.popleft(); comp.append(c)
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (c[0]+dx, c[1]+dy)
                    if n not in seen and 0 <= n[0] < N and 0 <= n[1] < N and walkable(get(*n)):
                        seen.add(n); q.append(n)
            parts.append(comp)
        if len(parts) < 2:
            continue
        for pk in sorted(parts, key=len)[:-1]:
            if len(pk) <= limit:
                out.append((t, pk))
    return out

breaches = 0
for _ in range(40):
    tips = [(x, y) for y in range(1, N-1) for x in range(1, N-1)
            if walkable(get(x, y)) and degree(x, y) <= 1]
    if tips:
        for x, y in tips:
            if breach(x, y): breaches += 1
        continue
    pk = pockets()
    if not pk: break
    _, group = pk[0]
    for x, y in sorted(group, key=lambda c: -room_around(*c)):
        if breach(x, y): breaches += 1; break
    else:
        break


# --- spawns: ten evenly round the ring, snapped to open ground -----------
RING = [(8,2),(16,2),(24,2),(30,10),(30,22),(24,30),(16,30),(8,30),(2,22),(2,10)]
placed = []
for sx, sy in RING:
    best = None
    for ry in range(1, N-1):
        for rx in range(1, N-1):
            if get(rx, ry) not in '.b': continue
            room = sum(1 for dy in range(-2, 3) for dx in range(-2, 3)
                       if 0 <= rx+dx < N and 0 <= ry+dy < N and walkable(get(rx+dx, ry+dy)))
            if room < 16: continue
            if any((rx-px)**2 + (ry-py)**2 < 36 for px, py in placed): continue
            d2 = (rx-sx)**2 + (ry-sy)**2
            if best is None or d2 < best[0]: best = (d2, rx, ry)
    put(best[1], best[2], 'S'); placed.append((best[1], best[2]))

# --- report --------------------------------------------------------------
cnt = Counter(''.join(''.join(r) for r in grid)); tot = N*N
inner = [grid[y][x] for y in range(1, N-1) for x in range(1, N-1)]
ic, itot = Counter(inner), len(inner)
print('\n'.join(''.join(r) for r in grid)); print()
print("size %dx%d  carves %d  breaches %d  components %d"
      % (N, N, carves, breaches, len(regions())))
for k, name in [('#','wall'), ('b','bush'), ('~','water'), ('X','box'), ('S','spawn'), ('.','floor')]:
    print("  %-5s %s  interior %4d %5.1f%%" % (name, k, ic[k], 100*ic[k]/itot))
print("  interior non-floor %.1f%%   interior blocking %.1f%%"
      % (100*(ic['#']+ic['b']+ic['~'])/itot, 100*(ic['#']+ic['~'])/itot))
pinch = [(x,y) for y in range(1,N-1) for x in range(1,N-1)
         if walkable(get(x,y)) and get(x-1,y)=='#' and get(x+1,y)=='#'
         and get(x,y-1)=='#' and get(x,y+1)=='#']
print("  one-tile pinches:", len(pinch), " spawns:", ic['S'], " boxes:", ic['X'])
dead = [(x, y) for y in range(1, N-1) for x in range(1, N-1)
        if walkable(get(x, y)) and degree(x, y) <= 1]
print("  dead ends:", len(dead), " single-tile-throat pockets:", len(pockets()))
assert not dead and not pockets(), "map still has cul-de-sacs"
assert len(regions()) == 1 and not pinch and ic['S'] == 10
print("  4-fold symmetric:", all(get(x,y)==get(*rot(x,y)) for y in range(N) for x in range(N)
      if get(x,y)!='S' and get(*rot(x,y))!='S'))



ASCII = '\n'.join(''.join(r) for r in grid)

if '--png' in sys.argv:
    out = sys.argv[sys.argv.index('--png') + 1]
    tmp = out + '.txt'
    open(tmp, 'w').write(ASCII)
    render(tmp, out)
    os.remove(tmp)

if '--write' in sys.argv:
    import re
    path = os.path.join(os.path.dirname(__file__), '..', 'godot', 'scripts', 'arena.gd')
    src = open(path).read()
    old = re.search(r'const MAP := """\n.*?"""', src, re.S).group(0)
    open(path, 'w').write(src.replace(old, 'const MAP := """\n%s\n"""' % ASCII))
    print('wrote', os.path.normpath(path))
