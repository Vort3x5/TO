"""CLI: samples / list / run / benchmark / verify."""

from __future__ import annotations

import argparse
import csv
import sys
import time
from pathlib import Path

import numpy as np

from .codec import encode_with, verify_lossless
from .image_io import load_gray, save_gray
from .plotting import plot_benchmark_bars, plot_histogram
from .predictors import all_predictors, get_predictor
from .fetch_data import fetch_real_samples
from .samples import generate_samples
from .stats import analyze


def _default_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _collect_images(data_dir: Path) -> list[Path]:
    """PNG w katalogu i podkatalogach, bez `_raw`."""
    return sorted(
        p for p in data_dir.rglob("*.png") if "_raw" not in p.parts and p.is_file()
    )


def cmd_samples(args: argparse.Namespace) -> int:
    out = Path(args.out)
    paths = generate_samples(out, size=args.size)
    print(f"zapisano {len(paths)} obrazów → {out}")
    for p in paths:
        print(f"  {p.name}")
    return 0


def cmd_fetch_data(args: argparse.Namespace) -> int:
    paths = fetch_real_samples(args.out, max_side=args.max_side, force=args.force)
    print(f"gotowe: {len(paths)} obrazów → {args.out}")
    return 0 if paths else 1


def cmd_list(_args: argparse.Namespace) -> int:
    for p in all_predictors():
        print(f"{p.name:24s}  {p.description}")
    return 0


def _predictor_subset(name: str) -> list[str]:
    if name == "all":
        return [p.name for p in all_predictors()]
    if name == "quick":
        return [
            "left",
            "above",
            "two_left",
            "three_left",
            "avg2",
            "avg3",
            "planar",
            "weighted",
            "quadratic_row",
            "median",
            "paeth",
            "lpc_row_o1_b16",
            "lpc_row_o2_b16",
            "lpc_row_o3_b32",
            "lpc_col_o2_b16",
            "selector_b8",
        ]
    return [n.strip() for n in name.split(",") if n.strip()]


def cmd_run(args: argparse.Namespace) -> int:
    img = load_gray(args.image)
    pred = get_predictor(args.predictor)
    t0 = time.perf_counter()
    residuals, _ = encode_with(img, pred)
    dt = time.perf_counter() - t0
    orig = analyze(img)
    res = analyze(residuals)
    print(f"obraz:      {args.image}  shape={img.shape}")
    print(f"predyktor:  {pred.name}  ({pred.description})")
    print(f"czas:       {dt:.3f}s")
    print(f"oryginał:   entropia={orig.entropy:.4f}  energia={orig.energy:.1f}")
    print(
        f"reszty:     entropia={res.entropy:.4f}  energia={res.energy:.1f}  "
        f"MAE={res.mean_abs:.4f}"
    )
    print(
        f"Huffman:    avg={res.huffman.avg_bits:.4f} bit/pix  "
        f"(Δ vs entropia = {res.huffman.avg_bits - res.entropy:+.4f})"
    )
    if args.hist_out:
        plot_histogram(img, residuals, args.hist_out, f"{Path(args.image).stem} / {pred.name}")
        print(f"histogram:  {args.hist_out}")
    if args.residuals_out:
        vis = np.clip(residuals.astype(np.int32) + 128, 0, 255).astype(np.uint8)
        save_gray(args.residuals_out, vis)
        print(f"reszty→img: {args.residuals_out}")
    return 0


def cmd_benchmark(args: argparse.Namespace) -> int:
    data_dir = Path(args.data)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    hist_dir = out_dir / "histograms"
    hist_dir.mkdir(exist_ok=True)

    images = _collect_images(data_dir) if data_dir.exists() else []
    if args.generate_samples or not images:
        synth = data_dir / "samples" if data_dir.name == "data" else data_dir
        print(f"generuję próbki syntetyczne → {synth}")
        generate_samples(synth, size=args.size)
        images = _collect_images(data_dir)

    if not images:
        print("brak obrazów w", data_dir, file=sys.stderr)
        return 1
    print(f"obrazy ({len(images)}): " + ", ".join(p.name for p in images))

    names = _predictor_subset(args.predictors)
    csv_path = out_dir / "benchmark.csv"
    fieldnames = [
        "image",
        "predictor",
        "original_entropy",
        "residual_entropy",
        "residual_energy",
        "residual_mae",
        "huffman_avg_bits",
        "huffman_minus_entropy",
        "seconds",
    ]

    rows: list[dict] = []
    for img_path in images:
        img = load_gray(img_path)
        orig = analyze(img)
        print(f"\n=== {img_path.name}  entropia_oryg={orig.entropy:.4f} ===")
        for pname in names:
            pred = get_predictor(pname)
            t0 = time.perf_counter()
            residuals, _ = encode_with(img, pred)
            dt = time.perf_counter() - t0
            res = analyze(residuals)
            row = {
                "image": img_path.stem,
                "predictor": pname,
                "original_entropy": f"{orig.entropy:.6f}",
                "residual_entropy": f"{res.entropy:.6f}",
                "residual_energy": f"{res.energy:.1f}",
                "residual_mae": f"{res.mean_abs:.6f}",
                "huffman_avg_bits": f"{res.huffman.avg_bits:.6f}",
                "huffman_minus_entropy": f"{res.huffman.avg_bits - res.entropy:.6f}",
                "seconds": f"{dt:.4f}",
            }
            rows.append(row)
            print(
                f"  {pname:24s}  H={res.entropy:6.3f}  "
                f"Huff={res.huffman.avg_bits:6.3f}  E={res.energy:12.1f}  {dt:.2f}s"
            )
            if args.histograms:
                plot_histogram(
                    img,
                    residuals,
                    hist_dir / f"{img_path.stem}__{pname}.png",
                    f"{img_path.stem} / {pname}",
                )

    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"\nCSV → {csv_path}")

    plots_dir = out_dir / "plots"
    plots_dir.mkdir(exist_ok=True)
    for img_path in images:
        plot_benchmark_bars(csv_path, plots_dir / f"{img_path.stem}_bars.png", img_path.stem)
    print(f"wykresy → {plots_dir}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    img = load_gray(args.image)
    names = _predictor_subset(args.predictors)
    failed = 0
    for pname in names:
        ok = verify_lossless(img, pname, full_decode=args.full_decode)
        status = "OK" if ok else "FAIL"
        print(f"{status:4s}  {pname}")
        if not ok:
            failed += 1
    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    root = _default_root()
    p = argparse.ArgumentParser(
        prog="predcomp",
        description="Kompresja obrazu — kodowanie różnicowe/predykcyjne (TO)",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("samples", help="wygeneruj syntetyczny zbiór testowy")
    s.add_argument("--out", default=str(root / "data" / "samples"))
    s.add_argument("--size", type=int, default=128)
    s.set_defaults(func=cmd_samples)

    s = sub.add_parser("fetch-data", help="pobierz Kodak + Wikimedia → data/real")
    s.add_argument("--out", default=str(root / "data" / "real"))
    s.add_argument("--max-side", type=int, default=512, help="dłuższy bok grayscale PNG")
    s.add_argument("--force", action="store_true", help="pobierz ponownie mimo istniejących plików")
    s.set_defaults(func=cmd_fetch_data)

    s = sub.add_parser("list", help="lista trybów predykcji")
    s.set_defaults(func=cmd_list)

    s = sub.add_parser("run", help="jeden obraz × jeden predyktor")
    s.add_argument("image")
    s.add_argument("--predictor", default="planar")
    s.add_argument("--hist-out", default=None)
    s.add_argument("--residuals-out", default=None)
    s.set_defaults(func=cmd_run)

    s = sub.add_parser("benchmark", help="wszystkie obrazy × zestaw predyktorów → CSV/wykresy")
    s.add_argument(
        "--data",
        default=str(root / "data"),
        help="katalog z PNG (rekurencyjnie; domyślnie data/ = samples+real)",
    )
    s.add_argument("--out", default=str(root / "results"))
    s.add_argument("--predictors", default="quick", help="quick | all | name1,name2,...")
    s.add_argument("--size", type=int, default=128)
    s.add_argument("--generate-samples", action="store_true")
    s.add_argument("--histograms", action="store_true", help="zapisuj histogramy dla każdej pary")
    s.set_defaults(func=cmd_benchmark)

    s = sub.add_parser("verify", help="sprawdź bezstratność (encode + przyczynowość)")
    s.add_argument("image")
    s.add_argument("--predictors", default="quick")
    s.add_argument(
        "--full-decode",
        action="store_true",
        help="dodatkowo wolne sekwencyjne decode (O(H·W) map)",
    )
    s.set_defaults(func=cmd_verify)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
