"""Wczytywanie / zapis obrazów jako jednokanałowa macierz uint8."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image


def load_gray(path: str | Path) -> np.ndarray:
    """Wczytaj obraz i zredukuj do luminancji Y (uint8, shape HxW)."""
    img = Image.open(path)
    if img.mode != "L":
        img = img.convert("L")
    return np.asarray(img, dtype=np.uint8)


def save_gray(path: str | Path, arr: np.ndarray) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.asarray(arr, dtype=np.uint8), mode="L").save(path)


def to_y_from_rgb(rgb: np.ndarray) -> np.ndarray:
    """BT.601 luma z float RGB [0,255] → uint8."""
    r = rgb[..., 0].astype(np.float64)
    g = rgb[..., 1].astype(np.float64)
    b = rgb[..., 2].astype(np.float64)
    y = 0.299 * r + 0.587 * g + 0.114 * b
    return np.clip(np.rint(y), 0, 255).astype(np.uint8)
