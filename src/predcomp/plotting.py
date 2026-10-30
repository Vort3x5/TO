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
    fig.savefig(out_path, dpi=120)
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

    fig, ax = plt.subplots(figsize=(12, max(4, 0.25 * len(rows))))
    y = np.arange(len(rows))
    ax.barh(y - 0.2, ent, height=0.4, label="entropia reszt", color="#0f766e")
    ax.barh(y + 0.2, huff, height=0.4, label="Huffman [bit/pix]", color="#b45309")
    ax.axvline(orig_ent, color="#334155", linestyle="--", label="entropia oryginału")
    ax.set_yticks(y)
    ax.set_yticklabels(names)
    ax.set_xlabel("bity / piksel")
    ax.set_title(f"Efektywność predykcji — {image_name}")
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
