"""CLI: samples / list / run / benchmark / verify / summarize / lpc2d."""

from __future__ import annotations

import argparse
import csv
import sys
import time
from collections import defaultdict
from pathlib import Path

import numpy as np

from .codec import encode_with, verify_lossless
from .fetch_data import fetch_real_samples
from .huffman import codebook_overhead_bits
from .image_io import load_gray, save_gray
from .lpc2d import encode_lpc2d
from .plotting import (
    plot_benchmark_bars,
    plot_histogram,
    plot_lpc2d_tradeoff,
    plot_lpc_sweep,
)
from .predictors import all_predictors, get_predictor
from .samples import generate_samples
from .stats import analyze, wrap_residuals_mod256


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
    print(f"zapisano {len(paths)} obrazów: {out}")
    for p in paths:
        print(f"  {p.name}")
    return 0


def cmd_fetch_data(args: argparse.Namespace) -> int:
    paths = fetch_real_samples(args.out, max_side=args.max_side, force=args.force)
    print(f"gotowe: {len(paths)} obrazów: {args.out}")
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
            "med",
            "paeth",
            "lpc_row_o1_b16",
            "lpc_row_o2_b16",
            "lpc_row_o3_b32",
            "lpc_col_o2_b16",
            "selector_b8",
        ]
    if name == "lpc_row":
        names = []
        for order in (1, 2, 3):
            for block in (8, 16, 32, 64):
                names.append(f"lpc_row_o{order}_b{block}")
        return names
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
    print(
        f"oryginał:   H={orig.entropy:.4f}  "
        f"E/pix={orig.energy_per_pix:.1f}  E_c/pix={orig.centered_energy_per_pix:.1f}"
    )
    print(
        f"reszty:     H={res.entropy:.4f}  E/pix={res.energy_per_pix:.1f}  "
        f"MAE={res.mean_abs:.4f}"
    )
    print(
        f"Huffman:    avg={res.huffman.avg_bits:.4f} bit/pix  "
        f"(Δ vs H = {res.huffman.avg_bits - res.entropy:+.4f}, "
        f"|alfabet|={res.huffman.codebook_size})"
    )
    if args.mod256:
        w = analyze(wrap_residuals_mod256(residuals))
        print(f"reszty mod256: H={w.entropy:.4f}  Huff={w.huffman.avg_bits:.4f}")
    if args.show_codes:
        # najczęstsze symbole
        flat = residuals.ravel()
        vals, counts = np.unique(flat, return_counts=True)
        order = np.argsort(-counts)[: args.show_codes]
        print("fragment książki kodowej (najczęstsze symbole):")
        for i in order:
            v = int(vals[i])
            print(
                f"  e={v:+4d}  count={int(counts[i]):7d}  "
                f"len={res.huffman.code_lengths[v]}  code={res.huffman.codes[v]}"
            )
        oh = codebook_overhead_bits(res.huffman.codebook_size)
        print(
            f"  szacunek narzutu tabeli: ~{oh} bit "
            f"({oh / flat.size:.4f} bit/pix przy |C|={res.huffman.codebook_size})"
        )
    if args.hist_out:
        plot_histogram(img, residuals, args.hist_out, f"{Path(args.image).stem} / {pred.name}")
        print(f"histogram:  {args.hist_out}")
    if args.residuals_out:
        vis = np.clip(residuals.astype(np.int32) + 128, 0, 255).astype(np.uint8)
        save_gray(args.residuals_out, vis)
        print(f"reszty jako obraz: {args.residuals_out}")
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
        print(f"generuję próbki syntetyczne: {synth}")
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
        "original_centered_energy_pp",
        "residual_entropy",
        "residual_energy",
        "residual_energy_pp",
        "residual_mae",
        "huffman_avg_bits",
        "huffman_minus_entropy",
        "seconds",
    ]

    rows: list[dict] = []
    for img_path in images:
        img = load_gray(img_path)
        orig = analyze(img)
        print(f"\n=== {img_path.name}  H0={orig.entropy:.4f} ===")
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
                "original_centered_energy_pp": f"{orig.centered_energy_per_pix:.4f}",
                "residual_entropy": f"{res.entropy:.6f}",
                "residual_energy": f"{res.energy:.1f}",
                "residual_energy_pp": f"{res.energy_per_pix:.4f}",
                "residual_mae": f"{res.mean_abs:.6f}",
                "huffman_avg_bits": f"{res.huffman.avg_bits:.6f}",
                "huffman_minus_entropy": f"{res.huffman.avg_bits - res.entropy:.6f}",
                "seconds": f"{dt:.4f}",
            }
            rows.append(row)
            print(
                f"  {pname:24s}  H={res.entropy:6.3f}  "
                f"Huff={res.huffman.avg_bits:6.3f}  "
                f"E/pix={res.energy_per_pix:8.1f}  {dt:.2f}s"
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
    print(f"\nCSV: {csv_path}")

    plots_dir = out_dir / "plots"
    plots_dir.mkdir(exist_ok=True)
    for img_path in images:
        plot_benchmark_bars(csv_path, plots_dir / f"{img_path.stem}_bars.png", img_path.stem)
        if args.predictors in ("lpc_row", "all") or "lpc_row" in args.predictors:
            plot_lpc_sweep(csv_path, plots_dir / f"{img_path.stem}_lpc_sweep.png", img_path.stem)
    print(f"wykresy: {plots_dir}")

    if args.summarize:
        _write_summaries(csv_path, out_dir)
    return 0


def _write_summaries(csv_path: Path, out_dir: Path) -> None:
    rows = list(csv.DictReader(csv_path.open()))
    for r in rows:
        r["H"] = float(r["residual_entropy"])
        r["Huff"] = float(r["huffman_avg_bits"])
        r["H0"] = float(r["original_entropy"])
        r["d"] = float(r["huffman_minus_entropy"])

    by_img: dict[str, list] = defaultdict(list)
    for r in rows:
        by_img[r["image"]].append(r)

    best_path = out_dir / "best_per_image.csv"
    with best_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["image", "H0", "best", "H", "Huff", "delta", "residual_energy_pp"])
        for img, rs in sorted(by_img.items()):
            best = min(rs, key=lambda x: x["H"])
            epp = best.get("residual_energy_pp", "")
            w.writerow(
                [
                    img,
                    f"{best['H0']:.3f}",
                    best["predictor"],
                    f"{best['H']:.3f}",
                    f"{best['Huff']:.3f}",
                    f"{best['d']:+.3f}",
                    epp,
                ]
            )

    by_pred: dict[str, list] = defaultdict(list)
    for r in rows:
        by_pred[r["predictor"]].append(r)
    mean_path = out_dir / "mean_by_predictor.csv"
    stats = []
    for p, rs in by_pred.items():
        mean_h = sum(x["H"] for x in rs) / len(rs)
        mean_hf = sum(x["Huff"] for x in rs) / len(rs)
        mean_d = sum(x["d"] for x in rs) / len(rs)
        wins = sum(
            1
            for irs in by_img.values()
            if min(irs, key=lambda x: x["H"])["predictor"] == p
        )
        stats.append((mean_h, p, mean_hf, mean_d, wins))
    stats.sort()
    with mean_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["predictor", "mean_H", "mean_Huff", "mean_delta", "wins"])
        for mean_h, p, mean_hf, mean_d, wins in stats:
            w.writerow([p, f"{mean_h:.3f}", f"{mean_hf:.3f}", f"{mean_d:+.3f}", wins])
    print(f"podsumowania: {best_path}, {mean_path}")


def cmd_summarize(args: argparse.Namespace) -> int:
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print("brak pliku", csv_path, file=sys.stderr)
        return 1
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    _write_summaries(csv_path, out_dir)
    return 0


def cmd_lpc2d(args: argparse.Namespace) -> int:
    img = load_gray(args.image)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    blocks = [int(b) for b in args.blocks.split(",") if b.strip()]
    csv_path = out_dir / "lpc2d.csv"
    fieldnames = [
        "image",
        "block",
        "residual_entropy",
        "huffman_avg_bits",
        "sideinfo_bpp",
        "total_bpp",
        "n_blocks",
    ]
    rows = []
    stem = Path(args.image).stem
    print(f"LPC 2D na {args.image}  shape={img.shape}")
    for b in blocks:
        r = encode_lpc2d(img, block=b, coeff_bits=args.coeff_bits)
        row = {
            "image": stem,
            "block": b,
            "residual_entropy": f"{r.residual_entropy:.6f}",
            "huffman_avg_bits": f"{r.huffman_avg_bits:.6f}",
            "sideinfo_bpp": f"{r.sideinfo_bits_per_pix:.6f}",
            "total_bpp": f"{r.total_bits_per_pix:.6f}",
            "n_blocks": r.n_blocks,
        }
        rows.append(row)
        print(
            f"  B={b:3d}  H={r.residual_entropy:.3f}  "
            f"side={r.sideinfo_bits_per_pix:.3f}  "
            f"suma={r.total_bits_per_pix:.3f}"
        )
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    plot_path = out_dir / "plots" / f"{stem}_lpc2d.png"
    plot_lpc2d_tradeoff(csv_path, plot_path)
    print(f"CSV: {csv_path}")
    print(f"wykres: {plot_path}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    img = load_gray(args.image)
    names = _predictor_subset(args.predictors)
    crop = None
    if args.crop:
        ch, cw = (int(x) for x in args.crop.split("x"))
        crop = (ch, cw)
        print(f"wycinek: {ch}x{cw}, full_decode={args.full_decode}")
    failed = 0
    for pname in names:
        ok = verify_lossless(img, pname, full_decode=args.full_decode, crop=crop)
        status = "OK" if ok else "FAIL"
        print(f"{status:4s}  {pname}")
        if not ok:
            failed += 1
    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    root = _default_root()
    p = argparse.ArgumentParser(
        prog="predcomp",
        description="Kompresja obrazu: kodowanie różnicowe/predykcyjne (TO)",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("samples", help="wygeneruj syntetyczny zbiór testowy")
    s.add_argument("--out", default=str(root / "data" / "samples"))
    s.add_argument("--size", type=int, default=128)
    s.set_defaults(func=cmd_samples)

    s = sub.add_parser("fetch-data", help="pobierz Kodak + Wikimedia: data/real")
    s.add_argument("--out", default=str(root / "data" / "real"))
    s.add_argument("--max-side", type=int, default=512, help="dłuższy bok PNG w skali szarości")
    s.add_argument("--force", action="store_true", help="pobierz ponownie mimo istniejących plików")
    s.set_defaults(func=cmd_fetch_data)

    s = sub.add_parser("list", help="lista trybów predykcji")
    s.set_defaults(func=cmd_list)

    s = sub.add_parser("run", help="jeden obraz × jeden predyktor")
    s.add_argument("image")
    s.add_argument("--predictor", default="planar")
    s.add_argument("--hist-out", default=None)
    s.add_argument("--residuals-out", default=None)
    s.add_argument("--mod256", action="store_true", help="podaj też entropię reszt mod 256")
    s.add_argument(
        "--show-codes",
        type=int,
        default=0,
        metavar="N",
        help="pokaż N najczęstszych słów kodowych Huffmana",
    )
    s.set_defaults(func=cmd_run)

    s = sub.add_parser("benchmark", help="wszystkie obrazy × zestaw predyktorów: CSV/wykresy")
    s.add_argument(
        "--data",
        default=str(root / "data"),
        help="katalog z PNG (rekurencyjnie; domyślnie data/ = samples+real)",
    )
    s.add_argument("--out", default=str(root / "results"))
    s.add_argument(
        "--predictors",
        default="quick",
        help="quick | all | lpc_row | name1,name2,...",
    )
    s.add_argument("--size", type=int, default=128)
    s.add_argument("--generate-samples", action="store_true")
    s.add_argument("--histograms", action="store_true", help="zapisuj histogramy dla każdej pary")
    s.add_argument(
        "--summarize",
        action="store_true",
        help="dopisz best_per_image.csv i mean_by_predictor.csv",
    )
    s.set_defaults(func=cmd_benchmark)

    s = sub.add_parser("summarize", help="z benchmark.csv zrób best_per_image / mean_by_predictor")
    s.add_argument("--csv", default=str(root / "results" / "benchmark.csv"))
    s.add_argument("--out", default=str(root / "results"))
    s.set_defaults(func=cmd_summarize)

    s = sub.add_parser("lpc2d", help="LPC 2D z side-info (kompromis blok vs narzut)")
    s.add_argument("image")
    s.add_argument("--blocks", default="8,16,32,64")
    s.add_argument("--coeff-bits", type=int, default=10)
    s.add_argument("--out", default=str(root / "results"))
    s.set_defaults(func=cmd_lpc2d)

    s = sub.add_parser("verify", help="przyczynowość (+ opcjonalnie pełne decode)")
    s.add_argument("image")
    s.add_argument("--predictors", default="quick")
    s.add_argument(
        "--full-decode",
        action="store_true",
        help="sekwencyjne decode (wolne; używaj z --crop)",
    )
    s.add_argument(
        "--crop",
        default=None,
        help="wycinek HxW do full-decode, np. 24x40",
    )
    s.set_defaults(func=cmd_verify)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
