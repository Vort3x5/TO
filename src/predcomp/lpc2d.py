"""LPC 2D w blokach: Î = αA+βB+γC+δD; 4 współczynniki × 11 bitów w side-info."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .codec import quantize_pred
from .predictors import LPC_COEFF_BITS, _neighbors, quantize_lpc_coeffs
from .stats import analyze

N_COEFFS = 4


def _neighbors4(img: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """A,B,C jak w `_neighbors`; D=górny-prawy, przy x=w-1 jest D:=B."""
    a, b, c = _neighbors(img)
    imgf = img.astype(np.float64, copy=False)
    d = np.zeros_like(imgf)
    d[1:, :-1] = imgf[:-1, 1:]
    d[:, -1] = b[:, -1]
    return a, b, c, d


def _fit_block(
    img: np.ndarray,
    a: np.ndarray,
    b: np.ndarray,
    c: np.ndarray,
    d: np.ndarray,
    y0: int,
    y1: int,
    x0: int,
    x1: int,
) -> np.ndarray:
    ys, xs = np.mgrid[y0:y1, x0:x1]
    mask = (ys > 0) & (xs > 0)
    if not np.any(mask):
        return np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
    y = img[y0:y1, x0:x1][mask].astype(np.float64)
    xmat = np.column_stack(
        [
            a[y0:y1, x0:x1][mask],
            b[y0:y1, x0:x1][mask],
            c[y0:y1, x0:x1][mask],
            d[y0:y1, x0:x1][mask],
        ]
    )
    try:
        coeffs, *_ = np.linalg.lstsq(xmat, y, rcond=None)
    except np.linalg.LinAlgError:
        return np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
    return quantize_lpc_coeffs(coeffs.astype(np.float64))


def _predict_pixel(
    recon: np.ndarray,
    y: int,
    x: int,
    coeffs: np.ndarray,
) -> float:
    """Ta sama konwencja krawędzi co `_neighbors` / left."""
    h, w = recon.shape
    if y == 0 and x == 0:
        return 0.0
    if x == 0:
        # A := B
        return float(recon[y - 1, x])
    if y == 0:
        # B := A
        return float(recon[y, x - 1])
    a = float(recon[y, x - 1])
    b = float(recon[y - 1, x])
    c = float(recon[y - 1, x - 1])
    d = float(recon[y - 1, x + 1]) if x + 1 < w else b
    aa, bb, gg, dd = coeffs
    return aa * a + bb * b + gg * c + dd * d


@dataclass(frozen=True)
class Lpc2dResult:
    residuals: np.ndarray
    residual_entropy: float
    sideinfo_bits_per_pix: float
    total_bits_per_pix: float
    n_blocks: int
    block: int
    huffman_avg_bits: float
    coeff_grid: np.ndarray  # (n_by, n_bx, 4)


def encode_lpc2d(
    image: np.ndarray,
    block: int = 16,
    *,
    coeff_bits: int = LPC_COEFF_BITS,
) -> Lpc2dResult:
    """Predykcja Î = αA+βB+γC+δD; współczynniki kwantowane i liczone w narzucie."""
    del coeff_bits  # wspólna stała LPC_COEFF_BITS w quantize_lpc_coeffs
    img = np.asarray(image, dtype=np.uint8)
    h, w = img.shape
    imgf = img.astype(np.float64)
    a, b, c, d = _neighbors4(imgf)
    n_by = (h + block - 1) // block
    n_bx = (w + block - 1) // block
    coeff_grid = np.zeros((n_by, n_bx, N_COEFFS), dtype=np.float64)
    pred = np.zeros((h, w), dtype=np.float64)
    n_blocks = 0

    for iy, by in enumerate(range(0, h, block)):
        for ix, bx in enumerate(range(0, w, block)):
            y1, x1 = min(by + block, h), min(bx + block, w)
            coeffs = _fit_block(imgf, a, b, c, d, by, y1, bx, x1)
            coeff_grid[iy, ix] = coeffs
            n_blocks += 1
            aa, bb, gg, dd = coeffs
            pred[by:y1, bx:x1] = (
                aa * a[by:y1, bx:x1]
                + bb * b[by:y1, bx:x1]
                + gg * c[by:y1, bx:x1]
                + dd * d[by:y1, bx:x1]
            )
            # krawędzie bez pełnego sąsiedztwa 2D: pierwszy wiersz = left,
            # pierwsza kolumna = above (b[0,0] i tak jest 0)
            if by == 0:
                pred[0, bx:x1] = a[0, bx:x1]
            if bx == 0:
                pred[by:y1, 0] = b[by:y1, 0]

    pred_q = quantize_pred(pred)
    residuals = img.astype(np.int16) - pred_q
    stats = analyze(residuals)
    side = (n_blocks * N_COEFFS * LPC_COEFF_BITS) / float(h * w)
    return Lpc2dResult(
        residuals=residuals,
        residual_entropy=stats.entropy,
        sideinfo_bits_per_pix=side,
        total_bits_per_pix=stats.entropy + side,
        n_blocks=n_blocks,
        block=block,
        huffman_avg_bits=stats.huffman.avg_bits,
        coeff_grid=coeff_grid,
    )


def decode_lpc2d(
    residuals: np.ndarray,
    coeff_grid: np.ndarray,
    block: int,
) -> np.ndarray:
    """Sekwencyjna rekonstrukcja z reszt i siatki współczynników."""
    res = np.asarray(residuals, dtype=np.int16)
    h, w = res.shape
    recon = np.zeros((h, w), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            iy, ix = y // block, x // block
            pred = _predict_pixel(recon.astype(np.float64), y, x, coeff_grid[iy, ix])
            pred_q = int(np.clip(np.rint(pred), 0, 255))
            val = pred_q + int(res[y, x])
            if not 0 <= val <= 255:
                raise ValueError(f"LPC2D decode poza zakresem przy ({x},{y}): {val}")
            recon[y, x] = np.uint8(val)
    return recon


def verify_lpc2d(
    image: np.ndarray,
    block: int = 16,
    *,
    crop: tuple[int, int] | None = None,
) -> bool:
    img = np.asarray(image, dtype=np.uint8)
    if crop is not None:
        ch, cw = crop
        img = img[:ch, :cw]
    enc = encode_lpc2d(img, block=block)
    decoded = decode_lpc2d(enc.residuals, enc.coeff_grid, block)
    return np.array_equal(img, decoded)
