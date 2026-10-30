"""Statyczny kod Huffmana — tylko długości kodów (wystarczą do średniej bitowej)."""

from __future__ import annotations

import heapq
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class HuffmanResult:
    avg_bits: float
    total_bits: int
    n_symbols: int
    codebook_size: int
    code_lengths: dict[int, int]


class _Node:
    __slots__ = ("freq", "symbol", "left", "right")

    def __init__(self, freq: int, symbol: int | None = None, left=None, right=None):
        self.freq = freq
        self.symbol = symbol
        self.left = left
        self.right = right

    def __lt__(self, other: "_Node") -> bool:
        return self.freq < other.freq


def _lengths(root: _Node) -> dict[int, int]:
    out: dict[int, int] = {}

    def walk(node: _Node, depth: int) -> None:
        if node.symbol is not None:
            out[node.symbol] = 1 if depth == 0 else depth
            return
        walk(node.left, depth + 1)
        walk(node.right, depth + 1)

    walk(root, 0)
    return out


def build_huffman_from_counts(values: np.ndarray, counts: np.ndarray) -> HuffmanResult:
    """values[i] ma częstość counts[i] (z np.unique(..., return_counts=True))."""
    n = int(counts.sum())
    if n == 0:
        return HuffmanResult(0.0, 0, 0, 0, {})
    if values.size == 1:
        sym = int(values[0])
        return HuffmanResult(1.0, n, n, 1, {sym: 1})

    heap = [_Node(int(c), symbol=int(v)) for v, c in zip(values.tolist(), counts.tolist())]
    heapq.heapify(heap)
    while len(heap) > 1:
        a, b = heapq.heappop(heap), heapq.heappop(heap)
        heapq.heappush(heap, _Node(a.freq + b.freq, left=a, right=b))
    lengths = _lengths(heap[0])
    total = sum(int(c) * lengths[int(v)] for v, c in zip(values.tolist(), counts.tolist()))
    return HuffmanResult(total / n, total, n, len(lengths), lengths)


def build_huffman(symbols: np.ndarray) -> HuffmanResult:
    flat = np.asarray(symbols).ravel()
    if flat.size == 0:
        return HuffmanResult(0.0, 0, 0, 0, {})
    values, counts = np.unique(flat, return_counts=True)
    return build_huffman_from_counts(values, counts)
