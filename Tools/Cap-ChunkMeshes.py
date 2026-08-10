#!/usr/bin/env python3
"""Cap open boundary loops in Battlezone 98 Redux Ogre chunk meshes.

The tool is deliberately conservative about *topology* but not about which clean
holes to fill: every closed, manifold geometric boundary loop is a cap candidate.
Existing vertex coordinates are never moved or recentered, so the GEO/bone-local
origin established when the chunk meshes were exported remains unchanged.

Pipeline:
    .mesh -> OgreXMLConverter -> XML audit/capping -> OgreXMLConverter -> .mesh

Generated caps are placed in one dedicated submesh using a shared material
(default: CR_ChunkInterior). Each cap triangle uses flat normals and planar UV0.
UVs can either stretch each loop to the full 0..1 square (default) or preserve
aspect ratio with --uv-mode fit.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict, deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

Vec3 = Tuple[float, float, float]
Vec2 = Tuple[float, float]
Tri = Tuple[int, int, int]


def v_sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def v_len_sq(a: Vec3) -> float:
    return v_dot(a, a)


def v_len(a: Vec3) -> float:
    return math.sqrt(v_len_sq(a))


def v_normalize(a: Vec3, eps: float = 1e-20) -> Optional[Vec3]:
    length = v_len(a)
    if length <= eps:
        return None
    return (a[0] / length, a[1] / length, a[2] / length)


def centroid(points: Sequence[Vec3]) -> Vec3:
    inv = 1.0 / len(points)
    return (
        sum(p[0] for p in points) * inv,
        sum(p[1] for p in points) * inv,
        sum(p[2] for p in points) * inv,
    )


def bbox_diagonal(points: Sequence[Vec3]) -> float:
    if not points:
        return 0.0
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    zs = [p[2] for p in points]
    return v_len((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))


@dataclass
class SourceTriangle:
    positions: Tuple[Vec3, Vec3, Vec3]
    welded: Tri


@dataclass
class BoundaryLoop:
    welded_ids: List[int]
    positions: List[Vec3]
    projected: List[Vec2] = field(default_factory=list)
    projected_axis: int = -1
    normal: Optional[Vec3] = None
    planarity_error: float = 0.0
    area_2d: float = 0.0
    status: str = "candidate"
    reason: str = ""
    cap_triangles: List[Tri] = field(default_factory=list)


@dataclass
class MeshAudit:
    source: str = ""
    status: str = ""
    source_triangles: int = 0
    welded_vertices: int = 0
    boundary_edges: int = 0
    boundary_components: int = 0
    closed_loops: int = 0
    capped_loops: int = 0
    skipped_loops: int = 0
    added_triangles: int = 0
    nonmanifold_edges: int = 0
    unsupported_submeshes: int = 0
    notes: List[str] = field(default_factory=list)

    def csv_row(self) -> Dict[str, object]:
        return {
            "mesh": self.source,
            "status": self.status,
            "source_triangles": self.source_triangles,
            "welded_vertices": self.welded_vertices,
            "boundary_edges": self.boundary_edges,
            "boundary_components": self.boundary_components,
            "closed_loops": self.closed_loops,
            "capped_loops": self.capped_loops,
            "skipped_loops": self.skipped_loops,
            "added_triangles": self.added_triangles,
            "nonmanifold_edges": self.nonmanifold_edges,
            "unsupported_submeshes": self.unsupported_submeshes,
            "notes": "; ".join(self.notes),
        }


class SpatialWelder:
    """Topology-only position welder using a uniform 3D hash grid.

    Existing Ogre vertices are never edited. Welding is used solely to decide
    whether independently-indexed vertices occupy the same geometric point,
    which is necessary across UV/material seams and separate submeshes.
    """

    def __init__(self, epsilon: float):
        if epsilon <= 0.0:
            raise ValueError("weld epsilon must be > 0")
        self.epsilon = epsilon
        self.epsilon_sq = epsilon * epsilon
        self.points: List[Vec3] = []
        self.cells: Dict[Tuple[int, int, int], List[int]] = defaultdict(list)

    def _cell(self, p: Vec3) -> Tuple[int, int, int]:
        e = self.epsilon
        return (
            math.floor(p[0] / e),
            math.floor(p[1] / e),
            math.floor(p[2] / e),
        )

    def add(self, p: Vec3) -> int:
        cell = self._cell(p)
        cx, cy, cz = cell
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for idx in self.cells.get((cx + dx, cy + dy, cz + dz), ()):
                        if v_len_sq(v_sub(self.points[idx], p)) <= self.epsilon_sq:
                            return idx
        idx = len(self.points)
        self.points.append(p)
        self.cells[cell].append(idx)
        return idx


def _bool_attr(node: ET.Element, name: str, default: bool = False) -> bool:
    text = node.get(name)
    if text is None:
        return default
    return text.strip().lower() in {"1", "true", "yes"}


def _parse_geometry_positions(geometry: Optional[ET.Element]) -> List[Vec3]:
    if geometry is None:
        return []
    declared = int(geometry.get("vertexcount", "0") or "0")
    position_buffers = [
        vb for vb in geometry.findall("vertexbuffer") if _bool_attr(vb, "positions")
    ]
    if not position_buffers:
        return []
    vb = position_buffers[0]
    out: List[Vec3] = []
    for vertex in vb.findall("vertex"):
        pos = vertex.find("position")
        if pos is None:
            raise ValueError("position-enabled vertexbuffer contains a vertex without <position>")
        out.append(
            (
                float(pos.get("x", "0")),
                float(pos.get("y", "0")),
                float(pos.get("z", "0")),
            )
        )
    if declared and declared != len(out):
        raise ValueError(
            f"geometry declares {declared} vertices but POSITION buffer has {len(out)}"
        )
    return out


def _iter_source_triangles(
    root: ET.Element, welder: SpatialWelder, audit: MeshAudit
) -> List[SourceTriangle]:
    shared_positions = _parse_geometry_positions(root.find("sharedgeometry"))
    submeshes = root.find("submeshes")
    if submeshes is None:
        raise ValueError("mesh XML has no <submeshes>")

    triangles: List[SourceTriangle] = []
    for sm_index, submesh in enumerate(submeshes.findall("submesh")):
        operation = submesh.get("operationtype", "triangle_list")
        if operation != "triangle_list":
            audit.unsupported_submeshes += 1
            audit.notes.append(
                f"submesh {sm_index}: skipped operationtype={operation}"
            )
            continue
        use_shared = _bool_attr(submesh, "usesharedvertices", True)
        positions = (
            shared_positions
            if use_shared
            else _parse_geometry_positions(submesh.find("geometry"))
        )
        if not positions:
            audit.notes.append(f"submesh {sm_index}: no readable positions")
            continue
        faces = submesh.find("faces")
        if faces is None:
            continue
        for face in faces.findall("face"):
            try:
                idxs = (
                    int(face.get("v1", "-1")),
                    int(face.get("v2", "-1")),
                    int(face.get("v3", "-1")),
                )
            except ValueError as exc:
                raise ValueError(f"submesh {sm_index} has invalid face index") from exc
            if min(idxs) < 0 or max(idxs) >= len(positions):
                raise ValueError(
                    f"submesh {sm_index} face {idxs} is outside geometry vertex count "
                    f"{len(positions)}"
                )
            pos = (positions[idxs[0]], positions[idxs[1]], positions[idxs[2]])
            welded = (welder.add(pos[0]), welder.add(pos[1]), welder.add(pos[2]))
            if len(set(welded)) < 3:
                continue
            triangles.append(SourceTriangle(pos, welded))
    audit.source_triangles = len(triangles)
    audit.welded_vertices = len(welder.points)
    return triangles


def _edge_key(a: int, b: int) -> Tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _boundary_loops(
    triangles: Sequence[SourceTriangle],
    welded_points: Sequence[Vec3],
    audit: MeshAudit,
) -> List[BoundaryLoop]:
    occurrences: Dict[Tuple[int, int], List[Tuple[int, int]]] = defaultdict(list)
    for tri in triangles:
        a, b, c = tri.welded
        for u, v in ((a, b), (b, c), (c, a)):
            occurrences[_edge_key(u, v)].append((u, v))

    boundary_directed: Dict[Tuple[int, int], Tuple[int, int]] = {}
    adjacency: Dict[int, List[int]] = defaultdict(list)
    for key, uses in occurrences.items():
        if len(uses) == 1:
            u, v = uses[0]
            boundary_directed[key] = (u, v)
            adjacency[u].append(v)
            adjacency[v].append(u)
        elif len(uses) > 2:
            audit.nonmanifold_edges += 1

    audit.boundary_edges = len(boundary_directed)
    if not boundary_directed:
        return []

    components: List[List[int]] = []
    unseen = set(adjacency)
    while unseen:
        start = next(iter(unseen))
        queue = deque([start])
        component: List[int] = []
        unseen.remove(start)
        while queue:
            current = queue.popleft()
            component.append(current)
            for nxt in adjacency[current]:
                if nxt in unseen:
                    unseen.remove(nxt)
                    queue.append(nxt)
        components.append(component)
    audit.boundary_components = len(components)

    loops: List[BoundaryLoop] = []
    for component in components:
        if len(component) < 3 or any(len(adjacency[v]) != 2 for v in component):
            audit.skipped_loops += 1
            audit.notes.append(
                f"boundary component with {len(component)} vertices is non-loop/non-manifold "
                f"(degrees={sorted(set(len(adjacency[v]) for v in component))})"
            )
            continue

        start = min(component)
        prev = -1
        current = start
        ordered: List[int] = []
        for _ in range(len(component) + 1):
            ordered.append(current)
            neighbors = adjacency[current]
            nxt = neighbors[0] if neighbors[0] != prev else neighbors[1]
            prev, current = current, nxt
            if current == start:
                break
        if current != start or len(ordered) != len(component):
            audit.skipped_loops += 1
            audit.notes.append(
                f"failed to traverse boundary component with {len(component)} vertices"
            )
            continue

        matches = 0
        mismatches = 0
        for i, u in enumerate(ordered):
            v = ordered[(i + 1) % len(ordered)]
            directed = boundary_directed[_edge_key(u, v)]
            if directed == (u, v):
                matches += 1
            else:
                mismatches += 1

        # Existing surface triangles define the boundary direction. The missing
        # closing face uses the opposite direction so edge winding is manifold.
        cap_order = list(reversed(ordered)) if matches >= mismatches else ordered
        loops.append(
            BoundaryLoop(cap_order, [welded_points[i] for i in cap_order])
        )

    audit.closed_loops = len(loops)
    return loops


def _newell_normal(points: Sequence[Vec3]) -> Vec3:
    nx = ny = nz = 0.0
    for i, p in enumerate(points):
        q = points[(i + 1) % len(points)]
        nx += (p[1] - q[1]) * (p[2] + q[2])
        ny += (p[2] - q[2]) * (p[0] + q[0])
        nz += (p[0] - q[0]) * (p[1] + q[1])
    return (nx, ny, nz)


def _project(points: Sequence[Vec3], normal: Vec3) -> Tuple[int, List[Vec2]]:
    axis = max(range(3), key=lambda i: abs(normal[i]))
    if axis == 0:
        return axis, [(p[1], p[2]) for p in points]
    if axis == 1:
        return axis, [(p[0], p[2]) for p in points]
    return axis, [(p[0], p[1]) for p in points]


def _project_point(p: Vec3, axis: int) -> Vec2:
    if axis == 0:
        return (p[1], p[2])
    if axis == 1:
        return (p[0], p[2])
    return (p[0], p[1])


def _cross2(a: Vec2, b: Vec2, c: Vec2) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _polygon_area2(points: Sequence[Vec2]) -> float:
    return 0.5 * sum(
        p[0] * points[(i + 1) % len(points)][1]
        - points[(i + 1) % len(points)][0] * p[1]
        for i, p in enumerate(points)
    )


def _point_in_triangle(
    p: Vec2, a: Vec2, b: Vec2, c: Vec2, eps: float
) -> bool:
    c1 = _cross2(a, b, p)
    c2 = _cross2(b, c, p)
    c3 = _cross2(c, a, p)
    has_neg = c1 < -eps or c2 < -eps or c3 < -eps
    has_pos = c1 > eps or c2 > eps or c3 > eps
    return not (has_neg and has_pos)


def _point_in_polygon(p: Vec2, polygon: Sequence[Vec2]) -> bool:
    inside = False
    j = len(polygon) - 1
    for i, pi in enumerate(polygon):
        pj = polygon[j]
        if (pi[1] > p[1]) != (pj[1] > p[1]):
            x_at_y = (
                (pj[0] - pi[0]) * (p[1] - pi[1])
                / ((pj[1] - pi[1]) or 1e-30)
                + pi[0]
            )
            if p[0] < x_at_y:
                inside = not inside
        j = i
    return inside


def _orientation(a: Vec2, b: Vec2, c: Vec2, eps: float) -> int:
    value = _cross2(a, b, c)
    if value > eps:
        return 1
    if value < -eps:
        return -1
    return 0


def _on_segment(a: Vec2, b: Vec2, p: Vec2, eps: float) -> bool:
    return (
        min(a[0], b[0]) - eps <= p[0] <= max(a[0], b[0]) + eps
        and min(a[1], b[1]) - eps <= p[1] <= max(a[1], b[1]) + eps
        and abs(_cross2(a, b, p)) <= eps
    )


def _segments_intersect(
    a: Vec2, b: Vec2, c: Vec2, d: Vec2, eps: float
) -> bool:
    o1 = _orientation(a, b, c, eps)
    o2 = _orientation(a, b, d, eps)
    o3 = _orientation(c, d, a, eps)
    o4 = _orientation(c, d, b, eps)
    if o1 != o2 and o3 != o4:
        return True
    if o1 == 0 and _on_segment(a, b, c, eps):
        return True
    if o2 == 0 and _on_segment(a, b, d, eps):
        return True
    if o3 == 0 and _on_segment(c, d, a, eps):
        return True
    if o4 == 0 and _on_segment(c, d, b, eps):
        return True
    return False


def _self_intersects(poly: Sequence[Vec2], eps: float) -> bool:
    count = len(poly)
    for i in range(count):
        a, b = poly[i], poly[(i + 1) % count]
        for j in range(i + 1, count):
            if j == i or j == (i + 1) % count or i == (j + 1) % count:
                continue
            c, d = poly[j], poly[(j + 1) % count]
            if _segments_intersect(a, b, c, d, eps):
                return True
    return False


def _remove_collinear(
    points3: Sequence[Vec3], points2: Sequence[Vec2], eps: float
) -> Tuple[List[Vec3], List[Vec2]]:
    p3 = list(points3)
    p2 = list(points2)
    changed = True
    while changed and len(p2) > 3:
        changed = False
        for i in range(len(p2)):
            prev = p2[i - 1]
            cur = p2[i]
            nxt = p2[(i + 1) % len(p2)]
            if abs(_cross2(prev, cur, nxt)) <= eps:
                del p2[i]
                del p3[i]
                changed = True
                break
    return p3, p2


def _ear_clip(poly: Sequence[Vec2], eps: float) -> Optional[List[Tri]]:
    if len(poly) < 3:
        return None
    area = _polygon_area2(poly)
    if abs(area) <= eps:
        return None
    winding = 1.0 if area > 0.0 else -1.0
    remaining = list(range(len(poly)))
    triangles: List[Tri] = []
    guard = 0
    max_guard = len(poly) * len(poly) * 2

    while len(remaining) > 3 and guard < max_guard:
        guard += 1
        ear_found = False
        for slot, curr in enumerate(remaining):
            prev = remaining[slot - 1]
            nxt = remaining[(slot + 1) % len(remaining)]
            if winding * _cross2(poly[prev], poly[curr], poly[nxt]) <= eps:
                continue
            if any(
                other not in {prev, curr, nxt}
                and _point_in_triangle(
                    poly[other], poly[prev], poly[curr], poly[nxt], eps
                )
                for other in remaining
            ):
                continue
            triangles.append((prev, curr, nxt))
            del remaining[slot]
            ear_found = True
            break
        if not ear_found:
            return None

    if len(remaining) == 3:
        triangles.append((remaining[0], remaining[1], remaining[2]))
    return triangles


def _planarity_error(
    points: Sequence[Vec3], plane_point: Vec3, normal: Vec3
) -> float:
    return max(abs(v_dot(v_sub(p, plane_point), normal)) for p in points)


def _has_coplanar_overlap(
    loop: BoundaryLoop,
    triangles: Sequence[SourceTriangle],
    plane_epsilon: float,
) -> bool:
    assert loop.normal is not None
    center = centroid(loop.positions)
    normal = loop.normal
    for tri in triangles:
        points = tri.positions
        if max(
            abs(v_dot(v_sub(p, center), normal)) for p in points
        ) > plane_epsilon:
            continue
        tri_normal = v_normalize(
            v_cross(v_sub(points[1], points[0]), v_sub(points[2], points[0]))
        )
        if tri_normal is None or abs(v_dot(tri_normal, normal)) < 0.98:
            continue
        tri_center = centroid(points)
        if _point_in_polygon(
            _project_point(tri_center, loop.projected_axis), loop.projected
        ):
            return True
    return False


def _prepare_loop(
    loop: BoundaryLoop,
    triangles: Sequence[SourceTriangle],
    geometric_epsilon: float,
    plane_epsilon: float,
    allow_overlap: bool,
) -> None:
    normal = v_normalize(_newell_normal(loop.positions))
    if normal is None:
        loop.status = "skipped"
        loop.reason = "degenerate_normal"
        return
    loop.normal = normal
    axis, projected = _project(loop.positions, normal)
    loop.projected_axis = axis
    loop.planarity_error = _planarity_error(
        loop.positions, centroid(loop.positions), normal
    )

    clean3, clean2 = _remove_collinear(
        loop.positions, projected, geometric_epsilon
    )
    if len(clean2) < 3:
        loop.status = "skipped"
        loop.reason = "degenerate_after_collinear_cleanup"
        return
    loop.positions = clean3
    loop.projected = clean2
    loop.area_2d = abs(_polygon_area2(clean2))
    if loop.area_2d <= geometric_epsilon:
        loop.status = "skipped"
        loop.reason = "near_zero_projected_area"
        return
    if _self_intersects(clean2, geometric_epsilon):
        loop.status = "skipped"
        loop.reason = "self_intersecting_projection"
        return
    if not allow_overlap and _has_coplanar_overlap(
        loop, triangles, plane_epsilon
    ):
        loop.status = "skipped"
        loop.reason = "coplanar_overlap"
        return
    cap_tris = _ear_clip(clean2, geometric_epsilon)
    if not cap_tris:
        loop.status = "skipped"
        loop.reason = "triangulation_failed"
        return
    loop.cap_triangles = cap_tris
    loop.status = "capped"


def _uv_map(points: Sequence[Vec2], mode: str) -> List[Vec2]:
    min_u = min(p[0] for p in points)
    max_u = max(p[0] for p in points)
    min_v = min(p[1] for p in points)
    max_v = max(p[1] for p in points)
    width = max(max_u - min_u, 1e-20)
    height = max(max_v - min_v, 1e-20)
    if mode == "stretch":
        return [
            ((p[0] - min_u) / width, (p[1] - min_v) / height)
            for p in points
        ]
    scale = max(width, height)
    pad_u = (1.0 - width / scale) * 0.5
    pad_v = (1.0 - height / scale) * 0.5
    return [
        (
            pad_u + (p[0] - min_u) / scale,
            pad_v + (p[1] - min_v) / scale,
        )
        for p in points
    ]


def _fmt(value: float) -> str:
    return format(value, ".9g")


def _append_cap_submesh(
    root: ET.Element,
    loops: Sequence[BoundaryLoop],
    material: str,
    uv_mode: str,
) -> int:
    cap_loops = [loop for loop in loops if loop.status == "capped"]
    if not cap_loops:
        return 0

    cap_vertices: List[Tuple[Vec3, Vec3, Vec2]] = []
    cap_faces: List[Tri] = []
    for loop in cap_loops:
        uvs = _uv_map(loop.projected, uv_mode)
        for tri in loop.cap_triangles:
            p0, p1, p2 = (
                loop.positions[tri[0]],
                loop.positions[tri[1]],
                loop.positions[tri[2]],
            )
            face_normal = v_normalize(
                v_cross(v_sub(p1, p0), v_sub(p2, p0))
            )
            if face_normal is None:
                continue
            base = len(cap_vertices)
            for idx in tri:
                cap_vertices.append((loop.positions[idx], face_normal, uvs[idx]))
            cap_faces.append((base, base + 1, base + 2))

    if not cap_faces:
        return 0

    submeshes = root.find("submeshes")
    if submeshes is None:
        raise ValueError("mesh XML has no <submeshes>")
    submesh = ET.SubElement(
        submeshes,
        "submesh",
        {
            "material": material,
            "usesharedvertices": "false",
            "use32bitindexes": "true" if len(cap_vertices) > 65535 else "false",
            "operationtype": "triangle_list",
        },
    )
    faces = ET.SubElement(
        submesh, "faces", {"count": str(len(cap_faces))}
    )
    for a, b, c in cap_faces:
        ET.SubElement(
            faces,
            "face",
            {"v1": str(a), "v2": str(b), "v3": str(c)},
        )

    geometry = ET.SubElement(
        submesh, "geometry", {"vertexcount": str(len(cap_vertices))}
    )
    vertex_buffer = ET.SubElement(
        geometry,
        "vertexbuffer",
        {
            "positions": "true",
            "normals": "true",
            "texture_coords": "1",
            "texture_coord_dimensions_0": "float2",
        },
    )
    for pos, normal, uv in cap_vertices:
        vertex = ET.SubElement(vertex_buffer, "vertex")
        ET.SubElement(
            vertex,
            "position",
            {"x": _fmt(pos[0]), "y": _fmt(pos[1]), "z": _fmt(pos[2])},
        )
        ET.SubElement(
            vertex,
            "normal",
            {
                "x": _fmt(normal[0]),
                "y": _fmt(normal[1]),
                "z": _fmt(normal[2]),
            },
        )
        ET.SubElement(
            vertex,
            "texcoord",
            {"u": _fmt(uv[0]), "v": _fmt(uv[1])},
        )
    return len(cap_faces)


def process_xml(
    xml_in: Path,
    xml_out: Optional[Path],
    *,
    source_label: str,
    weld_epsilon: float,
    material: str,
    uv_mode: str,
    allow_overlap: bool,
    audit_only: bool,
) -> Tuple[MeshAudit, List[BoundaryLoop]]:
    audit = MeshAudit(source=source_label)
    tree = ET.parse(xml_in)
    root = tree.getroot()
    if root.tag != "mesh":
        raise ValueError(f"expected <mesh> root, got <{root.tag}>")

    welder = SpatialWelder(weld_epsilon)
    triangles = _iter_source_triangles(root, welder, audit)
    if not triangles:
        audit.status = "no_triangles"
        return audit, []

    diagonal = bbox_diagonal(welder.points)
    geometric_epsilon = max(
        weld_epsilon * 0.25, max(diagonal, 1.0) * 1e-10
    )
    plane_epsilon = max(
        weld_epsilon * 4.0, max(diagonal, 1.0) * 1e-5
    )
    loops = _boundary_loops(triangles, welder.points, audit)
    for loop in loops:
        _prepare_loop(
            loop,
            triangles,
            geometric_epsilon,
            plane_epsilon,
            allow_overlap,
        )

    audit.capped_loops = sum(loop.status == "capped" for loop in loops)
    audit.skipped_loops += sum(loop.status == "skipped" for loop in loops)
    for loop in loops:
        if loop.status == "skipped":
            audit.notes.append(
                f"loop({len(loop.positions)} verts): {loop.reason}"
            )

    if audit_only:
        audit.added_triangles = sum(
            len(loop.cap_triangles)
            for loop in loops
            if loop.status == "capped"
        )
        audit.status = "audited"
        return audit, loops

    if xml_out is None:
        raise ValueError("xml_out is required when audit_only is false")
    audit.added_triangles = _append_cap_submesh(
        root, loops, material, uv_mode
    )
    audit.status = "capped" if audit.added_triangles else "unchanged"
    xml_out.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(tree, space="  ")
    tree.write(xml_out, encoding="utf-8", xml_declaration=True)
    return audit, loops


def _run_converter(converter: str, source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = [converter, "-q", str(source), str(destination)]
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.returncode != 0:
        output = completed.stdout.strip()
        raise RuntimeError(
            f"OgreXMLConverter failed ({completed.returncode}) for {source}\n"
            f"command: {' '.join(command)}\n{output}"
        )


def _resolve_converter(name: str) -> str:
    path = Path(name)
    if path.exists():
        return str(path.resolve())
    found = shutil.which(name)
    if found:
        return found
    if os.name == "nt" and not name.lower().endswith(".exe"):
        found = shutil.which(name + ".exe")
        if found:
            return found
    raise FileNotFoundError(
        f"OgreXMLConverter not found: {name!r}. Pass --converter with the "
        "Ogre 1.10 converter path."
    )


def _collect_meshes(
    input_path: Path,
    include: re.Pattern[str],
    exclude: re.Pattern[str],
) -> List[Path]:
    candidates = (
        [input_path]
        if input_path.is_file()
        else sorted(input_path.rglob("*.mesh"))
    )
    return [
        path
        for path in candidates
        if path.is_file()
        and path.suffix.lower() == ".mesh"
        and include.search(path.as_posix())
        and not exclude.search(path.as_posix())
    ]


def _default_output(input_path: Path) -> Path:
    if input_path.is_file():
        return input_path.with_name(input_path.stem + ".capped.mesh")
    return input_path.with_name(input_path.name.rstrip("/\\") + "_capped")


def _output_for(
    source: Path, input_root: Path, output_root: Path
) -> Path:
    if input_root.is_file():
        return output_root
    return output_root / source.relative_to(input_root)


def _write_report(path: Path, audits: Sequence[MeshAudit]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(MeshAudit().csv_row().keys())
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        for audit in audits:
            writer.writerow(audit.csv_row())


def process_mesh_file(
    source: Path,
    destination: Optional[Path],
    *,
    converter: str,
    weld_epsilon: float,
    material: str,
    uv_mode: str,
    allow_overlap: bool,
    audit_only: bool,
    keep_xml: bool,
) -> MeshAudit:
    with tempfile.TemporaryDirectory(prefix="bz_chunk_caps_") as temp_text:
        temp_dir = Path(temp_text)
        raw_xml = temp_dir / (source.name + ".xml")
        capped_xml = temp_dir / (source.name + ".capped.xml")
        _run_converter(converter, source, raw_xml)
        audit, _loops = process_xml(
            raw_xml,
            None if audit_only else capped_xml,
            source_label=str(source),
            weld_epsilon=weld_epsilon,
            material=material,
            uv_mode=uv_mode,
            allow_overlap=allow_overlap,
            audit_only=audit_only,
        )

        if not audit_only and destination is not None:
            destination.parent.mkdir(parents=True, exist_ok=True)
            if audit.status == "unchanged":
                # Do not XML-roundtrip a mesh when there is nothing to add.
                shutil.copy2(source, destination)
            else:
                _run_converter(converter, capped_xml, destination)

        if keep_xml:
            xml_dir = (
                destination.parent if destination is not None else source.parent
            ) / "_chunk_cap_xml"
            xml_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(raw_xml, xml_dir / (source.name + ".before.xml"))
            if capped_xml.exists():
                shutil.copy2(
                    capped_xml, xml_dir / (source.name + ".capped.xml")
                )
        return audit


def _write_synthetic_xml(
    path: Path, vertices: Sequence[Vec3], faces: Sequence[Tri]
) -> None:
    mesh = ET.Element("mesh")
    submeshes = ET.SubElement(mesh, "submeshes")
    submesh = ET.SubElement(
        submeshes,
        "submesh",
        {
            "material": "test",
            "usesharedvertices": "false",
            "use32bitindexes": "false",
            "operationtype": "triangle_list",
        },
    )
    faces_node = ET.SubElement(
        submesh, "faces", {"count": str(len(faces))}
    )
    for tri in faces:
        ET.SubElement(
            faces_node,
            "face",
            {"v1": str(tri[0]), "v2": str(tri[1]), "v3": str(tri[2])},
        )
    geometry = ET.SubElement(
        submesh, "geometry", {"vertexcount": str(len(vertices))}
    )
    vertex_buffer = ET.SubElement(
        geometry, "vertexbuffer", {"positions": "true"}
    )
    for point in vertices:
        vertex = ET.SubElement(vertex_buffer, "vertex")
        ET.SubElement(
            vertex,
            "position",
            {"x": str(point[0]), "y": str(point[1]), "z": str(point[2])},
        )
    ET.ElementTree(mesh).write(path, encoding="utf-8", xml_declaration=True)


def run_self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="bz_chunk_caps_selftest_") as text:
        root = Path(text)

        cube_vertices = [
            (-1, -1, -1),
            (1, -1, -1),
            (1, 1, -1),
            (-1, 1, -1),
            (-1, -1, 1),
            (1, -1, 1),
            (1, 1, 1),
            (-1, 1, 1),
        ]
        cube_faces = [
            (0, 2, 1),
            (0, 3, 2),
            (0, 1, 5),
            (0, 5, 4),
            (1, 2, 6),
            (1, 6, 5),
            (2, 3, 7),
            (2, 7, 6),
            (3, 0, 4),
            (3, 4, 7),
        ]
        cube_in = root / "open_cube.xml"
        cube_out = root / "open_cube.capped.xml"
        _write_synthetic_xml(cube_in, cube_vertices, cube_faces)
        audit, loops = process_xml(
            cube_in,
            cube_out,
            source_label="open_cube",
            weld_epsilon=1e-6,
            material="CR_ChunkInterior",
            uv_mode="stretch",
            allow_overlap=False,
            audit_only=False,
        )
        assert audit.closed_loops == 1, audit
        assert audit.capped_loops == 1, audit
        assert audit.added_triangles == 2, audit
        assert loops[0].status == "capped", loops[0]
        uvs = _uv_map(loops[0].projected, "stretch")
        assert min(u for u, _ in uvs) == 0.0
        assert max(u for u, _ in uvs) == 1.0
        assert min(v for _, v in uvs) == 0.0
        assert max(v for _, v in uvs) == 1.0

        sheet_vertices = [
            (-1, -1, 0),
            (1, -1, 0),
            (1, 1, 0),
            (-1, 1, 0),
        ]
        sheet_faces = [(0, 1, 2), (0, 2, 3)]
        sheet_in = root / "sheet.xml"
        sheet_out = root / "sheet.capped.xml"
        _write_synthetic_xml(sheet_in, sheet_vertices, sheet_faces)
        audit, loops = process_xml(
            sheet_in,
            sheet_out,
            source_label="sheet",
            weld_epsilon=1e-6,
            material="CR_ChunkInterior",
            uv_mode="stretch",
            allow_overlap=False,
            audit_only=False,
        )
        assert audit.closed_loops == 1, audit
        assert audit.capped_loops == 0, audit
        assert audit.added_triangles == 0, audit
        assert loops[0].reason == "coplanar_overlap", loops[0]

        tube_vertices = cube_vertices
        tube_faces = [
            (0, 1, 5),
            (0, 5, 4),
            (1, 2, 6),
            (1, 6, 5),
            (2, 3, 7),
            (2, 7, 6),
            (3, 0, 4),
            (3, 4, 7),
        ]
        tube_in = root / "tube.xml"
        tube_out = root / "tube.capped.xml"
        _write_synthetic_xml(tube_in, tube_vertices, tube_faces)
        audit, _loops = process_xml(
            tube_in,
            tube_out,
            source_label="tube",
            weld_epsilon=1e-6,
            material="CR_ChunkInterior",
            uv_mode="stretch",
            allow_overlap=False,
            audit_only=False,
        )
        assert audit.closed_loops == 2, audit
        assert audit.capped_loops == 2, audit
        assert audit.added_triangles == 4, audit

    print(
        "Self-test passed: open cube, flat-sheet rejection, and two-ended tube."
    )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", help="Input .mesh file or directory tree")
    parser.add_argument(
        "--output",
        help="Output .mesh path or output root. Defaults to <input>_capped.",
    )
    parser.add_argument(
        "--converter",
        default="OgreXMLConverter",
        help="Ogre 1.10 OgreXMLConverter executable/path (default: search PATH)",
    )
    parser.add_argument(
        "--material",
        default="CR_ChunkInterior",
        help="Material assigned to the generated cap submesh",
    )
    parser.add_argument(
        "--weld-epsilon",
        type=float,
        default=1e-5,
        help="Position tolerance used only for topology detection (default: 1e-5)",
    )
    parser.add_argument(
        "--uv-mode",
        choices=("stretch", "fit"),
        default="stretch",
        help="stretch fills 0..1 per loop; fit preserves projected aspect ratio",
    )
    parser.add_argument(
        "--allow-coplanar-overlap",
        action="store_true",
        help="Disable the flat-sheet/duplicate-surface overlap safeguard",
    )
    parser.add_argument(
        "--audit-only",
        action="store_true",
        help="Detect/report cap candidates without writing output meshes",
    )
    parser.add_argument(
        "--report",
        default="chunk_cap_report.csv",
        help="CSV summary path (default: chunk_cap_report.csv)",
    )
    parser.add_argument(
        "--include-regex",
        default=".*",
        help="Only process mesh paths matching this regex",
    )
    parser.add_argument(
        "--exclude-regex",
        default="^$",
        help="Skip mesh paths matching this regex",
    )
    parser.add_argument(
        "--keep-xml",
        action="store_true",
        help="Keep before/after XML beside output for inspection",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run synthetic topology regression tests and exit",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.self_test:
        run_self_test()
        return 0
    if not args.input:
        raise SystemExit("--input is required unless --self-test is used")
    if args.weld_epsilon <= 0.0:
        raise SystemExit("--weld-epsilon must be > 0")

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        raise SystemExit(f"input does not exist: {input_path}")
    include = re.compile(args.include_regex, re.IGNORECASE)
    exclude = re.compile(args.exclude_regex, re.IGNORECASE)
    meshes = _collect_meshes(input_path, include, exclude)
    if not meshes:
        raise SystemExit(f"no matching .mesh files found under {input_path}")

    converter = _resolve_converter(args.converter)
    output_root = (
        Path(args.output).resolve()
        if args.output
        else _default_output(input_path)
    )
    if input_path.is_dir() and output_root == input_path:
        raise SystemExit(
            "refusing to use the input directory as output; choose a separate "
            "--output tree"
        )
    if input_path.is_file() and not args.audit_only and output_root == input_path:
        raise SystemExit(
            "refusing to overwrite the input mesh; choose a different --output path"
        )

    audits: List[MeshAudit] = []
    print(
        f"Processing {len(meshes)} mesh(es); material={args.material}; "
        f"weld_epsilon={args.weld_epsilon:g}"
    )
    for index, source in enumerate(meshes, 1):
        destination = (
            None
            if args.audit_only
            else _output_for(source, input_path, output_root)
        )
        try:
            audit = process_mesh_file(
                source,
                destination,
                converter=converter,
                weld_epsilon=args.weld_epsilon,
                material=args.material,
                uv_mode=args.uv_mode,
                allow_overlap=args.allow_coplanar_overlap,
                audit_only=args.audit_only,
                keep_xml=args.keep_xml,
            )
        except Exception as exc:
            audit = MeshAudit(
                source=str(source),
                status="error",
                notes=[str(exc).replace("\n", " | ")],
            )
        audits.append(audit)
        print(
            f"[{index:>4}/{len(meshes)}] {source.name}: {audit.status}; "
            f"loops={audit.closed_loops}, capped={audit.capped_loops}, "
            f"skipped={audit.skipped_loops}, +tris={audit.added_triangles}"
        )

    report_path = Path(args.report).resolve()
    _write_report(report_path, audits)
    failures = sum(a.status == "error" for a in audits)
    total_caps = sum(a.capped_loops for a in audits)
    total_tris = sum(a.added_triangles for a in audits)
    print(f"Report: {report_path}")
    print(
        f"Complete: {total_caps} loop(s) capped, {total_tris} triangle(s) "
        f"added, {failures} error(s)."
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
