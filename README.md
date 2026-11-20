# TO — kompresja obrazu (kodowanie różnicowe / predykcyjne)

Projekt z Techniki obrazowej: porównanie trybów predykcji, metryk reszt
(histogram, energia, entropia) oraz efektywności kodu Huffmana.

## Uruchomienie

```bash
nix develop
python -m predcomp.cli samples          # syntetyka → data/samples/
python -m predcomp.cli fetch-data       # Kodak + Wikimedia → data/real/
python -m predcomp.cli benchmark --predictors quick --summarize
python -m predcomp.cli verify data/real/kodak_kodim15.png --full-decode --crop 24x40
python -m predcomp.cli lpc2d data/real/kodak_kodim15.png
```

Wyniki robocze: `results/` (gitignore). Kopie do sprawozdania: `sprawozdanie/dane/`.  
Źródła obrazów: [`data/real/SOURCES.md`](data/real/SOURCES.md).

| Komenda | Opis |
|---|---|
| `list` | tryby predykcji |
| `samples` | syntetyczny zbiór PNG |
| `fetch-data` | Kodak + Wikimedia (skala szarości ≤512 px) |
| `run IMAGE --predictor NAME` | jeden pomiar (`--hist-out`, `--show-codes`, `--mod256`) |
| `benchmark` | CSV + wykresy (`quick` / `all` / `lpc_row` / lista) |
| `summarize` | `best_per_image.csv`, `mean_by_predictor.csv` |
| `lpc2d IMAGE` | LPC 2D z side-info, kompromis vs rozmiar bloku |
| `verify IMAGE` | przyczynowość; `--full-decode --crop HxW` |

## Tryby predykcji

- **Sąsiedzi:** `left`, `above`, `two_left`, `three_left`, `two_above`
- **Funkcje:** `avg2`, `avg3`, `planar`, `weighted`, `quadratic_row`, `median`, `med` (JPEG-LS), `paeth`
- **LPC 1D:** `lpc_{row,col}_o{1,2,3}_b{8,16,32,64}` (bez side-info; pierwszy segment = left)
- **LPC 2D:** CLI `lpc2d` (A,B,C,D + współczynniki jako side-info)
- **Adaptacja:** `selector_b8` – lokalny wybór {left, above, planar}

Predyktory w rejestrze są przyczynowe (bez side-info). LPC 2D dokłada narzut na współczynniki.

## Architektura (krótko)

Każdy predyktor to `predict_map(img) → macierz float` (NumPy, zwektoryzowane).
Encode: `reszty = img − round(clip(predykcja))`. Metryki i Huffman liczone z
`np.unique` (jeden przebieg).

## Podział pracy (4 osoby)

Równy wkład w kod + wspólną część sprawozdania. Każda osoba jest **właścicielem**
swojego modułu i sekcji w sprawozdaniu; integracja i wnioski końcowe — razem.

### Osoba A — Infrastruktura i I/O
- `flake.nix`, uruchamialność (`nix develop`), `README`
- `image_io.py`, `samples.py`, CLI: `samples` / szkielet `cli.py`
- zbiór testowy (syntetyka + ewentualnie 1–2 zdjęcia własne)
- w sprawozdaniu: cel, wymagania, opis danych testowych

### Osoba B — Predyktory
- `predictors.py`: sąsiedzi, avg/planar/wagi, kwadratowa, mediana, MED, Paeth
- LPC 1D (wiersz/kolumna, rzędy i długości bloków), `selector_b8`, `lpc2d.py`
- w sprawozdaniu: opis trybów, poprawka pierwszego segmentu LPC

### Osoba C — Metryki i Huffman
- `stats.py`, `huffman.py`, `codec.py` (encode / weryfikacja / full-decode)
- CLI: `run`, `verify`; energia na piksel, książka kodowa
- w sprawozdaniu: energia/entropia, Huffman vs $H$, bezstratność

### Osoba D — Eksperymenty i sprawozdanie zbiorcze
- `plotting.py`, CLI: `benchmark`, `summarize`, `lpc2d`, wyniki
- dobór tabel i wykresów, redakcja `sprawozdanie/`
- w sprawozdaniu: wyniki, porównanie trybów, wnioski, podział zadań

**Wspólne (wszyscy):** spotkania z prowadzącym, review PR/commitów, redakcja
końcowa sprawozdania, podział procentowy wkładu zgodny z powyższym.

## Struktura repo

```
flake.nix
src/predcomp/     # kod
data/samples/     # syntetyka (kontrolowane przypadki)
data/real/        # Kodak + Wikimedia (SOURCES.md)
results/          # CSV + wykresy (gitignore)
```

## Zależności (Nix)

NumPy, Pillow, Matplotlib.
