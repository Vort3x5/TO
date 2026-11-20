"""Statyczny kod Huffmana: długości, średnia bitowa i opcjonalnie słowa kodowe."""

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
    codes: dict[int, str]


class _Node:
    __slots__ = ("freq", "symbol", "left", "right")

    def __init__(self, freq: int, symbol: int | None = None, left=None, right=None):
        self.freq = freq
        self.symbol = symbol
        self.left = left
        self.right = right

    def __lt__(self, other: "_Node") -> bool:
        return self.freq < other.freq


def _lengths_and_codes(root: _Node) -> tuple[dict[int, int], dict[int, str]]:
    lengths: dict[int, int] = {}
    codes: dict[int, str] = {}

    def walk(node: _Node, depth: int, path: str) -> None:
        if node.symbol is not None:
            lengths[node.symbol] = 1 if depth == 0 else depth
            codes[node.symbol] = path if path else "0"
            return
        walk(node.left, depth + 1, path + "0")
        walk(node.right, depth + 1, path + "1")

    walk(root, 0, "")
    return lengths, codes


def build_huffman_from_counts(values: np.ndarray, counts: np.ndarray) -> HuffmanResult:
    """values[i] ma częstość counts[i] (z np.unique(..., return_counts=True))."""
    n = int(counts.sum())
    if n == 0:
        return HuffmanResult(0.0, 0, 0, 0, {}, {})
    if values.size == 1:
        sym = int(values[0])
        return HuffmanResult(1.0, n, n, 1, {sym: 1}, {sym: "0"})

    heap = [_Node(int(c), symbol=int(v)) for v, c in zip(values.tolist(), counts.tolist())]
    heapq.heapify(heap)
    while len(heap) > 1:
        a, b = heapq.heappop(heap), heapq.heappop(heap)
        heapq.heappush(heap, _Node(a.freq + b.freq, left=a, right=b))
    lengths, codes = _lengths_and_codes(heap[0])
    total = sum(int(c) * lengths[int(v)] for v, c in zip(values.tolist(), counts.tolist()))
    return HuffmanResult(total / n, total, n, len(lengths), lengths, codes)


def build_huffman(symbols: np.ndarray) -> HuffmanResult:
    flat = np.asarray(symbols).ravel()
    if flat.size == 0:
        return HuffmanResult(0.0, 0, 0, 0, {}, {})
    values, counts = np.unique(flat, return_counts=True)
    return build_huffman_from_counts(values, counts)


def codebook_overhead_bits(codebook_size: int, *, symbol_bits: int = 9, max_len_bits: int = 5) -> int:
    """Grube oszacowanie narzutu na zapis drzewa / tabeli (symbol + długość)."""
    return codebook_size * (symbol_bits + max_len_bits)
