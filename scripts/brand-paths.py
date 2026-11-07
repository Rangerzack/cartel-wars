"""Outline the brand lettering from the bundled Oswald into SVG paths for scripts/brand-assets.mjs, so the icon and the
splash need no font at render time. Run from the repo root: python3 scripts/brand-paths.py  (needs fontTools + brotli)."""
import json, pathlib
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

HERE = pathlib.Path(__file__).parent
FONTS = HERE / '..' / 'web' / 'node_modules' / '@fontsource' / 'oswald' / 'files'

def outline(weight: int, text: str, size: float, tracking: float = 0):
    f = TTFont(FONTS / f'oswald-latin-{weight}-normal.woff2')
    gs, cmap, upm = f.getGlyphSet(), f.getBestCmap(), f['head'].unitsPerEm
    scale, cx, parts = size / upm, 0.0, []
    for ch in text:
        if ch == ' ':
            cx += gs[cmap[ord(' ')]].width * scale + tracking
            continue
        g = gs[cmap[ord(ch)]]
        pen = SVGPathPen(gs)
        g.draw(TransformPen(pen, (scale, 0, 0, -scale, cx, 0)))
        parts.append(pen.getCommands())
        cx += g.width * scale + tracking
    return {'d': ' '.join(parts), 'w': round(cx - tracking, 1), 'cap': round(f['OS/2'].sCapHeight * scale, 1)}

out = {
    'cw': outline(700, 'CW', 200, tracking=6),
    'title': outline(700, 'CARTEL WARS', 120, tracking=9),
    'tag': outline(500, 'PRODUCE. MOVE PRODUCT. HOLD THE BLOCK.', 26, tracking=5.5),
}
(HERE / 'brand-paths.json').write_text(json.dumps(out))
print({k: (v['w'], v['cap']) for k, v in out.items()})
