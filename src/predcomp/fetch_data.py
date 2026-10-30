"""Pobieranie reprezentatywnego zestawu Kodak + Wikimedia → grayscale PNG."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

USER_AGENT = "TO-predcomp/0.1 (PW course project; educational use)"


@dataclass(frozen=True)
class RemoteImage:
    """Jedna pozycja katalogu testowego."""

    stem: str  # nazwa pliku bez .png
    kind: str  # kodak | wikimedia
    source: str  # URL albo tytuł pliku na Commons
    role: str  # po co jest w zestawie
    license_note: str


# Kodak Lossless True Color Image Suite — https://r0k.us/graphics/kodak/
# (Eastman Kodak, udostępnione do nieograniczonego użytku wg maintainerów zestawu)
KODAK = [
    RemoteImage(
        "kodak_kodim05",
        "kodak",
        "https://r0k.us/graphics/kodak/kodak/kodim05.png",
        "scena złożona / dużo detalu (rowery, targ)",
        "Kodak suite — unrestricted usage (r0k.us)",
    ),
    RemoteImage(
        "kodak_kodim08",
        "kodak",
        "https://r0k.us/graphics/kodak/kodak/kodim08.png",
        "architektura / ostre krawędzie i linie",
        "Kodak suite — unrestricted usage (r0k.us)",
    ),
    RemoteImage(
        "kodak_kodim13",
        "kodak",
        "https://r0k.us/graphics/kodak/kodak/kodim13.png",
        "tekstura naturalna (woda, skały)",
        "Kodak suite — unrestricted usage (r0k.us)",
    ),
    RemoteImage(
        "kodak_kodim15",
        "kodak",
        "https://r0k.us/graphics/kodak/kodak/kodim15.png",
        "portret / gładkie tony skóry + detale",
        "Kodak suite — unrestricted usage (r0k.us)",
    ),
    RemoteImage(
        "kodak_kodim19",
        "kodak",
        "https://r0k.us/graphics/kodak/kodak/kodim19.png",
        "krajobraz z dominantą (latarnia) + niebo",
        "Kodak suite — unrestricted usage (r0k.us)",
    ),
    RemoteImage(
        "kodak_kodim23",
        "kodak",
        "https://r0k.us/graphics/kodak/kodak/kodim23.png",
        "obiekt z gładkimi obszarami i krawędziami (papuga)",
        "Kodak suite — unrestricted usage (r0k.us)",
    ),
]

# Wikimedia Commons — tylko PD / CC0 (tytuły File:...)
WIKIMEDIA = [
    RemoteImage(
        "wiki_field_texture",
        "wikimedia",
        "File:Field with mixed intercropping of oat and rye.jpg",
        "tekstura pola / krajobraz rolniczy",
        "CC0",
    ),
    RemoteImage(
        "wiki_oak_foliage",
        "wikimedia",
        "File:Tree Identification - Oak- White - DPLA - 3c021a398d5a55e624c800ac787caff8.jpg",
        "listowie / drobna tekstura organiczna",
        "Public domain (PD-US)",
    ),
    RemoteImage(
        "wiki_portrait",
        "wikimedia",
        "File:Portrait of Edward A. Sutherland taken around the 1930s.jpg",
        "portret fotograficzny (historyczny)",
        "Public domain (PD-US)",
    ),
    RemoteImage(
        "wiki_manuscript",
        "wikimedia",
        "File:Manuscript page - British Library Harley 2253 f. 67.jpg",
        "tekst / ostre przejścia jasność–czerń",
        "Public domain",
    ),
    RemoteImage(
        "wiki_building",
        "wikimedia",
        "File:Monadnock Building East Facade Postcard.JPG",
        "fasada budynku / geometria pionowa",
        "Public domain",
    ),
]

CATALOG: list[RemoteImage] = KODAK + WIKIMEDIA


def _download(url: str, dest: Path, *, retries: int = 5) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    last_err: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=120) as resp, dest.open("wb") as out:
                out.write(resp.read())
            return
        except urllib.error.HTTPError as exc:
            last_err = exc
            if exc.code in (429, 503) and attempt + 1 < retries:
                time.sleep(2 ** attempt + 1)
                continue
            raise
        except urllib.error.URLError as exc:
            last_err = exc
            if attempt + 1 < retries:
                time.sleep(2 ** attempt + 1)
                continue
            raise
    raise RuntimeError(f"download failed: {url}") from last_err


def _commons_original_url(file_title: str) -> tuple[str, str]:
    """Zwraca (url, license_short) dla pliku na Commons."""
    params = urllib.parse.urlencode(
        {
            "action": "query",
            "titles": file_title,
            "prop": "imageinfo",
            "iiprop": "url|extmetadata",
            "format": "json",
        }
    )
    api = f"https://commons.wikimedia.org/w/api.php?{params}"
    req = urllib.request.Request(api, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.load(resp)
    page = next(iter(data["query"]["pages"].values()))
    info = (page.get("imageinfo") or [None])[0]
    if not info or "url" not in info:
        raise RuntimeError(f"brak URL dla {file_title!r}")
    em = info.get("extmetadata") or {}
    lic = (em.get("LicenseShortName") or {}).get("value") or "unknown"
    return info["url"], lic


def _to_gray_png(src: Path, dst: Path, max_side: int) -> tuple[int, int]:
    img = Image.open(src)
    img = img.convert("L")
    w, h = img.size
    scale = min(1.0, max_side / max(w, h))
    if scale < 1.0:
        img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst)
    return img.size


def fetch_real_samples(out_dir: str | Path, *, max_side: int = 512, force: bool = False) -> list[Path]:
    """
    Pobierz katalog Kodak+Wikimedia, zapisz grayscale PNG (max bok = max_side).
    Surowy download ląduje w out_dir/_raw/ (gitignore’owany lokalnie przez results-like).
    """
    out = Path(out_dir)
    raw = out / "_raw"
    paths: list[Path] = []

    for item in CATALOG:
        dest = out / f"{item.stem}.png"
        if dest.exists() and not force:
            paths.append(dest)
            print(f"skip  {dest.name} (już jest)")
            continue

        print(f"fetch {item.stem} …")
        try:
            if item.kind == "kodak":
                url = item.source
                lic = item.license_note
                raw_path = raw / f"{item.stem}_src.png"
            else:
                time.sleep(1.5)  # Commons rate-limit
                url, lic_api = _commons_original_url(item.source)
                lic = f"{item.license_note} / API:{lic_api}"
                suffix = Path(urllib.parse.urlparse(url).path).suffix or ".jpg"
                raw_path = raw / f"{item.stem}_src{suffix}"

            if force or not raw_path.exists():
                _download(url, raw_path)
            size = _to_gray_png(raw_path, dest, max_side)
            print(f"  → {dest.name}  {size[0]}x{size[1]}  [{lic}]  ({item.role})")
            paths.append(dest)
        except (urllib.error.URLError, RuntimeError, OSError) as exc:
            print(f"  BŁĄD {item.stem}: {exc}")

    _write_sources(out)
    return paths


def _write_sources(out_dir: Path) -> None:
    lines = [
        "# Źródła obrazów testowych (`data/real`)",
        "",
        "Obrazy robocze: grayscale PNG, dłuższy bok ≤ 512 px (LANCZOS).",
        "Oryginały kolorowe: `data/real/_raw/`.",
        "",
        "## Kodak Lossless True Color Image Suite",
        "",
        "Źródło: <https://r0k.us/graphics/kodak/>  ",
        "Maintainer podaje, że Eastman Kodak udostępnił zestaw do unrestricted usage.",
        "Standard de facto w testach kompresji obrazu.",
        "",
        "| plik | oryginał | rola w teście |",
        "|---|---|---|",
    ]
    for item in KODAK:
        lines.append(f"| `{item.stem}.png` | `{Path(item.source).name}` | {item.role} |")

    lines += [
        "",
        "## Wikimedia Commons",
        "",
        "| plik | plik na Commons | licencja (katalog) | rola |",
        "|---|---|---|---|",
    ]
    for item in WIKIMEDIA:
        lines.append(
            f"| `{item.stem}.png` | {item.source} | {item.license_note} | {item.role} |"
        )
    lines.append("")
    (out_dir / "SOURCES.md").write_text("\n".join(lines), encoding="utf-8")
