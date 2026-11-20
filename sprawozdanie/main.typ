// Technika obrazowa — sprawozdanie z projektu
// Temat 3: kompresja obrazu (kodowanie różnicowe / predykcyjne)
// Kompilacja: typst compile sprawozdanie/main.typ

#set document(
  title: "Kompresja obrazu — kodowanie różnicowe/predykcyjne",
  author: "Zespół TO",
)
#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  numbering: "1",
)
#set text(lang: "pl", font: "Liberation Serif", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true, leading: 0.65em)
#show heading: set block(above: 1.2em, below: 0.6em)
#show figure: set block(breakable: false)
#show link: underline

#let code-font = "Liberation Mono"
#let mono(body) = text(font: code-font, size: 0.9em, body)

#align(center)[
  #text(size: 12pt)[Politechnika Warszawska · Wydział Elektroniki i Technik Informacyjnych]

  #v(0.8cm)
  #text(size: 14pt, weight: "bold")[Technika obrazowa — projekt]

  #v(0.4cm)
  #text(size: 18pt, weight: "bold")[
    Kompresja obrazu z wykorzystaniem\
    kodowania różnicowego / predykcyjnego
  ]

  #v(0.6cm)
  #text(size: 11pt)[Temat 3 · semestr zimowy 2025/26]

  #v(1.2cm)
  #grid(
    columns: (1fr, 1fr),
    gutter: 1.2cm,
    align(left)[
      *Zespół* \
      \[Imię Nazwisko\] — osoba A \
      \[Imię Nazwisko\] — osoba B \
      \[Imię Nazwisko\] — osoba C \
      \[Imię Nazwisko\] — osoba D
    ],
    align(left)[
      *Prowadzący* \
      \[dr inż. …\] \
      \
      *Repozytorium* \
      `predcomp` (Python / Nix)
    ],
  )

  #v(1.5cm)
  #text(size: 10pt)[Data: listopad 2026]
]

#pagebreak()

= Cel i wymagania

Celem projektu jest bezstratna kompresja obrazów w skali szarości metodą
*kodowania różnicowego (predykcyjnego)*: dla każdego piksela wyznaczamy
predykcję na podstawie już znanych sąsiadów, kodujemy resztę
$e = I - hat(I)$, a następnie porównujemy rozkład reszt z rozkładem oryginału
oraz efektywność statycznego kodu Huffmana z entropią Shannonowską.

Zgodnie z kartą projektu wymagane jest:
+ kilka trybów predykcji — w tym 1, 2 i 3 sąsiednie piksele oraz LPC
  z różnymi długościami bloków;
+ porównanie oryginału i reszt: histogramy, energia, entropia;
+ zbudowanie kodu Huffmana i porównanie średniej długości kodu z entropią.

Aplikacja `predcomp` realizuje powyższe punkty w pełni przyczynowo
(predykcja korzysta wyłącznie z pikseli już zrekonstruowanych), więc
kodowanie jest bezstratne bez side-information.

= Dane testowe

Zbiór składa się z dwóch części.

== Obrazy syntetyczne (`data/samples/`, $128 times 128$)

Kontrolowane przypadki o znanej strukturze przestrzennej:

#figure(
  grid(
    columns: 4,
    gutter: 0.4cm,
    image("figs/gradient_h.png", width: 100%),
    image("figs/edges.png", width: 100%),
    image("figs/smooth_blobs.png", width: 100%),
    image("figs/noise.png", width: 100%),
  ),
  caption: [Przykłady syntetyczne: gradient poziomy, krawędzie, gładkie plamy, szum i.i.d.],
)

- `gradient_h` / `gradient_v` — silna korelacja w jednym kierunku,
- `edges`, `checker` — ostre przejścia,
- `smooth_blobs` — obszary gładkie z miękkimi granicami,
- `noise` — brak korelacji (graniczny przypadek predykcji),
- `naturalish` — pole $1\/f$ z rozmycim (przybliżenie zdjęcia).

== Obrazy rzeczywiste (`data/real/`, grayscale, dłuższy bok $lt.eq 512$)

- *Kodak Lossless True Color Image Suite* — 6 klatek (`kodim05/08/13/15/19/23`),
- *Wikimedia Commons* — 5 obrazów (portret, tekstura, fasada, rękopis, listowie).

Źródła i licencje: `data/real/SOURCES.md`.
Przykłady:

#figure(
  grid(
    columns: 2,
    gutter: 0.6cm,
    image("figs/kodak_kodim15.png", width: 100%),
    image("figs/kodak_kodim08.png", width: 100%),
  ),
  caption: [Kodak `kodim15` (portret) oraz `kodim08` (architektura / ostre krawędzie).],
)

= Metody

== Model kodowania

Dla obrazu $I in {0,...,255}^(H times W)$ i predyktora $P$:

$
hat(I) = Q(P(I)), quad
e = I - hat(I),
$

gdzie $Q$ to zaokrąglenie do najbliższej liczby całkowitej z obcięciem do
$[0, 255]$. Wszystkie predyktory są *przyczynowe* względem porządku
rasterowego (lewy → prawy, góra → dół): do predykcji piksela $(x,y)$
używane są wyłącznie piksele już odwiedzone. Dzięki temu dekoder
odtwarza $I$ sekwencyjnie z samego ciągu reszt $e$.

== Tryby predykcji

Oznaczamy sąsiadów w konwencji PNG/JPEG-LS:
$A$ — lewy, $B$ — górny, $C$ — górny-lewy.

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: 6pt,
    stroke: 0.5pt + luma(180),
    [*Nazwa*], [*Opis*],
    [`left` / `above`], [1 sąsiad: $A$ lub $B$],
    [`two_left` / `three_left`], [średnia 2 lub 3 pikseli w wierszu],
    [`avg2` / `avg3`], [$(A+B)\/2$ oraz $(A+B+C)\/3$],
    [`planar`], [$A + B - C$ (predykcja płaszczyzny)],
    [`weighted`], [$0.75 A + 0.25 B$],
    [`quadratic_row`], [ekstrapolacja kwadratowa w wierszu],
    [`median`], [mediana$(A,B,C)$],
    [`paeth`], [selektor Paetha (PNG)],
    [`lpc_row_*` / `lpc_col_*`], [LPC rzędu 1–3, okno bloku 8–64],
    [`selector_b8`], [lokalny wybór $\{A, B, "planar"\}$ w bloku $8 times 8$],
  ),
  caption: [Zestaw trybów użytych w eksperymentach (podzbiór `quick`).],
)

LPC: w każdym segmencie długości $B$ współczynniki estymowane są metodą
najmniejszych kwadratów na poprzednim oknie przyczynowym i stosowane do
bieżącego segmentu (bez side-info — dekoder powtarza tę samą estymację).

`selector_b8` wybiera w bloku ten z trzech kandydatów, który na *ramce*
przyczynowej (już znane piksele przy krawędzi bloku) ma najmniejszą energię
błędu.

== Metryki

Dla sygnału $x$ (oryginał lub reszty):

- *energia* $E = sum_i x_i^2$,
- *entropia empiryczna*
  $H = - sum_v p_v log_2 p_v$, gdzie $p_v$ to częstości wartości,
- *średnia długość Huffmana* $overline(L) = sum_v p_v ell_v$, gdzie $ell_v$
  to długości kodów ze statycznego drzewa Huffmana zbudowanego na histogramie.

Dla bezstratnego kodu źródłowego zachodzi $overline(L) >= H$; różnica
$Delta = overline(L) - H$ mierzy „marnotrawstwo” kodu względem entropii.

= Implementacja

Kod w Pythonie (NumPy, Pillow, Matplotlib), środowisko przez Nix Flake:

```
nix develop
python -m predcomp.cli samples
python -m predcomp.cli fetch-data
python -m predcomp.cli verify IMAGE
python -m predcomp.cli benchmark --predictors quick
```

Moduły: `predictors.py` (mapy predykcji), `codec.py` (encode / weryfikacja),
`stats.py` + `huffman.py` (metryki), `plotting.py` + `cli.py` (benchmark,
CSV, wykresy). Wyniki eksperymentów: `results/benchmark.csv` oraz figury
w `sprawozdanie/figs/`.

Weryfikacja bezstratności (`verify`) na `kodak_kodim15` dla całego zestawu
`quick` zakończyła się statusem *OK* dla wszystkich 16 trybów.

= Wyniki eksperymentów

Benchmark: 18 obrazów $times$ 16 predyktorów (`quick`). Poniżej wybrane
wyniki ilustrujące zachowanie metod.

== Histogramy: oryginał vs reszty

#figure(
  image("figs/gradient_h__left.png", width: 95%),
  caption: [`gradient_h` + `left`: oryginał ma płaski histogram (wszystkie poziomy),
    reszty koncentrują się wokół zera ($H approx 0.13$).],
)

#figure(
  image("figs/noise__planar.png", width: 95%),
  caption: [`noise` + `planar`: brak korelacji — reszty są *szersze* niż oryginał
    ($H$: $7.99 -> 8.85$). Predykcja pogarsza kompresję.],
)

#figure(
  image("figs/kodak_kodim15__selector_b8.png", width: 95%),
  caption: [`kodak_kodim15` + `selector_b8`: typowy przypadek zdjęcia —
    spadek entropii z $7.48$ do $4.43$ bit/piksel.],
)

== Porównanie trybów (entropia reszt i Huffman)

#figure(
  image("figs/gradient_h_bars.png", width: 92%),
  caption: [Gradient poziomy: prawie wszystkie proste tryby dają $H < 0.3$;
    LPC (źle dopasowany do czystego gradientu / kwantyzacja) wypada gorzej.],
)

#figure(
  image("figs/noise_bars.png", width: 92%),
  caption: [Szum i.i.d.: entropia reszt *powyżej* entropii oryginału (linia
    przerywana) — predykcja nie pomaga.],
)

#figure(
  image("figs/kodak_kodim15_bars.png", width: 92%),
  caption: [Portret Kodak: najlepsze `paeth` / `selector_b8` / `avg2`
    ($H approx 4.4$); LPC i `quadratic_row` wyraźnie gorsze.],
)

#figure(
  image("figs/kodak_kodim08_bars.png", width: 92%),
  caption: [Architektura (`kodim08`): `paeth` wygrywa ($H approx 5.56$),
    potem `selector_b8` i `planar` — krawędzie i linie faworyzują selektory.],
)

== Tabele zbiorcze

Entropia reszt $H$ dla wybranych obrazów i trybów:

#figure(
  table(
    columns: (auto,) + (auto,) * 5,
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [`left`], [`planar`], [`paeth`], [`LPC o2`], [`sel.`],
    [gradient_h], [0.132], [*0.066*], [*0.066*], [1.044], [0.339],
    [edges], [0.354], [0.207], [0.208], [2.898], [*0.160*],
    [smooth_blobs], [2.643], [*1.214*], [2.081], [3.234], [1.433],
    [noise], [8.704], [8.847], [8.733], [8.566], [8.700],
    [kodim15], [4.797], [4.678], [*4.407*], [5.187], [4.426],
    [kodim08], [6.450], [5.829], [*5.556*], [6.769], [5.816],
    [manuscript], [6.207], [6.287], [*5.967*], [6.538], [6.127],
  ),
  caption: [Entropia reszt \[bit/piksel\]. `LPC o2` = `lpc_row_o2_b16`,
    `sel.` = `selector_b8`. Najlepszy wynik w wierszu pogrubiony
    (dla `noise` wszystkie wyniki są gorsze od $H_0$).],
)

Najlepszy tryb per obraz (wg $H$ reszt) oraz średnie po całym zbiorze:

#figure(
  table(
    columns: (1.6fr, auto, 1.4fr, auto, auto),
    align: (left, center, left, center, center),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [$H_0$], [*Najlepszy*], [$H$], [$overline(L)$],
    [checker], [1.00], [planar], [0.13], [1.02],
    [edges], [2.03], [selector_b8], [0.16], [1.05],
    [gradient_h/v], [7.00], [planar / paeth], [0.07], [1.01],
    [smooth_blobs], [5.48], [planar], [1.21], [1.45],
    [naturalish], [6.89], [planar], [4.80], [4.83],
    [noise], [7.99], [avg3\*], [8.42], [8.44],
    [kodim05], [7.41], [avg2], [6.03], [6.06],
    [kodim08], [7.69], [paeth], [5.56], [5.58],
    [kodim13], [7.48], [weighted], [6.26], [6.28],
    [kodim15], [7.48], [paeth], [4.41], [4.43],
    [kodim19], [7.44], [paeth], [4.88], [4.92],
    [kodim23], [7.31], [selector_b8], [3.96], [4.01],
    [wiki\_building], [7.49], [paeth], [5.35], [5.39],
    [wiki\_field], [7.57], [paeth], [5.61], [5.64],
    [wiki\_manuscript], [7.04], [paeth], [5.97], [6.00],
    [wiki\_oak], [6.70], [paeth], [5.54], [5.57],
    [wiki\_portrait], [6.45], [avg2], [3.66], [3.69],
  ),
  caption: [Zwycięzca per obraz. \*dla szumu „najlepszy” nadal zwiększa entropię
    względem $H_0$.],
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Predyktor*], [śr. $H$], [śr. $overline(L)$], [śr. $Delta$], [zwycięstwa],
    [paeth], [*4.10*], [*4.33*], [+0.23], [*7*],
    [selector_b8], [4.14], [4.34], [+0.20], [2],
    [planar], [4.19], [4.43], [+0.24], [5],
    [avg2], [4.29], [4.47], [+0.17], [2],
    [weighted], [4.37], [4.54], [+0.17], [1],
    [left], [4.44], [4.64], [+0.19], [0],
    [lpc_row_o2_b16], [4.99], [5.07], [+0.08], [0],
    [quadratic_row], [5.14], [5.31], [+0.17], [0],
  ),
  caption: [Średnie po 18 obrazach (wybrane tryby). `paeth` ma najniższą średnią
    entropię i najwięcej zwycięstw.],
)

== Huffman vs entropia

Na obrazach rzeczywistych $Delta = overline(L) - H$ jest zwykle rzędu
$0.02$–$0.05$ bit/piksel — statyczny Huffman jest bliski entropii.
Na sygnałach o bardzo małej entropii (gradient, checker, edges) pojawia się
większe $Delta$ (nawet $approx 0.9$), bo Huffman musi mieć długości całkowite
i przy dominującym symbolu „0” średnia długość nie może spaść poniżej $approx 1$
bit/symbol (dla alfabetu dwu-/kilkuwartościowego).

== Wizualizacja mapy reszt

#figure(
  grid(
    columns: 2,
    gutter: 0.5cm,
    [
      #image("figs/res_gradient_h_left.png", width: 100%)
      #align(center, text(size: 9pt)[gradient_h / left (+128)])
    ],
    [
      #image("figs/res_kodim15_selector.png", width: 100%)
      #align(center, text(size: 9pt)[kodim15 / selector_b8 (+128)])
    ],
  ),
  caption: [Mapy reszt przesunięte o 128 (szary = zero). Gradient: prawie jednolity
    szary. Portret: reszty głównie na krawędziach i teksturach.],
)

= Wnioski

+ *Predykcja działa, gdy jest korelacja przestrzenna.* Na gradientach i
  gładkich obszarach entropia spada o rząd wielkości; na szumie i.i.d.
  rośnie — to oczekiwane ograniczenie modelu.
+ *Najlepszy ogólny tryb w zestawie: `paeth`*, potem `selector_b8` i
  `planar`. Selektory radzą sobie szczególnie dobrze przy mieszance
  krawędzi i obszarów gładkich (zdjęcia, architektura).
+ *Proste średnie (`avg2`) często biją LPC* w tym eksperymencie: LPC bez
  side-info, z kwantyzacją predykcji do 8 bitów i krótkim oknem, bywa
  niestabilne / droższe obliczeniowo, a zysk rzadko przewyższa Paetha.
+ *Huffman ≈ entropia* na typowych resztach zdjęć ($Delta$ rzędu
  setnych bita). Przy bardzo skupionych resztach limituje go całkowitość
  długości kodów.
+ Implementacja jest bezstratna (weryfikacja przyczynowości + tożsamość
  encode) i odtwarzalna przez `nix develop` + CLI.

Możliwe rozszerzenia: predyktory JPEG-LS / CALIC, adaptacyjny / kanoniczny
Huffman lub Golomb–Rice, kolor (osobno kanały YCbCr), pomiary rzeczywistego
rozmiaru bitowego z nagłówkiem drzewa.

= Podział zadań

#figure(
  table(
    columns: (auto, 1.2fr, 1.4fr),
    align: (left, left, left),
    inset: 6pt,
    stroke: 0.5pt + luma(180),
    [*Os.*], [*Moduły / odpowiedzialność*], [*Sekcja sprawozdania*],
    [A], [`flake.nix`, `image_io`, `samples`, szkielet CLI, dane], [cel, wymagania, opis danych],
    [B], [`predictors.py` — sąsiedzi, avg/planar, LPC, selector], [opis matematyczny trybów],
    [C], [`stats`, `huffman`, `codec`, `run`/`verify`], [metryki, Huffman vs entropia],
    [D], [`plotting`, `benchmark`, wyniki, redakcja zbiorcza], [tabele, wykresy, wnioski],
  ),
  caption: [Podział pracy w zespole 4-osobowym (zgodnie z README projektu).
    Uzupełnić imionami i procentami wkładu przed oddaniem.],
)

*Szacunkowy udział:* A 25% · B 25% · C 25% · D 25% (do potwierdzenia przez zespół).

#v(1em)
#align(center, text(size: 9pt, fill: luma(100))[
  Pełne wyniki liczbowe: `results/benchmark.csv`. \
  Kod źródłowy i zbiór danych: repozytorium projektu.
])
