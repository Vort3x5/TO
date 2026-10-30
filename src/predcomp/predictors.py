"""Tryby predykcji — każdy zwraca pełną mapę predykcji (przyczynową w.r.t. raster)."""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Callable

import numpy as np

PredictMap = Callable[[np.ndarray], np.ndarray]


def _neighbors(img: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """A=lewy, B=górny, C=górny-lewy; brakujący sąsiad = 0."""
    imgf = img.astype(np.float64, copy=False)
    a = np.zeros_like(imgf)
    b = np.zeros_like(imgf)
    c = np.zeros_like(imgf)
    a[:, 1:] = imgf[:, :-1]
    b[1:, :] = imgf[:-1, :]
    c[1:, 1:] = imgf[:-1, :-1]
    return a, b, c


def pred_left(img: np.ndarray) -> np.ndarray:
    a, _, _ = _neighbors(img)
    return a


def pred_above(img: np.ndarray) -> np.ndarray:
    _, b, _ = _neighbors(img)
    return b


def pred_avg2(img: np.ndarray) -> np.ndarray:
    a, b, _ = _neighbors(img)
    return 0.5 * (a + b)


def pred_avg3(img: np.ndarray) -> np.ndarray:
    a, b, c = _neighbors(img)
    return (a + b + c) / 3.0


def pred_planar(img: np.ndarray) -> np.ndarray:
    a, b, c = _neighbors(img)
    return a + b - c


def pred_weighted(img: np.ndarray) -> np.ndarray:
    a, b, _ = _neighbors(img)
    return 0.75 * a + 0.25 * b


def pred_median(img: np.ndarray) -> np.ndarray:
    """Mediana trzech wartości: suma − min − max (bez sortowania)."""
    a, b, c = _neighbors(img)
    amin = np.minimum(np.minimum(a, b), c)
    amax = np.maximum(np.maximum(a, b), c)
    return a + b + c - amin - amax


def pred_paeth(img: np.ndarray) -> np.ndarray:
    a, b, c = _neighbors(img)
    p = a + b - c
    da, db, dc = np.abs(p - a), np.abs(p - b), np.abs(p - c)
    out = np.where((da <= db) & (da <= dc), a, np.where(db <= dc, b, c))
    return out


def pred_two_left(img: np.ndarray) -> np.ndarray:
    imgf = img.astype(np.float64, copy=False)
    out = np.zeros_like(imgf)
    out[:, 1] = imgf[:, 0]
    out[:, 2:] = 0.5 * (imgf[:, 1:-1] + imgf[:, :-2])
    return out


def pred_three_left(img: np.ndarray) -> np.ndarray:
    imgf = img.astype(np.float64, copy=False)
    out = np.zeros_like(imgf)
    out[:, 1] = imgf[:, 0]
    out[:, 2] = 0.5 * (imgf[:, 1] + imgf[:, 0])
    out[:, 3:] = (imgf[:, 2:-1] + imgf[:, 1:-2] + imgf[:, :-3]) / 3.0
    return out


def pred_two_above(img: np.ndarray) -> np.ndarray:
    imgf = img.astype(np.float64, copy=False)
    out = np.zeros_like(imgf)
    out[1, :] = imgf[0, :]
    out[2:, :] = 0.5 * (imgf[1:-1, :] + imgf[:-2, :])
    return out


def pred_quadratic_row(img: np.ndarray) -> np.ndarray:
    """Ekstrapolacja: 3·A − 3·A₂ + A₃ (dla x≥3); wcześniej left / liniowa."""
    imgf = img.astype(np.float64, copy=False)
    out = np.zeros_like(imgf)
    out[:, 1] = imgf[:, 0]
    out[:, 2] = 2.0 * imgf[:, 1] - imgf[:, 0]
    out[:, 3:] = 3.0 * imgf[:, 2:-1] - 3.0 * imgf[:, 1:-2] + imgf[:, :-3]
    return out


def _fit_lpc(samples: np.ndarray, order: int) -> np.ndarray | None:
    n = samples.size
    if n <= order or order < 1:
        return None
    y = samples[order:]
    x = np.column_stack([samples[order - 1 - k : n - 1 - k] for k in range(order)])
    try:
        coeffs, *_ = np.linalg.lstsq(x, y, rcond=None)
    except np.linalg.LinAlgError:
        return None
    return coeffs


def _lpc_line(line: np.ndarray, order: int, block: int) -> np.ndarray:
    """LPC wzdłuż 1D: współczynniki stałe w segmencie `block`, z poprzedniego okna."""
    n = line.size
    out = np.zeros(n, dtype=np.float64)
    for seg_start in range(0, n, block):
        seg_end = min(seg_start + block, n)
        if seg_start == 0:
            coeffs = None
        else:
            hist = line[:seg_start]
            window = hist[-block:] if hist.size > block else hist
            coeffs = _fit_lpc(window, order)

        if coeffs is None:
            if seg_start < seg_end and seg_start > 0:
                out[seg_start:seg_end] = line[seg_start - 1 : seg_end - 1]
            continue

        # początek segmentu / rząd: za mało historii → left
        i0 = seg_start
        while i0 < seg_end and i0 < order:
            if i0 > 0:
                out[i0] = line[i0 - 1]
            i0 += 1
        if i0 >= seg_end:
            continue

        # stałe współczynniki → splot z historią (zwektoryzowany dla małych rzędów)
        a = coeffs
        if order == 1:
            out[i0:seg_end] = a[0] * line[i0 - 1 : seg_end - 1]
        elif order == 2:
            out[i0:seg_end] = a[0] * line[i0 - 1 : seg_end - 1] + a[1] * line[i0 - 2 : seg_end - 2]
        elif order == 3:
            out[i0:seg_end] = (
                a[0] * line[i0 - 1 : seg_end - 1]
                + a[1] * line[i0 - 2 : seg_end - 2]
                + a[2] * line[i0 - 3 : seg_end - 3]
            )
        else:
            for i in range(i0, seg_end):
                out[i] = float(a @ line[i - order : i][::-1])
    return out


def make_lpc_row(order: int, block: int) -> PredictMap:
    def predict(img: np.ndarray) -> np.ndarray:
        imgf = img.astype(np.float64, copy=False)
        h, w = imgf.shape
        out = np.empty_like(imgf)
        for y in range(h):
            out[y] = _lpc_line(imgf[y], order, block)
            # x=0: fallback górny (jak wcześniej)
            if h > 0:
                out[y, 0] = imgf[y - 1, 0] if y > 0 else 0.0
        return out

    predict.__name__ = f"lpc_row_o{order}_b{block}"
    return predict


def make_lpc_col(order: int, block: int) -> PredictMap:
    def predict(img: np.ndarray) -> np.ndarray:
        imgf = img.astype(np.float64, copy=False)
        # kolumny = LPC na wierszach transpozycji, potem fallback lewy na y=0
        out_t = np.empty_like(imgf.T)
        for x, col in enumerate(imgf.T):
            out_t[x] = _lpc_line(col, order, block)
        out = out_t.T
        out[0, 1:] = imgf[0, :-1]
        out[0, 0] = 0.0
        return out

    predict.__name__ = f"lpc_col_o{order}_b{block}"
    return predict


def make_selector(block: int = 8) -> PredictMap:
    """W bloku wybierz {left, above, planar} wg energii na ramce przyczynowej."""

    def predict(img: np.ndarray) -> np.ndarray:
        maps = (pred_left(img), pred_above(img), pred_planar(img))
        imgf = img.astype(np.float64, copy=False)
        h, w = imgf.shape
        out = np.empty_like(imgf)
        for by in range(0, h, block):
            for bx in range(0, w, block):
                y1, x1 = min(by + block, h), min(bx + block, w)
                best_i, best_e = 0, float("inf")
                for i, m in enumerate(maps):
                    energy = 0.0
                    if by > 0:
                        yy = by - 1
                        d = imgf[yy, bx:x1] - m[yy, bx:x1]
                        energy += float(np.dot(d, d))
                        if bx > 0:
                            d = imgf[max(0, by - block) : by, bx - 1] - m[max(0, by - block) : by, bx - 1]
                            energy += float(np.dot(d, d))
                    if bx > 0:
                        d = imgf[by, max(0, bx - block) : bx] - m[by, max(0, bx - block) : bx]
                        energy += float(np.dot(d, d))
                    if energy < best_e:
                        best_e = energy
                        best_i = i
                out[by:y1, bx:x1] = maps[best_i][by:y1, bx:x1]
        return out

    predict.__name__ = f"selector_b{block}"
    return predict


@dataclass(frozen=True)
class Predictor:
    name: str
    fn: PredictMap
    description: str


def _build_registry() -> dict[str, Predictor]:
    items = [
        Predictor("left", pred_left, "1 sąsiad: lewy (A)"),
        Predictor("above", pred_above, "1 sąsiad: górny (B)"),
        Predictor("two_left", pred_two_left, "2 piksele w wierszu (średnia)"),
        Predictor("three_left", pred_three_left, "3 piksele w wierszu (średnia)"),
        Predictor("two_above", pred_two_above, "2 piksele w kolumnie (średnia)"),
        Predictor("avg2", pred_avg2, "średnia (A+B)/2"),
        Predictor("avg3", pred_avg3, "średnia (A+B+C)/3"),
        Predictor("planar", pred_planar, "planar A+B-C"),
        Predictor("weighted", pred_weighted, "0.75A + 0.25B"),
        Predictor("quadratic_row", pred_quadratic_row, "ekstrapolacja kwadratowa w wierszu"),
        Predictor("median", pred_median, "mediana(A,B,C)"),
        Predictor("paeth", pred_paeth, "Paeth (PNG)"),
    ]
    for order in (1, 2, 3):
        for block in (8, 16, 32, 64):
            items.append(
                Predictor(
                    f"lpc_row_o{order}_b{block}",
                    make_lpc_row(order, block),
                    f"LPC wiersz, rząd {order}, okno {block}",
                )
            )
            items.append(
                Predictor(
                    f"lpc_col_o{order}_b{block}",
                    make_lpc_col(order, block),
                    f"LPC kolumna, rząd {order}, okno {block}",
                )
            )
    items.append(
        Predictor("selector_b8", make_selector(8), "lokalny wybór {left,above,planar} w bloku 8×8")
    )
    return {p.name: p for p in items}


@lru_cache(maxsize=1)
def _registry() -> dict[str, Predictor]:
    return _build_registry()


def all_predictors() -> list[Predictor]:
    return list(_registry().values())


def get_predictor(name: str) -> Predictor:
    reg = _registry()
    if name not in reg:
        raise KeyError(f"nieznany predyktor {name!r}; dostępne: {', '.join(reg)}")
    return reg[name]
