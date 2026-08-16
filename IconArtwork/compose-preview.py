#!/usr/bin/env python3
"""Flatten an option's IconComposerLayers/*.svg into one preview SVG, then
rasterise it to a 1024 PNG with qlmanage.

The layer files are what Icon Composer imports; this only exists so a direction
can be looked at before anyone opens Icon Composer. Layer-local gradient ids are
namespaced per layer so two layers can both call a gradient "well".

    ./compose-preview.py OptionB "ParchmentInk"
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def layer_body(path: Path, index: int) -> str:
    text = path.read_text()
    body = re.sub(r"^.*?<svg[^>]*>", "", text, count=1, flags=re.S)
    body = re.sub(r"</svg>\s*$", "", body, flags=re.S)
    prefix = f"L{index}_"
    for gid in re.findall(r'id="([^"]+)"', body):
        body = body.replace(f'id="{gid}"', f'id="{prefix}{gid}"')
        body = body.replace(f"url(#{gid})", f"url(#{prefix}{gid})")
    return f"  <g>\n{body}\n  </g>"


def main() -> int:
    option = sys.argv[1]
    name = sys.argv[2] if len(sys.argv) > 2 else option
    option_dir = ROOT / option
    layers = sorted((option_dir / "IconComposerLayers").glob("*.svg"))
    if not layers:
        print(f"no layers in {option_dir}", file=sys.stderr)
        return 1

    svg = "\n".join(
        ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">']
        + [layer_body(p, i) for i, p in enumerate(layers)]
        + ["</svg>", ""]
    )
    preview_svg = option_dir / f"{option}-{name}-preview.svg"
    preview_svg.write_text(svg)

    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            ["qlmanage", "-t", "-s", "1024", "-o", tmp, str(preview_svg)],
            check=True,
            capture_output=True,
        )
        rendered = next(Path(tmp).glob("*.png"))
        shutil.move(str(rendered), option_dir / f"{option}-{name}-preview.png")

    print(f"{option_dir / f'{option}-{name}-preview.png'}  ({len(layers)} layers)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
