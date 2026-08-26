# -*- coding: utf-8 -*-
"""生成键盘模式用的键盘贴图，以及配套的按键高光几何。

    py -3 tools/gen_keyboard.py            # 生成贴图 + 就地更新 KEY_SHAPES
    py -3 tools/gen_keyboard.py --dry-run  # 只看结果，不写任何文件

产出两样，二者必须同源，否则高光会跟画上去的键错位：
    assets/images/input_reaction/doro_keyboard.png     键盘贴图（612x354，带透明底）
    input_stage_v3.gd 里的 KEY_SHAPES           每个键帽的四角，高光照它描边

为什么要有这个脚本
------------------
上一版贴图是从 ayangweb/Awesome-BongoCat 拿来的图改色而成（桌面由 #90c5e6 刷成
#f6dce3，其余 92.57% 的像素原样），那个仓库没有任何许可证。docs/keyboard-research.md
当初就写过「如果公开发行，建议仅参考结构后重画」，这个脚本就是在还那笔账。

这里不做像素级复刻 —— 那样得到的还是人家那张图，一个问题都没解决。键盘的几何和
视角必须一致（键位映射依赖它，而且键盘本来就长那样，这不是谁的创作），线条、字形、
手绘抖动都是自己生成的。

怎么保证跟代码对得上
--------------------
键的位置不在这里定，而是从 input_stage_v3.gd 的 _add_key(...) 里读 —— 那是代码
认定的真值，读它就不存在「对不齐」的可能。本脚本只做两件事：
  1. 用字母数字四排（52 个键，列位置是标准 QWERTY，确定无疑）拟合一个投影变换，
     用来决定每个键帽的四边形形状和字母朝向。底排的修饰键不参与拟合 —— 那排的
     列位置只能靠猜，掺进去会把透视带歪（实测最大残差从 3.9px 恶化到 12.2px）。
  2. 按这个投影把键盘画出来，并把每个键帽的四角吐给 GDScript。

依赖：Python 3 + Pillow（pip install pillow）。字体只在生成时用来把字形画进图里，
不涉及分发字体本身。
"""
import argparse
import io
import math
import os
import random
import re
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('需要 Pillow：pip install pillow')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GD = os.path.join(ROOT, 'scripts', 'gd', 'interact', 'input_stage_v3.gd')
OUT_PNG = os.path.join(ROOT, 'assets', 'images', 'input_reaction', 'doro_keyboard.png')

# ---------------------------------------------------------------- 画面参数
W, H = 612, 354
SS = 4                              # 超采样倍数，缩回去才不毛边
C_PLATE = (255, 255, 255, 255)      # 底板
C_FRAME = (0x57, 0x66, 0x90, 255)   # 边框带 / 侧壁（同色，两色会看出「两层」）
C_KEY = (0xF6, 0xDC, 0xE3, 255)     # 键与键之间那圈粉
C_EDGE = (0x92, 0xC4, 0xE8, 255)    # 键帽边缘的淡蓝细线
C_TEXT = (0x92, 0xC4, 0xE8, 255)    # 键帽上的字

FRAME_W = 6.6                       # 边框带宽度
WALL_DROP = 5.0                     # 侧壁下移量，做出键盘厚度
PLATE_IN = 0.13                     # 底板内缩，补掉描边自身的宽度

KEY_FILL_W = 0.87                   # 键帽占一个键位的比例，空出来的缝由粉描边填满
KEY_FILL_H = 0.86
KEY_ROUND = 0.30
KEY_PINK_W = 4.3                    # 粗粉描边：宽到能填满相邻键之间的缝
KEY_EDGE_W = 1.3                    # 细淡蓝描边：压在同一条路径上
HALF_ROWS = 0.40                    # ↑ ↓ 是半高键（实测两者中心只差 0.46 行）
JITTER = 0.55                       # 描边的低频摆动幅度，手绘感来源
SEED = 20260825                     # 固定种子，每次跑出来一模一样

TEXT_1CH = 0.41                     # 单字符字号（相对一个键帽宽）
TEXT_NCH = 0.30                     # 多字符字号
ARROW_FIT = 0.62                    # 箭头长度占键帽在该方向上半径的比例

# 标点单独放大。
#
# 字号是按字母的视觉大小定的，可句点、逗号、引号这些字形本身只占字面框的一小块，
# 同样字号下渲染出来就剩两三个像素，缩到实际显示尺寸（约 0.49）几乎看不见 ——
# 句点在键帽上只有一个 2x2 的点。按字形实际占多大分别补偿。
PUNCT_BOOST = {
    '.': 1.8, ',': 1.8,
    "'": 1.6, '`': 1.6,
    ';': 1.5,
    '-': 1.3, '=': 1.25,
}

FONTS = [                           # 按顺序找第一个存在的
    r'C:\Windows\Fonts\NotoSans-Bold.ttf',
    r'C:\Windows\Fonts\arialbd.ttf',
    r'C:\Windows\Fonts\segoeuib.ttf',
]

# ---------------------------------------------------------------- 一次性量出来的常数
# 下面这些当初是从参考图上量的（底板范围取自它那圈深蓝框带，补画的键取自键帽连通域）。
# 量完就烘在这儿了 —— 生成器不再需要那张图，那张图才能删掉。
PLATE_COL = (-0.567, 15.364)
PLATE_ROW = (-1.306, 5.186)

# 贴图上画着、但代码不映射的键（按了没反应，只是不画就缺牙）。
# 网格位置对应标准 60% 布局：底排是 Ctrl / Fn / Win / Alt / Space / Alt / Ctrl。
EXTRA_KEYS = [
    ('Shift', 13.635, 3.002, 2.25),   # 右 Shift
    ('Ctrl', 11.455, 3.998, 0.75),    # 右 Ctrl
    ('Fn', 1.716, 4.011, 0.75),       # Fn，夹在左 Ctrl 和 Win 之间，笔记本排法
    ('Alt', 10.442, 4.007, 0.75),     # 右 Alt
]

# 各键宽度，单位是一个键帽宽
WIDE = {
    'Back': 2.0, 'Tab': 1.5, '\\\\': 1.5, 'Caps': 1.75, 'Enter': 2.25,
    'Shift': 2.25, 'Ctrl': 1.5, 'Win': 1.25, 'Alt': 1.25, 'Space': 6.25,
}
HALF_KEYS = {'\u2191', '\u2193'}
ARROW_DIR = {'\u2190': 180.0, '\u2192': 0.0, '\u2191': -90.0, '\u2193': 90.0}

# 拟合用的布局：只用字母数字四排，列位置是标准 QWERTY
FIT_ROWS = {
    0: [('`', 0.5), ('1', 1.5), ('2', 2.5), ('3', 3.5), ('4', 4.5), ('5', 5.5),
        ('6', 6.5), ('7', 7.5), ('8', 8.5), ('9', 9.5), ('0', 10.5), ('-', 11.5),
        ('=', 12.5), ('Back', 14.0)],
    1: [('Tab', 0.75), ('Q', 2.0), ('W', 3.0), ('E', 4.0), ('R', 5.0), ('T', 6.0),
        ('Y', 7.0), ('U', 8.0), ('I', 9.0), ('O', 10.0), ('P', 11.0), ('[', 12.0),
        (']', 13.0), ('\\\\', 14.25)],
    2: [('Caps', 0.875), ('A', 2.25), ('S', 3.25), ('D', 4.25), ('F', 5.25),
        ('G', 6.25), ('H', 7.25), ('J', 8.25), ('K', 9.25), ('L', 10.25),
        (';', 11.25), ("'", 12.25), ('Enter', 13.875)],
    3: [('Shift', 1.125), ('Z', 2.75), ('X', 3.75), ('C', 4.75), ('V', 5.75),
        ('B', 6.75), ('N', 7.75), ('M', 8.75), (',', 9.75), ('.', 10.75),
        ('/', 11.75)],
}


# ================================================================ 读键位
def read_keys(path):
    """从 input_stage_v3.gd 的 _add_key(...) 里读出键位 —— 那是唯一的真值来源。"""
    src = open(path, encoding='utf-8').read()
    pat = re.compile(
        r'_add_key\(\s*(0x[0-9A-Fa-f]+)\s*,\s*"([^"]*)"\s*,\s*'
        r'Vector2\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)\s*\)'
    )
    keys = [{'vk': int(m.group(1), 16), 'label': m.group(2),
             'x': float(m.group(3)), 'y': float(m.group(4))}
            for m in pat.finditer(src)]
    if not keys:
        sys.exit('在 %s 里没找到 _add_key(...)' % path)
    return keys


# ================================================================ 投影
def fit_projection(keys):
    """最小二乘解一个 8 参数投影变换：网格 (col, row) -> 贴图 (x, y)。"""
    by = {k['label']: (k['x'], k['y']) for k in keys}
    pairs = []
    for row, items in FIT_ROWS.items():
        for label, col in items:
            if label in by:
                x, y = by[label]
                pairs.append((col, float(row), x, y))
    A, B = [], []
    for c, r, x, y in pairs:
        A.append([c, r, 1, 0, 0, 0, -c * x, -r * x]); B.append(x)
        A.append([0, 0, 0, c, r, 1, -c * y, -r * y]); B.append(y)
    n = 8
    M = [[sum(A[k][i] * A[k][j] for k in range(len(A))) for j in range(n)]
         + [sum(A[k][i] * B[k] for k in range(len(A)))] for i in range(n)]
    for i in range(n):
        pv = max(range(i, n), key=lambda t: abs(M[t][i]))
        M[i], M[pv] = M[pv], M[i]
        dv = M[i][i]
        for j in range(i, n + 1):
            M[i][j] /= dv
        for t in range(n):
            if t != i and M[t][i]:
                fq = M[t][i]
                for j in range(i, n + 1):
                    M[t][j] -= fq * M[i][j]
    p = [M[i][n] for i in range(n)]
    errs = []
    a, b, cc, d, e, f, g, h = p
    for c, r, x, y in pairs:
        w = g * c + h * r + 1.0
        errs.append(math.hypot((a * c + b * r + cc) / w - x, (d * c + e * r + f) / w - y))
    return p, len(pairs), sum(errs) / len(errs), max(errs)


def make_transforms(p):
    a, b, cc, d, e, f, g, h = p

    def proj(col, row):
        w = g * col + h * row + 1.0
        return ((a * col + b * row + cc) / w, (d * col + e * row + f) / w)

    m = [[a, b, cc], [d, e, f], [g, h, 1.0]]
    (m00, m01, m02), (m10, m11, m12), (m20, m21, m22) = m
    det = (m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20)
           + m02 * (m10 * m21 - m11 * m20))
    inv = [[(m11 * m22 - m12 * m21) / det, (m02 * m21 - m01 * m22) / det, (m01 * m12 - m02 * m11) / det],
           [(m12 * m20 - m10 * m22) / det, (m00 * m22 - m02 * m20) / det, (m02 * m10 - m00 * m12) / det],
           [(m10 * m21 - m11 * m20) / det, (m01 * m20 - m00 * m21) / det, (m00 * m11 - m01 * m10) / det]]

    def unproj(x, y):
        u = inv[0][0] * x + inv[0][1] * y + inv[0][2]
        v = inv[1][0] * x + inv[1][1] * y + inv[1][2]
        w = inv[2][0] * x + inv[2][1] * y + inv[2][2]
        return (u / w, v / w)

    return proj, unproj


# ================================================================ 形状
def round_quad(quad, r=KEY_ROUND, steps=9):
    """给四边形切圆角，返回闭合折线。"""
    n = len(quad)
    out = []
    for i in range(n):
        p0, p1, p2 = quad[(i - 1) % n], quad[i], quad[(i + 1) % n]
        ax, ay = p1[0] + (p0[0] - p1[0]) * r, p1[1] + (p0[1] - p1[1]) * r
        bx, by = p1[0] + (p2[0] - p1[0]) * r, p1[1] + (p2[1] - p1[1]) * r
        for s in range(steps + 1):
            t = s / steps
            mt = 1 - t
            out.append((mt * mt * ax + 2 * mt * t * p1[0] + t * t * bx,
                        mt * mt * ay + 2 * mt * t * p1[1] + t * t * by))
    return out + [out[0]]


def jitter(poly, amp, rng):
    """沿法线加低频摆动。手绘的粗细不均是慢变化，不是逐点乱抖。"""
    if amp <= 0:
        return poly
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cy = sum(p[1] for p in poly) / n
    waves = [(rng.uniform(0.6, 1.0), rng.uniform(1.0, 3.0), rng.uniform(0, 6.283))
             for _ in range(3)]
    out = []
    for i, (x, y) in enumerate(poly):
        u = i / max(1, n - 1)
        off = sum(wv * math.sin(2 * math.pi * fr * u + ph) for wv, fr, ph in waves) / len(waves)
        dx, dy = x - cx, y - cy
        L = math.hypot(dx, dy) or 1.0
        out.append((x + dx / L * off * amp, y + dy / L * off * amp))
    out[-1] = out[0]
    return out


def load_font(px):
    for path in FONTS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, max(6, int(px)))
            except Exception:
                pass
    return ImageFont.load_default()


# ================================================================ 主流程
def build(keys, proj, unproj):
    rng = random.Random(SEED)

    def key_quad(cx, cy, units, rows):
        col, row = unproj(cx, cy)
        hw = units * KEY_FILL_W * 0.5
        hh = rows * 0.5
        return [proj(col - hw, row - hh), proj(col + hw, row - hh),
                proj(col + hw, row + hh), proj(col - hw, row + hh)]

    # 可按的键（位置来自代码）+ 只画不响应的键（网格位置烘在常数里）
    items = []
    for k in keys:
        items.append({
            'vk': k['vk'], 'label': k['label'], 'x': k['x'], 'y': k['y'],
            'units': WIDE.get(k['label'], 1.0),
            'rows': HALF_ROWS if k['label'] in HALF_KEYS else KEY_FILL_H,
            'live': True,
        })
    for label, col, row, units in EXTRA_KEYS:
        x, y = proj(col, row)
        items.append({'vk': None, 'label': label, 'x': x, 'y': y,
                      'units': units, 'rows': KEY_FILL_H, 'live': False})

    img = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    S = lambda pts: [(x * SS, y * SS) for x, y in pts]

    c0, c1 = PLATE_COL[0] + PLATE_IN, PLATE_COL[1] - PLATE_IN
    r0, r1 = PLATE_ROW[0] + PLATE_IN, PLATE_ROW[1] - PLATE_IN
    plate = round_quad([proj(c0, r0), proj(c1, r0), proj(c1, r1), proj(c0, r1)],
                       r=0.055, steps=15)

    # 侧壁跟边框带同色。用两个深浅不同的色会看出上下两条带，像底板有两层。
    wall = [(x, y + WALL_DROP) for x, y in plate]
    dr.polygon(S(wall), fill=C_FRAME)
    dr.line(S(wall), fill=C_FRAME, width=int(FRAME_W * SS), joint='curve')
    dr.polygon(S(plate), fill=C_PLATE)
    dr.line(S(jitter(plate, JITTER * 0.5, rng)), fill=C_FRAME,
            width=int(FRAME_W * SS), joint='curve')

    # 一个键只描一条路径：先粗粉（填满键之间的缝），再细淡蓝压在同一条路径上。
    # 画成两条大小不同的路径会变成「键里面套着一个键」。
    quads = {}
    for it in items:
        quad = key_quad(it['x'], it['y'], it['units'], it['rows'])
        quads[id(it)] = quad
        wobble = jitter(round_quad(quad), JITTER, rng)
        dr.line(S(wobble), fill=C_KEY, width=int(KEY_PINK_W * SS), joint='curve')
        dr.line(S(wobble), fill=C_EDGE, width=max(SS, int(KEY_EDGE_W * SS)), joint='curve')

    # 字单独一层，方便按各自的透视角度旋转
    lay = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)

    def step(p0, p1):
        """从 p0 指向 p1 的单位向量，以及这一步在屏幕上的长度。"""
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L = math.hypot(dx, dy) or 1.0
        return (dx / L, dy / L), L

    for it in items:
        lab, cx, cy = it['label'], it['x'], it['y']
        col, row = unproj(cx, cy)

        if lab in ARROW_DIR:
            # 箭头直接按网格方向投影，不走「临时图 + 整体旋转」那条路。
            #
            # 原来的画法是在临时图里指个方向再把整张图转 col 轴的角度，等于默认
            # 「上下 = col 轴转 90 度」。可这个投影是带切变的：col 轴和 row 轴在
            # 屏幕上夹约 138 度，不是 90 度。于是 ← → 正确（本就沿 col 轴），
            # ↑ ↓ 却歪了约 49 度，箭头尖顶出键帽。
            #
            # 键帽的上下边沿是沿 row 轴的，所以 ↑ ↓ 必须指 row 轴方向。
            if lab in ('←', '→'):
                u, per = step(proj(col - 0.5, row), proj(col + 0.5, row))
                half = it['units'] * KEY_FILL_W * 0.5 * per
                if lab == '←':
                    u = (-u[0], -u[1])
            else:
                u, per = step(proj(col, row - 0.5), proj(col, row + 0.5))
                half = it['rows'] * 0.5 * per
                if lab == '↑':
                    u = (-u[0], -u[1])
            L = half * ARROW_FIT * SS
            th = L * 0.42
            sw = max(2, int(L * 0.24))
            ux, uy = u
            nx, ny = -uy, ux
            ox, oy = cx * SS, cy * SS
            ld.line([(ox - ux * L * 0.85, oy - uy * L * 0.85),
                     (ox + ux * L * 0.35, oy + uy * L * 0.35)], fill=C_TEXT, width=sw)
            ld.polygon([(ox + ux * L, oy + uy * L),
                        (ox + ux * L * 0.30 + nx * th, oy + uy * L * 0.30 + ny * th),
                        (ox + ux * L * 0.30 - nx * th, oy + uy * L * 0.30 - ny * th)],
                       fill=C_TEXT)
            continue

        pa, pb = proj(col - 0.5, row), proj(col + 0.5, row)
        ang = math.degrees(math.atan2(pb[1] - pa[1], pb[0] - pa[0]))
        edge = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
        box = int(edge * SS * 3)
        tmp = Image.new('RGBA', (box, box), (0, 0, 0, 0))
        td = ImageDraw.Draw(tmp)
        base = edge * (TEXT_1CH if len(lab) == 1 else TEXT_NCH)
        size = base * PUNCT_BOOST.get(lab, 1.0)
        txt = '\\' if lab == '\\\\' else lab
        # 描边按放大前的字号算。标点要的是「字形大一点」，不是「笔画粗一圈」——
        # 两个一起放大，句点就成了一块方疙瘩。
        td.text((box / 2, box / 2), txt, font=load_font(size * SS), fill=C_TEXT,
                anchor='mm', stroke_width=max(1, int(base * SS * 0.055)),
                stroke_fill=C_TEXT)
        tmp = tmp.rotate(-ang, resample=Image.BICUBIC, center=(box / 2, box / 2))
        lay.alpha_composite(tmp, (int(cx * SS - box / 2), int(cy * SS - box / 2)))
    img.alpha_composite(lay)

    out = img.resize((W, H), Image.LANCZOS)
    shapes = [(it['vk'], it['label'],
               [(x - it['x'], y - it['y']) for x, y in quads[id(it)]])
              for it in items if it['live']]
    return out, shapes


def render_table(shapes):
    """吐成 GDScript 的字典字面量。

    写普通数组而不是 PackedVector2Array(...)：const 不接受构造调用
    （会报 "isn't a constant expression"），Vector2(x, y) 本身可以。
    """
    lines = []
    for vk, label, pts in shapes:
        body = ', '.join('Vector2(%.1f, %.1f)' % (x, y) for x, y in pts)
        lines.append('\t0x%02X: [%s],  # %s' % (vk, body, label))
    return '\n'.join(lines)


def inject(path, table):
    src = open(path, encoding='utf-8').read()
    m = re.search(r'(const KEY_SHAPES := \{\n)(.*?)(\n\})', src, re.S)
    if not m:
        sys.exit('在 %s 里没找到 KEY_SHAPES 块' % path)
    if m.group(2) == table:
        return False
    open(path, 'w', encoding='utf-8', newline='\n').write(
        src[:m.start(2)] + table + src[m.end(2):])
    return True


def main():
    # 在 main 里改 stdout，不在模块顶层 —— 顶层改的话，别的脚本 import 本模块来复用
    # read_keys / WIDE 这些东西时，会连带把它自己的 stdout 换掉，然后原来那个被关掉，
    # 后续 print 直接抛 ValueError。审查这份代码时被坑过两次。
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true', help='只看结果，不写文件')
    args = ap.parse_args()

    keys = read_keys(GD)
    p, n, avg, worst = fit_projection(keys)
    print('  读到 %d 个可按的键' % len(keys))
    print('  透视拟合：%d 个点（字母数字四排），平均残差 %.2f px，最大 %.2f px' % (n, avg, worst))
    if worst > 6.0:
        print('  !! 残差偏大，多半是某个键的 resource_position 写错了 —— 先查那个再生成')

    proj, unproj = make_transforms(p)
    img, shapes = build(keys, proj, unproj)
    print('  贴图 %dx%d，共 %d 个键帽（%d 个可按 + %d 个只画）'
          % (img.width, img.height, len(keys) + len(EXTRA_KEYS), len(keys), len(EXTRA_KEYS)))

    px = img.load()
    bad = [k['label'] for k in keys
           if px[max(0, min(W - 1, int(round(k['x'])))),
                 max(0, min(H - 1, int(round(k['y']))))][3] < 40]
    print('  自检：%s' % ('每个键位中心都落在键帽上 ✓' if not bad else '有问题 -> %s' % bad[:6]))

    table = render_table(shapes)
    if args.dry_run:
        print('  --dry-run：没有写任何文件')
        return
    img.save(OUT_PNG)
    print('  已写 %s' % os.path.relpath(OUT_PNG, ROOT))
    print('  KEY_SHAPES：%s' % ('已更新' if inject(GD, table) else '无变化'))
    print()
    print('  贴图是新的，记得让 Godot 重新导入一次（打开编辑器，或 godot --headless --import）')


if __name__ == '__main__':
    main()
