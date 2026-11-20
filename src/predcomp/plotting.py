"""Wykresy do sprawozdania."""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def plot_histogram(
    original: np.ndarray,
    residuals: np.ndarray,
    out_path: str | Path,
    title: str,
) -> None:
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    axes[0].hist(original.ravel(), bins=256, range=(0, 255), color="#334155", alpha=0.9)
    axes[0].set_title("Oryginał")
    axes[0].set_xlabel("wartość")
    axes[0].set_ylabel("liczność")
    rmin, rmax = int(residuals.min()), int(residuals.max())
    bins = range(rmin, rmax + 2)
    axes[1].hist(residuals.ravel(), bins=bins, color="#0f766e", alpha=0.9)
    axes[1].set_title("Reszty")
    axes[1].set_xlabel("reszta")
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(out_path, dpi=140)
    plt.close(fig)


def plot_benchmark_bars(csv_path: str | Path, out_path: str | Path, image_name: str) -> None:
    """Słupki entropii reszt i średniej długości Huffmana dla jednego obrazu."""
    with Path(csv_path).open(newline="") as f:
        rows = [r for r in csv.DictReader(f) if r["image"] == image_name]
    if not rows:
        return
    rows.sort(key=lambda r: float(r["residual_entropy"]))
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    names = [r["predictor"] for r in rows]
    ent = [float(r["residual_entropy"]) for r in rows]
    huff = [float(r["huffman_avg_bits"]) for r in rows]
    orig_ent = float(rows[0]["original_entropy"])

    fig_h = max(5.0, 0.38 * len(rows) + 1.5)
    fig, ax = plt.subplots(figsize=(11, fig_h))
    y = np.arange(len(rows))
    ax.barh(y - 0.2, ent, height=0.4, label="entropia reszt", color="#0f766e")
    ax.barh(y + 0.2, huff, height=0.4, label="Huffman [bit/pix]", color="#b45309")
    ax.axvline(orig_ent, color="#334155", linestyle="--", label="entropia oryginału")
    ax.set_yticks(y)
    ax.set_yticklabels(names, fontsize=9)
    ax.set_xlabel("bity / piksel", fontsize=11)
    ax.set_title(f"Efektywność predykcji: {image_name}", fontsize=12)
    ax.legend(loc="lower right", fontsize=9)
    ax.tick_params(axis="x", labelsize=9)
    fig.tight_layout()
    fig.savefig(out_path, dpi=140)
    plt.close(fig)


def plot_lpc_sweep(csv_path: str | Path, out_path: str | Path, image_name: str) -> None:
    """Entropia reszt LPC 1D w funkcji długości bloku, osobne serie na rząd."""
    with Path(csv_path).open(newline="") as f:
        rows = [
            r
            for r in csv.DictReader(f)
            if r["image"] == image_name and r["predictor"].startswith("lpc_row_o")
        ]
    if not rows:
        return
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    by_order: dict[int, list[tuple[int, float]]] = {}
    for r in rows:
        # lpc_row_o{order}_b{block}
        parts = r["predictor"].split("_")
        order = int(parts[2][1:])
        block = int(parts[3][1:])
        by_order.setdefault(order, []).append((block, float(r["residual_entropy"])))

    fig, ax = plt.subplots(figsize=(8, 4.5))
    for order in sorted(by_order):
        pts = sorted(by_order[order])
        ax.plot(
            [b for b, _ in pts],
            [h for _, h in pts],
            marker="o",
            label=f"rząd {order}",
        )
    ax.set_xlabel("długość bloku B")
    ax.set_ylabel("entropia reszt [bit/pix]")
    ax.set_title(f"LPC 1D (wiersz) vs długość bloku: {image_name}")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_path, dpi=140)
    plt.close(fig)


def plot_lpc2d_tradeoff(csv_path: str | Path, out_path: str | Path) -> None:
    """H reszt, narzut side-info i suma vs rozmiar bloku LPC 2D."""
    with Path(csv_path).open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    rows.sort(key=lambda r: int(r["block"]))
    blocks = [int(r["block"]) for r in rows]
    h = [float(r["residual_entropy"]) for r in rows]
    side = [float(r["sideinfo_bpp"]) for r in rows]
    total = [float(r["total_bpp"]) for r in rows]

    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.plot(blocks, h, marker="o", label="H reszt")
    ax.plot(blocks, side, marker="s", label="narzut side-info")
    ax.plot(blocks, total, marker="^", label="H + narzut")
    ax.set_xlabel("rozmiar bloku")
    ax.set_ylabel("bit / piksel")
    ax.set_title("LPC 2D: kompromis dopasowanie vs narzut współczynników")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_path, dpi=140)
    plt.close(fig)
