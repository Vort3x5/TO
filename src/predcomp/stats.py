"""Metryki: histogram, energia, entropia, Huffman — wspólne np.unique."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .huffman import HuffmanResult, build_huffman_from_counts


@dataclass(frozen=True)
class SignalStats:
    energy: float
    mean_abs: float
    entropy: float
    huffman: HuffmanResult
    histogram: np.ndarray
    hist_min: int


def analyze(arr: np.ndarray) -> SignalStats:
    flat = np.asarray(arr).ravel()
    if flat.size == 0:
        empty = HuffmanResult(0.0, 0, 0, 0, {})
        return SignalStats(0.0, 0.0, 0.0, empty, np.array([], dtype=np.int64), 0)

    a = flat.astype(np.float64, copy=False)
    values, counts = np.unique(flat, return_counts=True)
    p = counts.astype(np.float64) / flat.size
    ent = float(-np.sum(p * np.log2(p)))

    vmin = int(values[0])
    vmax = int(values[-1])
    hist = np.zeros(vmax - vmin + 1, dtype=np.int64)
    hist[(values.astype(np.int64) - vmin)] = counts

    return SignalStats(
        energy=float(np.dot(a, a)),
        mean_abs=float(np.mean(np.abs(a))),
        entropy=ent,
        huffman=build_huffman_from_counts(values, counts),
        histogram=hist,
        hist_min=vmin,
    )
