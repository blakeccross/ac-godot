from __future__ import annotations

import math
from dataclasses import dataclass


def sin_s(angle: int) -> float:
    return math.sin(angle * (2.0 * math.pi / 65536.0))


def cos_s(angle: int) -> float:
    return math.cos(angle * (2.0 * math.pi / 65536.0))


@dataclass
class Mat4:
    """4x4, column vectors, matching ac-decomp MtxF (x' = xx*x + xy*y + xz*z + xw)."""

    m: list[list[float]]

    @staticmethod
    def identity() -> Mat4:
        return Mat4(
            [
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, 0.0, 0.0, 1.0],
            ]
        )

    def copy(self) -> Mat4:
        return Mat4([row[:] for row in self.m])

    def mul(self, other: Mat4) -> Mat4:
        a, b = self.m, other.m
        out = [[0.0] * 4 for _ in range(4)]
        for i in range(4):
            for j in range(4):
                out[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
        return Mat4(out)

    def transform_point(self, x: float, y: float, z: float) -> tuple[float, float, float]:
        m = self.m
        return (
            m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
            m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
            m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3],
        )

    def transform_vector(self, x: float, y: float, z: float) -> tuple[float, float, float]:
        """Rotate/scale a direction (no translation). Rigid binds: fine for normals."""
        m = self.m
        return (
            m[0][0] * x + m[0][1] * y + m[0][2] * z,
            m[1][0] * x + m[1][1] * y + m[1][2] * z,
            m[2][0] * x + m[2][1] * y + m[2][2] * z,
        )

    def inverse_affine(self) -> Mat4:
        r = [self.m[i][:3] for i in range(3)]
        det = (
            r[0][0] * (r[1][1] * r[2][2] - r[1][2] * r[2][1])
            - r[0][1] * (r[1][0] * r[2][2] - r[1][2] * r[2][0])
            + r[0][2] * (r[1][0] * r[2][1] - r[1][1] * r[2][0])
        )
        if abs(det) < 1e-12:
            return Mat4.identity()
        invr = [[0.0] * 3 for _ in range(3)]
        invr[0][0] = (r[1][1] * r[2][2] - r[1][2] * r[2][1]) / det
        invr[0][1] = (r[0][2] * r[2][1] - r[0][1] * r[2][2]) / det
        invr[0][2] = (r[0][1] * r[1][2] - r[0][2] * r[1][1]) / det
        invr[1][0] = (r[1][2] * r[2][0] - r[1][0] * r[2][2]) / det
        invr[1][1] = (r[0][0] * r[2][2] - r[0][2] * r[2][0]) / det
        invr[1][2] = (r[0][2] * r[1][0] - r[0][0] * r[1][2]) / det
        invr[2][0] = (r[1][0] * r[2][1] - r[1][1] * r[2][0]) / det
        invr[2][1] = (r[0][1] * r[2][0] - r[0][0] * r[2][1]) / det
        invr[2][2] = (r[0][0] * r[1][1] - r[0][1] * r[1][0]) / det
        t = [self.m[0][3], self.m[1][3], self.m[2][3]]
        it = [
            -(invr[0][0] * t[0] + invr[0][1] * t[1] + invr[0][2] * t[2]),
            -(invr[1][0] * t[0] + invr[1][1] * t[1] + invr[1][2] * t[2]),
            -(invr[2][0] * t[0] + invr[2][1] * t[1] + invr[2][2] * t[2]),
        ]
        return Mat4(
            [
                [invr[0][0], invr[0][1], invr[0][2], it[0]],
                [invr[1][0], invr[1][1], invr[1][2], it[1]],
                [invr[2][0], invr[2][1], invr[2][2], it[2]],
                [0.0, 0.0, 0.0, 1.0],
            ]
        )

    def to_godot(self) -> Mat4:
        """Reflect GC +Z onto Godot -Z: S * M * S with S = diag(1,1,-1,1)."""
        s = Mat4.identity()
        s.m[2][2] = -1.0
        return s.mul(self).mul(s)

    def translation(self) -> tuple[float, float, float]:
        return self.m[0][3], self.m[1][3], self.m[2][3]

    def rotation_quat(self) -> tuple[float, float, float, float]:
        """Return (x, y, z, w) from the 3x3. Assumes no scale/shear."""
        m00, m01, m02 = self.m[0][0], self.m[0][1], self.m[0][2]
        m10, m11, m12 = self.m[1][0], self.m[1][1], self.m[1][2]
        m20, m21, m22 = self.m[2][0], self.m[2][1], self.m[2][2]
        trace = m00 + m11 + m22
        if trace > 0:
            s = math.sqrt(trace + 1.0) * 2.0
            w = 0.25 * s
            x = (m21 - m12) / s
            y = (m02 - m20) / s
            z = (m10 - m01) / s
        elif m00 > m11 and m00 > m22:
            s = math.sqrt(1.0 + m00 - m11 - m22) * 2.0
            w = (m21 - m12) / s
            x = 0.25 * s
            y = (m01 + m10) / s
            z = (m02 + m20) / s
        elif m11 > m22:
            s = math.sqrt(1.0 + m11 - m00 - m22) * 2.0
            w = (m02 - m20) / s
            x = (m01 + m10) / s
            y = 0.25 * s
            z = (m12 + m21) / s
        else:
            s = math.sqrt(1.0 + m22 - m00 - m11) * 2.0
            w = (m10 - m01) / s
            x = (m02 + m20) / s
            y = (m12 + m21) / s
            z = 0.25 * s
        n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
        return x / n, y / n, z / n, w / n

    def gltf_mat4(self) -> list[float]:
        """Column-major 16 floats."""
        out: list[float] = []
        for col in range(4):
            for row in range(4):
                out.append(self.m[row][col])
        return out


def ckf_basis() -> Mat4:
    """+90° about Z: GC cKF bind (+X along the chain) → Godot Y-up."""
    return Mat4(
        [
            [0.0, -1.0, 0.0, 0.0],
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ]
    )


def ckf_bind_to_godot(x: float, y: float, z: float) -> tuple[float, float, float]:
    """Stand a cKF bind-pose point for Godot/glTF (Y-up).

    Animal Crossing cKF rest translations put the chain along +X (head at +X,
    feet along ±Y). The assembled Blender ``BOY.dae`` uses the same numbers but
    rotates the first joint so that chain is +Y. +90° about Z: ``(x,y,z) -> (-y,x,z)``.
    """
    return (-y, x, z)


def local_softcv3(trans: tuple[float, float, float], rot: tuple[int, int, int]) -> Mat4:
    """Identity then Matrix_softcv3_mult(trans, rot)."""
    m = Mat4.identity()
    rx, ry, rz = rot
    px, py, pz = trans
    # Translate
    for row in range(4):
        m.m[row][3] += m.m[row][0] * px + m.m[row][1] * py + m.m[row][2] * pz
    # Rz
    s, c = sin_s(rz), cos_s(rz)
    for row in range(4):
        x0, y0 = m.m[row][0], m.m[row][1]
        m.m[row][0] = x0 * c + y0 * s
        m.m[row][1] = -x0 * s + y0 * c
    if ry:
        s, c = sin_s(ry), cos_s(ry)
        for row in range(4):
            x0, z0 = m.m[row][0], m.m[row][2]
            m.m[row][0] = x0 * c - z0 * s
            m.m[row][2] = x0 * s + z0 * c
    if rx:
        s, c = sin_s(rx), cos_s(rx)
        for row in range(4):
            y0, z0 = m.m[row][1], m.m[row][2]
            m.m[row][1] = y0 * c + z0 * s
            m.m[row][2] = -y0 * s + z0 * c
    return m
