"""LPC 2D w blokach z sąsiadami A,B,C,D i współczynnikami jako side-info."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .codec import quantize_pred
from .stats import analyze


# A=lewy, B=górny, C=górny-lewy, D=górny-prawy (przyczynowy w rasterze)
N_COEFFS = 4
COEFF_BITS = 10  # na współczynnik (kwantyzacja stałoprzecinkowa)


def _neighbors4(img: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    imgf = img.astype(np.float64, copy=False)
    h, w = imgf.shape
    a = np.zeros_like(imgf)
    b = np.zeros_like(imgf)
    c = np.zeros_like(imgf)
    d = np.zeros_like(imgf)
    a[:, 1:] = imgf[:, :-1]
    b[1:, :] = imgf[:-1, :]
    c[1:, 1:] = imgf[:-1, :-1]
    d[1:, :-1] = imgf[:-1, 1:]
    return a, b, c, d


def _quantize_coeffs(coeffs: np.ndarray, bits: int = COEFF_BITS) -> np.ndarray:
    """Kwantyzacja współczynników do zakresu ok. [-2, 2] na `bits` bitów."""
    levels = (1 << bits) - 1
    scale = levels / 4.0  # [-2, 2] → [0, levels]
    q = np.clip(np.rint((coeffs + 2.0) * scale), 0, levels)
    return q / scale - 2.0


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
    """Estymacja [α,β,γ,δ] na pikselach bloku (encoder zna cały blok)."""
    ys, xs = np.mgrid[y0:y1, x0:x1]
    # pomijamy pierwszą kolumnę/wiersz obrazu (brak pełnych sąsiadów)
    mask = (ys > 0) & (xs > 0) & (xs < img.shape[1] - 1)
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
    return coeffs.astype(np.float64)


@dataclass(frozen=True)
class Lpc2dResult:
    residuals: np.ndarray
    residual_entropy: float
    sideinfo_bits_per_pix: float
    total_bits_per_pix: float
    n_blocks: int
    block: int
    huffman_avg_bits: float


def encode_lpc2d(
    image: np.ndarray,
    block: int = 16,
    *,
    coeff_bits: int = COEFF_BITS,
) -> Lpc2dResult:
    """Predykcja Î = αA+βB+γC+δD; współczynniki kwantowane i liczone w narzucie."""
    img = np.asarray(image, dtype=np.uint8)
    h, w = img.shape
    imgf = img.astype(np.float64)
    a, b, c, d = _neighbors4(imgf)
    pred = np.zeros((h, w), dtype=np.float64)
    n_blocks = 0

    for by in range(0, h, block):
        for bx in range(0, w, block):
            y1, x1 = min(by + block, h), min(bx + block, w)
            coeffs = _quantize_coeffs(
                _fit_block(imgf, a, b, c, d, by, y1, bx, x1),
                bits=coeff_bits,
            )
            n_blocks += 1
            aa, bb, gg, dd = coeffs
            pred[by:y1, bx:x1] = (
                aa * a[by:y1, bx:x1]
                + bb * b[by:y1, bx:x1]
                + gg * c[by:y1, bx:x1]
                + dd * d[by:y1, bx:x1]
            )
            # krawędzie bez pełnych sąsiadów: left / above
            if by == 0:
                pred[0, bx:x1] = a[0, bx:x1]
            if bx == 0:
                pred[by:y1, 0] = b[by:y1, 0] if by > 0 else 0.0
                if by == 0:
                    pred[0, 0] = 0.0

    pred_q = quantize_pred(pred)
    residuals = img.astype(np.int16) - pred_q
    stats = analyze(residuals)
    side = (n_blocks * N_COEFFS * coeff_bits) / float(h * w)
    return Lpc2dResult(
        residuals=residuals,
        residual_entropy=stats.entropy,
        sideinfo_bits_per_pix=side,
        total_bits_per_pix=stats.entropy + side,
        n_blocks=n_blocks,
        block=block,
        huffman_avg_bits=stats.huffman.avg_bits,
    )
