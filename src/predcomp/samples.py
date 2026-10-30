"""Syntetyczny zestaw testowy o różnej charakterystyce."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def _gradient_h(size: int = 128) -> np.ndarray:
    x = np.linspace(0, 255, size, dtype=np.float64)
    return np.tile(x, (size, 1)).astype(np.uint8)


def _gradient_v(size: int = 128) -> np.ndarray:
    return _gradient_h(size).T


def _checker(size: int = 128, cell: int = 8) -> np.ndarray:
    yy, xx = np.indices((size, size))
    return (((xx // cell) + (yy // cell)) % 2 * 255).astype(np.uint8)


def _smooth_blobs(size: int = 128, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    img = Image.new("L", (size, size), 128)
    draw = ImageDraw.Draw(img)
    for _ in range(12):
        x0, y0 = rng.integers(0, size, size=2)
        r = int(rng.integers(10, 40))
        shade = int(rng.integers(30, 230))
        draw.ellipse((x0 - r, y0 - r, x0 + r, y0 + r), fill=shade)
    img = img.filter(ImageFilter.GaussianBlur(radius=3))
    return np.asarray(img, dtype=np.uint8)


def _edges(size: int = 128) -> np.ndarray:
    img = np.full((size, size), 40, dtype=np.uint8)
    img[:, size // 3 : 2 * size // 3] = 200
    img[size // 2 :, :] = np.minimum(img[size // 2 :, :] + 40, 255)
    # skośna krawędź
    for y in range(size):
        x = int(y * 0.7) % size
        img[y, x : x + 3] = 255
    return img


def _noise(size: int = 128, seed: int = 1) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return rng.integers(0, 256, size=(size, size), dtype=np.uint8)


def _naturalish(size: int = 128, seed: int = 2) -> np.ndarray:
    """Szum 1/f-ish + blur — przybliżenie zdjęcia naturalnego bez zewnętrznych plików."""
    rng = np.random.default_rng(seed)
    spectrum = rng.normal(size=(size, size)) + 1j * rng.normal(size=(size, size))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    freq = np.sqrt(fx * fx + fy * fy)
    freq[0, 0] = 1.0
    spectrum /= freq
    field = np.real(np.fft.ifft2(spectrum))
    field -= field.min()
    field /= max(field.max(), 1e-12)
    img = (field * 255).astype(np.uint8)
    return np.asarray(Image.fromarray(img).filter(ImageFilter.GaussianBlur(radius=0.8)), dtype=np.uint8)


SAMPLE_BUILDERS = {
    "gradient_h": _gradient_h,
    "gradient_v": _gradient_v,
    "checker": _checker,
    "smooth_blobs": _smooth_blobs,
    "edges": _edges,
    "noise": _noise,
    "naturalish": _naturalish,
}


def generate_samples(out_dir: str | Path, size: int = 128) -> list[Path]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for name, builder in SAMPLE_BUILDERS.items():
        path = out / f"{name}.png"
        Image.fromarray(builder(size), mode="L").save(path)
        paths.append(path)
    return paths
