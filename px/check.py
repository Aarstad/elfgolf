# check.py -- decode px's escape stream back into pixels and compare them,
# frame by frame, against an independent model of the same plasma.
#   python3 check.py [FRAMES] [PNG]   -- PNG gets the last frame, upscaled
import re, subprocess, sys, struct, zlib
N = int(sys.argv[1]) if len(sys.argv) > 1 else 4
W, R = 80, 24; H = 2 * R

S, s, c = [], 0, 120 << 16           # Minsky, exactly as px does it
for _ in range(256):
    S.append(s >> 16); s += (c * 1608) >> 16; c -= (s * 1608) >> 16
assert all(-128 <= v <= 127 for v in S)
def asr(v, k): return v >> k         # python's >> on ints is arithmetic

def model(t):
    cx = asr(W + asr(S[(2 * t) & 255] * W, 8), 1)
    cy = asr(H + asr(S[(3 * t + 64) & 255] * H, 8), 1)
    px = []
    for y in range(H):
        ry = S[(3 * t + 4 * y) & 255]; dy2 = (y - cy) ** 2
        for x in range(W):
            v = (S[(3 * x + t) & 255] + ry + S[(2 * (x + y - t)) & 255]
                 + S[((((x - cx) ** 2 + dy2) >> 4) - 4 * t) & 255] + t)
            px.append(tuple(128 + S[(v + k) & 255] for k in (0, 85, 170)))
    return px

out = subprocess.run(['./px', str(N)], capture_output=True).stdout
frames = out.split(b'\033[H')[1:]
assert len(frames) == N, len(frames)
cell = re.compile(rb'\033\[38;2;(\d+);(\d+);(\d+);48;2;(\d+);(\d+);(\d+)m\xe2\x96\x80')
for t, f in enumerate(frames):
    rows = f.split(b'\r\n')
    assert len(rows) == R, (t, len(rows))
    got = [None] * (W * H)
    for r, line in enumerate(rows):
        cells = cell.findall(line)
        assert b''.join(m.group(0) for m in cell.finditer(line)) == line.replace(b'\033[0m\033[?25h\033[?1049l', b''), (t, r)
        assert len(cells) == W, (t, r, len(cells))
        for x, m in enumerate(cells):
            v = tuple(map(int, m))
            got[2 * r * W + x], got[(2 * r + 1) * W + x] = v[:3], v[3:]
    want = model(t)
    bad = [i for i in range(W * H) if got[i] != want[i]]
    assert not bad, (t, len(bad), bad[:3], [got[i] for i in bad[:3]], [want[i] for i in bad[:3]])
print(f'{N} frames, {W}x{H} pixels each, all match the model; {len(out)} bytes')

if len(sys.argv) > 2:                 # last frame as a PNG, 6x, no PIL needed
    k = 6
    raw = b''.join(b'\0' + b''.join(bytes(got[y * W + x]) * k for x in range(W))
                   for y in range(H) for _ in range(k))
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n'
        + ch(b'IHDR', struct.pack('>IIBBBBB', W * k, H * k, 8, 2, 0, 0, 0))
        + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))
