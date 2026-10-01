# life_check.py -- run life with a fixed seed, play its escape stream through a
# small terminal emulator, and hold the screen after every frame against an
# independent model of the board. Then report what the delta saved.
#   python3 life_check.py [FRAMES] [SEED]
import re, subprocess, sys
N = int(sys.argv[1]) if len(sys.argv) > 1 else 200
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 12345
W, R = 80, 24; H = 2 * R; M = (1 << 64) - 1
DEAD, RAIN, PATCH = (0x0a, 0x0c, 0x14), 31, 12

S, s, c = [], 0, 120 << 16
for _ in range(256):
    S.append(s >> 16); s += (c * 1608) >> 16; c -= (s * 1608) >> 16
rng = SEED or 1
def xs():
    global rng
    rng ^= rng >> 12; rng ^= (rng << 25) & M; rng ^= rng >> 27
    return rng
def hue(g): return tuple(128 + S[(g + k) & 255] for k in (0, 85, 170))

full = []                           # what each frame would cost sent whole
def enc(p): return len('2;%d;%d;%d;' % p)
def cost(col):
    n = 3 + 2 * (R - 1); f = b = None   # colours carry across row breaks
    for r in range(R):
        for x in range(W):
            u, d = col[2 * r * W + x], col[(2 * r + 1) * W + x]
            if u == d:                  # one colour: a space, background only
                n += 1 + (d != b) * (2 + 3 + enc(d)); b = d; continue
            k = (u != f) * (3 + enc(u)) + (d != b) * (3 + enc(d))
            n += 3 + (k and k + 2); f, b = u, d
    return n

def frames():                        # the model: (board colours) per frame
    global rng
    for g in range(N):
        born = hue(g)
        if g == 0:
            alive = [xs() >> 62 == 0 for _ in range(W * H)]
            col = [born if a else DEAD for a in alive]
        else:
            nxt = []
            for y in range(H):
                for x in range(W):
                    n = sum(alive[((y + dy) % H) * W + (x + dx) % W]
                            for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
                    a = alive[y * W + x]; b = n == 3 or (a and n == 2)
                    if b != a: col[y * W + x] = born if b else DEAD
                    nxt.append(b)
            alive = nxt
        if g & RAIN == 0:
            x0 = xs() % W; y0 = xs() % H
            for dy in range(PATCH):
                for dx in range(PATCH):
                    if xs() >> 63:
                        i = ((y0 + dy) % H) * W + (x0 + dx) % W
                        if not alive[i]: alive[i] = True; col[i] = born
        full.append(cost(col))
        yield list(col)

out = subprocess.run(['./life', str(N), str(SEED)], capture_output=True).stdout
tok = re.compile(rb'\033\[\?(?:1049[hl]|25[hl])|\033\[2J|\033\[H|\033\[(\d+)C'
                 rb'|\033\[([\d;]*)m|\xe2\x96\x80| |\r|\n')
screen = [[None] * W for _ in range(R)]
fg = bg = None; row = colm = 0; frame = 0; sizes = []; mark = 0
model = frames()
def settle():                        # a frame is done: compare, then count
    global frame, mark
    want = next(model)
    for r in range(R):
        for x in range(W):
            got = screen[r][x]
            exp = (want[2 * r * W + x], want[(2 * r + 1) * W + x])
            assert got == exp, (frame, r, x, got, exp)
    frame += 1
pos = 0; starts = []
for m in tok.finditer(out):
    assert m.start() == pos, ('stray bytes', out[pos:m.start()][:40]); pos = m.end()
    t = m.group(0)
    if t == b'\033[H':
        if starts: settle()
        starts.append(m.start()); row = colm = 0
    elif t == b'\033[2J': screen = [[None] * W for _ in range(R)]
    elif m.group(1): colm = min(colm + int(m.group(1)), W - 1)
    elif m.group(2) is not None:
        p = list(map(int, m.group(2).split(b';'))) if m.group(2) else [0]
        while p:
            if p[0] in (38, 48):
                v = tuple(p[2:5]); assert p[1] == 2
                if p[0] == 38: fg = v
                else: bg = v
                p = p[5:]
            else: p = p[1:]
    elif t == '▀'.encode():
        assert colm < W and row < R; screen[row][colm] = (fg, bg); colm += 1
    elif t == b' ':
        assert colm < W and row < R; screen[row][colm] = (bg, bg); colm += 1
    elif t == b'\r': colm = 0
    elif t == b'\n': row += 1
assert pos == len(out)
settle()
assert frame == N, frame
starts.append(len(out) - len(b'\033[0m\033[?25h\033[?1049l'))
sz = [b - a for a, b in zip(starts, starts[1:])]
print(f'{N} frames, seed {SEED}, {W}x{H} board: every frame matches the model')
assert sz[0] == full[0], (sz[0], full[0])
print(f'sent whole, later frames would mean {sum(full[1:]) / (N - 1):.0f} bytes: '
      f'the delta sends {sum(sz[1:]) / sum(full[1:]):.1%} of that')
print(f'first frame {sz[0]} bytes; later frames mean {sum(sz[1:]) / (N - 1):.0f}, '
      f'max {max(sz[1:])}, min {min(sz[1:])} bytes')
