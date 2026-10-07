#!/usr/bin/env python3
"""Generate `Dex/Helpers/IconlyGlyphs.swift` from Iconly Pro Light SVGs.

Usage:
    python3 -m venv /tmp/iconly-venv && /tmp/iconly-venv/bin/pip install svgelements
    /tmp/iconly-venv/bin/python Tools/iconly-paths.py Tools/iconly-svg

Each file in Tools/iconly-svg is named for its `Iconly` case (e.g. `menu.svg`)
and is the Light style, regular type: 24x24 viewBox, 1.5 stroke, round caps
and joins. close, refresh, info, settings and add are Sphinx's glyphs, so the
two apps draw shared roles identically.

Every glyph is normalized so all icons read the same size, in two steps:

1. Box: its visible extent (geometric bounds plus the stroke) is centered and
   scaled to fill the full 24-unit box.
2. Optical: a glyph whose convex hull (stroke included) is larger than the
   round icons' (`REFERENCE`) is shrunk about the center until it matches.
   Boxy and diagonal shapes (Close) read bigger than a
   circle of the same extent; open shapes (Check, chevrons) never grow past
   the box, since the eye reads those by their extent.

Every icon draws the same stroke, `LINE` units (Iconly's 1.5 on a glyph that
spans 18 of 24), so a glyph that is small in its source (Close, Add) grows in
size but not in weight. `IconlyIcon` then draws the box at `IconlyIcon.fill`
of its context's frame.

Paths are emitted as absolute M/L/C/Z only (arcs become cubics), the subset
`IconlyIcon` parses.
"""
import math
import sys
from pathlib import Path as FSPath

from svgelements import (SVG, Shape, Path, Move, Line, Close, CubicBezier,
                         QuadraticBezier, Arc, Matrix)

BOX = 24.0
LINE = 1.5 * BOX / 19.5

# Round icons whose optical size every other glyph is matched to.
REFERENCE = ['info']

# Bold (filled) glyphs: no stroke, drawn with an even-odd fill.
FILLED: set[str] = set()

# Display order in the generated enum and the Developer preview.
ORDER = [
    'menu', 'incognito', 'chevronDown', 'microphone', 'send', 'download',
    'refresh',
    'close', 'info', 'settings', 'add', 'folder', 'chat',
]


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def segments(svg_file):
    svg = SVG.parse(str(svg_file), reify=True)
    combined = Path()
    for el in svg.elements():
        if not isinstance(el, Shape) or isinstance(el, SVG):
            continue
        if el.fill is not None and el.fill.value is not None and el.fill.alpha \
                and svg_file.stem not in FILLED:
            print(f"warning: {svg_file.name} has a filled shape", file=sys.stderr)
        path = abs(Path(el))
        path.reify()
        for seg in path:
            if isinstance(seg, Arc):
                for c in seg.as_cubic_curves():
                    combined.append(c)
            elif isinstance(seg, QuadraticBezier):
                p0, p1, p2 = seg.start, seg.control, seg.end
                combined.append(CubicBezier(p0, p0 + (p1 - p0) * (2 / 3),
                                            p2 + (p1 - p2) * (2 / 3), p2))
            else:
                combined.append(seg)
    return combined


def normalize(path, line=LINE):
    x0, y0, x1, y1 = path.bbox()
    factor = (BOX - line) / max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    m = Matrix(f"translate({BOX / 2}, {BOX / 2}) scale({factor}) translate({-cx}, {-cy})")
    path = path * m
    path.reify()
    return path


def optical(path, line=LINE):
    """Side of a square with the area of the stroked glyph's convex hull."""
    points = []
    for seg in path:
        if isinstance(seg, Move):
            points.append((seg.end.x, seg.end.y))
        elif isinstance(seg, (Line, Close)) and seg.end is not None:
            points.append((seg.end.x, seg.end.y))
        elif isinstance(seg, CubicBezier):
            for i in range(1, 17):
                p = seg.point(i / 16)
                points.append((p.x, p.y))
    hull = convex_hull(points)
    area = 0.5 * abs(sum(hull[i][0] * hull[i - 1][1] - hull[i - 1][0] * hull[i][1]
                         for i in range(len(hull))))
    perimeter = sum(math.dist(hull[i], hull[i - 1]) for i in range(len(hull)))
    r = line / 2
    return math.sqrt(area + perimeter * r + math.pi * r * r)


def convex_hull(points):
    points = sorted(set(points))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def match(path, target, line=LINE):
    """Shrink about the center until the optical size is at most `target`.
    The stroke doesn't scale, so this settles over a few passes."""
    for _ in range(4):
        factor = min(1.0, target / optical(path, line))
        path = path * Matrix(f"translate({BOX / 2}, {BOX / 2}) scale({factor}) translate({-BOX / 2}, {-BOX / 2})")
        path.reify()
    return path


def emit(path):
    out = []
    for seg in path:
        if isinstance(seg, Move):
            out.append(f"M{fmt(seg.end.x)} {fmt(seg.end.y)}")
        elif isinstance(seg, Close):
            out.append("Z")
        elif isinstance(seg, Line):
            out.append(f"L{fmt(seg.end.x)} {fmt(seg.end.y)}")
        elif isinstance(seg, CubicBezier):
            c1, c2, e = seg.control1, seg.control2, seg.end
            out.append(f"C{fmt(c1.x)} {fmt(c1.y)} {fmt(c2.x)} {fmt(c2.y)} {fmt(e.x)} {fmt(e.y)}")
        else:
            raise ValueError(f"unexpected segment {type(seg).__name__}")
    return " ".join(out)


def main():
    folder = FSPath(sys.argv[1])
    names = {f.stem for f in folder.glob("*.svg")}
    missing = [n for n in ORDER if n not in names]
    extra = sorted(names - set(ORDER))
    if missing or extra:
        sys.exit(f"missing: {missing} extra: {extra}")
    line = lambda name: 0.0 if name in FILLED else LINE
    boxed = {name: normalize(segments(folder / f"{name}.svg"), line(name)) for name in ORDER}
    target = sum(optical(boxed[name]) for name in REFERENCE) / len(REFERENCE)
    rows = [(name, emit(match(boxed[name], target, line(name)))) for name in ORDER]
    lines = [
        "// Generated by Tools/iconly-paths.py from Tools/iconly-svg. Do not edit.",
        "",
        "extension Iconly {",
        "    /// Stroke width, in units of the 24-unit box, shared by every glyph.",
        f"    static let line: Double = {fmt(LINE)}",
        "",
        "    /// Bold glyphs: no stroke, drawn with an even-odd fill.",
        "    static let filled: Set<Iconly> = [" + ", ".join(f".{n}" for n in ORDER if n in FILLED) + "]",
        "",
        "    /// Each glyph centered and scaled so its visible extent (the shared",
        "    /// stroke included) fills the 24-unit box, then shrunk until its",
        "    /// optical size is no larger than the round icons'.",
        "    var path: String {",
        "        switch self {",
    ]
    for name, d in rows:
        lines.append(f'        case .{name}: "{d}"')
    lines += ["        }", "    }", "}", ""]
    out = FSPath(__file__).resolve().parent.parent / "Dex/Helpers/IconlyGlyphs.swift"
    out.write_text("\n".join(lines))
    print(f"{len(rows)} glyphs, line {LINE:.3f}, optical target {target:.3f}")


if __name__ == "__main__":
    main()
