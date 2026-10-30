# TO — kompresja obrazu (kodowanie różnicowe / predykcyjne)

Projekt z Techniki obrazowej: porównanie trybów predykcji, metryk reszt
(histogram, energia, entropia) oraz efektywności kodu Huffmana.

## Uruchomienie

```bash
nix develop
python -m predcomp.cli samples
python -m predcomp.cli benchmark --predictors quick
python -m predcomp.cli verify data/samples/edges.png
```

Wyniki: `results/benchmark.csv`, `results/plots/`.

| Komenda | Opis |
|---|---|
| `list` | tryby predykcji |
| `samples` | syntetyczny zbiór PNG |
| `run IMAGE --predictor NAME` | jeden pomiar (+ opcjonalnie histogram) |
| `benchmark` | CSV + wykresy (`quick` / `all` / lista) |
| `verify IMAGE` | encode + test przyczynowości |

## Tryby predykcji

- **Sąsiedzi:** `left`, `above`, `two_left`, `three_left`, `two_above`
- **Funkcje:** `avg2`, `avg3`, `planar`, `weighted`, `quadratic_row`, `median`, `paeth`
- **LPC:** `lpc_{row,col}_o{1,2,3}_b{8,16,32,64}`
- **Adaptacja:** `selector_b8` — lokalny wybór {left, above, planar}

Wszystkie są przyczynowe (tylko już znane piksele) → bezstratne bez side-info.

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
- `predictors.py`: sąsiedzi, avg/planar/wagi, kwadratowa, mediana, Paeth
- LPC (wiersz/kolumna, rzędy i długości bloków) oraz `selector_b8`
- w sprawozdaniu: opis matematyczny trybów, uzasadnienie wyboru zestawu

### Osoba C — Metryki i Huffman
- `stats.py`, `huffman.py`, `codec.py` (encode / weryfikacja)
- CLI: `run`, `verify`; poprawność bezstratności
- w sprawozdaniu: definicje energii/entropii, budowa Huffmana, porównanie
  średniej długości kodu z entropią

### Osoba D — Eksperymenty i sprawozdanie zbiorcze
- `plotting.py`, CLI: `benchmark`, skrypty/wyniki w `results/`
- dobór tabel i wykresów, uruchomienie pełnych pomiarów
- w sprawozdaniu: wyniki, porównanie trybów, wnioski, tabela podziału zadań

**Wspólne (wszyscy):** spotkania z prowadzącym, review PR/commitów, redakcja
końcowa sprawozdania, podział procentowy wkładu zgodny z powyższym.

## Struktura repo

```
flake.nix
src/predcomp/     # kod
data/samples/     # obrazy testowe
results/          # CSV + wykresy (gitignore)
```

## Zależności (Nix)

NumPy, Pillow, Matplotlib.
