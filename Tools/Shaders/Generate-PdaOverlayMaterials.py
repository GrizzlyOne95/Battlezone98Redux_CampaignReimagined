#!/usr/bin/env python3
"""Generate Campaign Reimagined PDA/subtitle panel materials.

DX11 has no fixed-function pipeline. Each generated material therefore puts an
SM4 programmable technique first while retaining the historical fixed-function
pass as a renderer fallback. Ogre Panel/BorderPanel geometry exposes POSITION +
TEXCOORD but no per-vertex diffuse colour, so the DX11 path must use the
dedicated CR_OverlayPanel_vertexHLSL4 input signature instead of CR_UI.
The numeric colour/alpha formulas mirror PersistentConfig._GetPdaOverlayColorSet().
"""

from __future__ import annotations

import argparse
from pathlib import Path

FAMILIES = (
    ("DG", 0.10, 0.42, 0.10),
    ("G", 0.18, 0.92, 0.18),
    ("B", 0.35, 0.65, 1.00),
    ("W", 1.00, 1.00, 1.00),
    ("R", 1.00, 0.35, 0.35),
)


def clamp(value: float, maximum: float) -> float:
    return min(maximum, value)


def colors(base_r: float, base_g: float, base_b: float, opacity: float):
    background_alpha = clamp(0.22 + opacity * 0.38, 0.82)
    header_alpha = clamp(0.20 + opacity * 0.34, 0.76)
    border_alpha = clamp(0.68 + opacity * 0.28, 1.00)

    return {
        "Backdrop": (
            clamp(0.012 + base_r * 0.05, 0.14),
            clamp(0.012 + base_g * 0.05, 0.14),
            clamp(0.012 + base_b * 0.05, 0.14),
            background_alpha,
        ),
        "Header": (
            clamp(0.018 + base_r * 0.08, 0.18),
            clamp(0.018 + base_g * 0.08, 0.18),
            clamp(0.018 + base_b * 0.08, 0.18),
            header_alpha,
        ),
        "Border": (
            clamp(0.30 + base_r * 0.85, 1.00),
            clamp(0.30 + base_g * 0.85, 1.00),
            clamp(0.30 + base_b * 0.85, 1.00),
            border_alpha,
        ),
    }


def material(name: str, rgba: tuple[float, float, float, float]) -> str:
    r, g, b, a = rgba
    return f"""material {name}
{{
    // D3D11 path: explicit SM4 programs because D3D11 has no fixed pipeline.
    technique
    {{
        pass
        {{
            vertex_program_ref CR_OverlayPanel_vertexHLSL4
            {{
            }}
            fragment_program_ref CR_OverlayTint_fragmentHLSL4
            {{
                param_named overlayColor float4 {r:.4f} {g:.4f} {b:.4f} {a:.4f}
            }}

            lighting off
            scene_blend alpha_blend
            depth_check off
            depth_write off
            cull_hardware none
            cull_software none

            texture_unit diffuseMap
            {{
                texture white.png
                tex_address_mode clamp
                filtering none none none
            }}
        }}
    }}

    // DX9/GL compatibility: preserve the original fixed-function behavior.
    technique
    {{
        pass
        {{
            lighting off
            scene_blend alpha_blend
            depth_check off
            depth_write off
            cull_hardware none
            cull_software none
            texture_unit
            {{
                texture white.png
                tex_address_mode clamp
                filtering none none none
                colour_op_ex source1 src_manual src_current {r:.4f} {g:.4f} {b:.4f}
                alpha_op_ex source1 src_manual src_current {a:.4f}
            }}
        }}
    }}
}}
"""


def generate() -> str:
    out = [
        "// Auto-generated PDA overlay fill materials.\n",
        "// Keep in sync with PersistentConfig._GetPdaOverlayColorSet().\n",
        "// Regenerate with Tools/Generate-PdaOverlayMaterials.py.\n",
        "// D3D11 uses the first programmable technique; DX9/GL fall back to the second.\n\n",
    ]

    for key, base_r, base_g, base_b in FAMILIES:
        for alpha_step in range(21):
            opacity = alpha_step * 0.05
            section_colors = colors(base_r, base_g, base_b, opacity)
            for section in ("Backdrop", "Header", "Border"):
                out.append(
                    material(
                        f"CRPda{section}_{key}_A{alpha_step:02d}",
                        section_colors[section],
                    )
                )
                out.append("\n")

    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default="Materials/cr_pda_overlay.material",
        help="output material script path",
    )
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generate(), encoding="utf-8", newline="\n")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
