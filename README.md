# TO: kompresja obrazu (kodowanie różnicowe / predykcyjne)

Projekt z Techniki obrazowej: porównanie trybów predykcji, metryk reszt
(histogram, energia, entropia) oraz efektywności kodu Huffmana.

## Uruchomienie

```bash
nix develop
python -m predcomp.cli samples
python -m predcomp.cli fetch-data
python -m predcomp.cli benchmark --predictors quick --summarize
python -m predcomp.cli verify data/real/kodak_kodim15.png --full-decode --crop 24x40 --lpc2d
# LPC 2D: domyślny wycinek weryfikacji 140x140
python -m predcomp.cli lpc2d data/real
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
| `summarize` | `best_per_image.csv`, `mean_by_predictor.csv` (remisy = wspólne wygrane) |
| `lpc2d PATH` | LPC 2D z side-info (plik lub katalog) |
| `verify IMAGE` | przyczynowość; `--full-decode --crop HxW`; `--lpc2d` |

## Tryby predykcji

- **Sąsiedzi:** `left`, `above`, `two_left`, `three_left`, `two_above`
- **Funkcje:** `avg2`, `avg3`, `planar`, `weighted`, `quadratic_row`, `median`, `med` (JPEG-LS), `paeth`
- **LPC 1D:** `lpc_{row,col}_o{1,2,3}_b{8,16,32,64}` (współczynniki `round(c·256)/256`; pierwszy segment = left)
- **LPC 2D:** CLI `lpc2d` (A,B,C,D + side-info 11 bit/współczynnik; przy prawej krawędzi D=B)
- **Adaptacja:** `selector_b8` – lokalny wybór {left, above, planar}

Predyktory w rejestrze są przyczynowe. LPC 2D dokłada narzut na współczynniki.

## Architektura (krótko)

Każdy predyktor to `predict_map(img)` → macierz float (NumPy).
Kodowanie: `reszty = img − round(clip(predykcja))`. Metryki i Huffman z `np.unique`.

## Podział pracy (4 osoby)

Równy wkład w kod i wspólną część sprawozdania. Każda osoba jest właścicielem
swojego modułu i sekcji; integracja i wnioski końcowe – razem.

### Osoba A: infrastruktura i I/O
- `flake.nix`, `nix develop`, `README`
- `image_io.py`, `samples.py`, szkielet CLI
- zbiór testowy; w sprawozdaniu: cel, opis danych

### Osoba B: predyktory
- `predictors.py`, `lpc2d.py` (sąsiedzi, MED, Paeth, LPC 1D/2D, selector)
- w sprawozdaniu: opis trybów, poprawki LPC

### Osoba C: metryki i Huffman
- `stats.py`, `huffman.py`, `codec.py`
- CLI `run` / `verify`; energia, książka kodowa, dekodowanie
- w sprawozdaniu: metryki, Huffman wobec $H$, bezstratność

### Osoba D: eksperymenty i sprawozdanie
- `plotting.py`, `benchmark`, `summarize`, `lpc2d`, wyniki
- redakcja `sprawozdanie/`; wnioski i podział zadań

**Wspólne:** spotkania z prowadzącym, przegląd zmian, redakcja końcowa,
podział procentowy wkładu zgodny z powyższym.

## Struktura repo

```
flake.nix
src/predcomp/
data/samples/
data/real/
results/          # gitignore
sprawozdanie/     # Typst + dane CSV + figs
```

## Zależności (Nix)

NumPy, Pillow, Matplotlib.
