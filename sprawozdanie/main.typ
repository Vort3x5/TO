// Technika obrazowa – sprawozdanie (temat 3)
// typst compile sprawozdanie/main.typ

#set document(
  title: "Kompresja obrazu – kodowanie różnicowe/predykcyjne",
  author: "Zespół TO",
)
#set page(paper: "a4", margin: (x: 2.2cm, y: 2.35cm), numbering: "1")
#set text(lang: "pl", font: "Liberation Serif", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true, leading: 0.65em)
#show heading: set block(above: 1.1em, below: 0.5em)
#show figure: set block(breakable: false)

#align(center)[
  #text(size: 12pt)[Politechnika Warszawska – Wydział Elektroniki i Technik Informacyjnych]
  #v(0.65cm)
  #text(size: 14pt, weight: "bold")[Technika obrazowa – projekt]
  #v(0.3cm)
  #text(size: 17pt, weight: "bold")[
    Kompresja obrazu z wykorzystaniem\
    kodowania różnicowego / predykcyjnego
  ]
  #v(0.45cm)
  #text(size: 11pt)[Temat 3, semestr zimowy 2026/27]
  #v(1.0cm)
  #grid(
    columns: (1fr, 1fr),
    gutter: 1.2cm,
    align(left)[
      *Zespół* \
      \Szymon Boniuk\
      \Karolina Świątek\
      \Piotr Świtaj\
      \Michał Kopyciński\
    ],
    align(left)[
      *Prowadzący* \
      \dr inż. Grzegorz Galiński \
    ],
  )
  #v(1.2cm)
  #text(size: 10pt)[Data: listopad 2026]
]

#pagebreak()

= Cel i wymagania

Celem było zaimplementowanie bezstratnej kompresji obrazów w skali szarości
metodą kodowania różnicowego: piksel przewidujemy z już znanych sąsiadów
i kodujemy resztę $e = I - hat(I)$, czyli różnicę między wartością piksela
a jego predykcją. Z karty projektu wynikają trzy obowiązki: kilka trybów
predykcji (w tym 1–3 sąsiadów oraz LPC przy różnych długościach odcinków
i bloków), porównanie oryginału z resztami (histogram, energia, entropia)
oraz statyczny Huffman zestawiony z entropią $H$.

= Dane testowe

*Syntetyczne* (`data/samples/`, $128 times 128$): gradienty, szachownica,
krawędzie, gładkie plamy, szum niezależny, pole „naturalish” (widmo $1\/f$
z rozmyciem).

*Rzeczywiste* (`data/real/`, dłuższy bok $lt.eq 512$): sześć klatek Kodak
oraz pięć obrazów z Wikimedia Commons. Źródła: `data/real/SOURCES.md`.

#figure(
  grid(
    columns: 4,
    gutter: 0.35cm,
    image("figs/gradient_h.png", width: 100%),
    image("figs/edges.png", width: 100%),
    image("figs/smooth_blobs.png", width: 100%),
    image("figs/noise.png", width: 100%),
  ),
  caption: [Syntetyka: gradient, krawędzie, gładkie plamy, szum.],
)

#figure(
  grid(
    columns: 2,
    gutter: 0.5cm,
    image("figs/kodak_kodim15.png", width: 100%),
    image("figs/kodak_kodim08.png", width: 100%),
  ),
  caption: [Kodak `kodim15` (portret) i `kodim08` (architektura).],
)

= Metody

== Model

Dla obrazu $I in {0,...,255}^(h times w)$ i predyktora $P$ predykcja to
$hat(I) = Q(P(I))$, a reszta $e = I - hat(I)$, gdzie $Q$ zaokrągla do
liczb całkowitych w $[0,255]$. Obraz przeglądamy wiersz po wierszu, od lewej
do prawej (porządek rastrowy). Każdy predyktor korzysta wyłącznie z pikseli
już odwiedzonych w tej kolejności (predykcja przyczynowa), więc dekoder może
powtórzyć tę samą predykcję. LPC 2D dodatkowo zapisuje współczynniki bloku.

Sąsiedzi $A$ (lewy), $B$ (górny), $C$ (górny-lewy) są wspólni dla trybów
korzystających z sąsiadów $A$, $B$, $C$: przy $x=0$ przyjmujemy $A := B$
oraz $C := B$, przy $y=0$ jest $B := A$ oraz $C := A$ (punkt $(0,0)$ zostaje
0). Dzięki temu `left`, `above`, `planar` i LPC dzielą tę samą obsługę
krawędzi; na brzegu `planar` i `avg3` redukują się do jednego znanego sąsiada.

== Tryby bez informacji dodatkowej

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Nazwa*], [*Opis*],
    [`left` / `above`], [jeden sąsiad: $A$ lub $B$],
    [`two_left` / `three_left`], [średnia 2 lub 3 pikseli w wierszu],
    [`avg2` / `avg3`], [$(A+B)\/2$, $(A+B+C)\/3$],
    [`planar`], [$A+B-C$],
    [`weighted`], [$0.75 A + 0.25 B$],
    [`quadratic_row`], [ekstrapolacja kwadratowa w wierszu],
    [`median`], [mediana$(A,B,C)$],
    [`med`], [MED (JPEG-LS): mediana$(A,B,A+B-C)$],
    [`paeth`], [selektor Paetha (PNG)],
    [`lpc_row_*` / `lpc_col_*`], [LPC 1D, rząd 1–3, odcinek $N in {8,16,32,64}$],
    [`selector_b8`], [wybór left / above / planar w bloku $8 times 8$],
  ),
  caption: [Predyktory w `predcomp`.],
)

*`selector_b8`.* Obraz dzielimy na bloki $8 times 8$; $(b_y, b_x)$ to
współrzędne lewego górnego piksela bloku. W każdym bloku wybieramy ten
z trybów `left`, `above` i `planar`, który dawał najmniejszą energię
błędu na pikselach już znanych dekoderowi: w wierszu nad blokiem
($y = b_y - 1$), w kolumnie $x = b_x - 1$ ponad blokiem oraz (gdy
$b_x > 0$) na ośmiu pikselach na lewo od bloku w jego pierwszym wierszu.
Pikseli z wnętrza bloku nie używamy, więc dekoder może powtórzyć wybór.

*LPC 1D.* Piksel przewidujemy jako kombinację liniową $p$ poprzednich
pikseli w tej samej linii, czyli w wierszu (`lpc_row`) lub kolumnie
(`lpc_col`): $hat(I)_n = sum_(k=1)^p c_k I_(n-k)$, gdzie $p in {1,2,3}$
to rząd predyktora. Linię dzielimy na odcinki długości $N$.
Współczynniki $c_k$ dla odcinka wyznaczamy metodą najmniejszych kwadratów
na $N$ pikselach poprzedniego odcinka. Dekoder zna już te piksele, więc
współczynników nie trzeba przesyłać. Pierwszy odcinek nie ma poprzednika
i używa `left` (lub `above`). Do tego samego predyktora wracamy też wtedy,
gdy układ równań jest osobliwy, np. w stałym fragmencie wiersza.
Współczynniki zaokrąglamy do wielokrotności $1\/256$ w przedziale $[-2, 2]$.
Zmniejsza to ryzyko, że koder i dekoder na różnych maszynach policzą inne
wartości, ale go nie usuwa.

== LPC 2D z informacją dodatkową

Obraz dzielimy na bloki $N times N$. W każdym bloku estymujemy
$ hat(I) = alpha A + beta B + gamma C + delta D, $
gdzie $D$ jest górnym-prawym sąsiadem; przy prawej krawędzi ($x = w-1$)
przyjmujemy $D = B$. Współczynniki wyznaczamy metodą najmniejszych
kwadratów z pikseli samego bloku, więc w przeciwieństwie do LPC 1D
dekoder ich nie zna i trzeba je zapisać w pliku. Cztery współczynniki
po 11 bitów to narzut $(4 dot 11)\/N^2$ bit/piksel.
Dekoder odtwarza obraz sekwencyjnie z reszt i siatki współczynników.

== Metryki

Energia reszt na piksel: $E = 1\/(h w) sum e^2$. Dla oryginału liczymy ją
po odjęciu średniej ($E_c$), żeby nie zależała od jasności obrazu.
Entropia empiryczna: $H = -sum_s p_s log_2 p_s$, gdzie $p_s$ to częstość
symbolu $s$; $H_0$ oznacza entropię oryginału, $H$ entropię reszt.
Średnia długość słowa kodu Huffmana to $overline(L)$, a
$Delta = overline(L) - H$.

Reszty leżą w ${-255,...,255}$ (511 symboli), więc $H$ może przekroczyć
8 bitów. Po redukcji modulo 256 (jak w PNG / JPEG-LS) entropia wraca bliżej
$H_0$.

#pagebreak()

= Implementacja

Środowisko: `nix develop`.

```
python -m predcomp.cli benchmark --predictors quick --summarize
python -m predcomp.cli benchmark --predictors lpc_row \
  --data data/real/kodak_kodim15.png --out results/lpc_sweep
python -m predcomp.cli lpc2d data/real
python -m predcomp.cli verify IMAGE --full-decode --crop 24x40
python -m predcomp.cli verify IMAGE --predictors left --lpc2d
```

`--data` przyjmuje katalog albo pojedynczy PNG (jak `lpc2d`).
`--crop` dotyczy tylko trybów z tabeli 1; LPC 2D ma domyślnie wycinek
$140 times 140$ (`--lpc2d-crop` zmienia go niezależnie). `summarize` przy
remisie wypisuje wszystkich zwycięzców. CSV: `sprawozdanie/dane/`.

Test przyczynowości zeruje wszystkie piksele od wybranej pozycji dalej
i sprawdza, że predykcje dla wcześniejszych pozycji się nie zmieniają.
Pełne dekodowanie odtwarza obraz piksel po pikselu wyłącznie z reszt
(a dla LPC 2D także ze współczynników) i porównuje wynik z oryginałem.

= Wyniki

Benchmark `quick`: 18 obrazów $times$ 17 trybów. Zestaw `quick` to tryby
z tabeli 1, z LPC w wariantach `lpc_row_o1_b16`, `lpc_row_o2_b16`,
`lpc_row_o3_b32` i `lpc_col_o2_b16`.

== Histogramy

#figure(
  image("figs/gradient_h__left.png", width: 90%),
  caption: [`gradient_h` + `left`: oryginał płaski, reszty skupione.],
)

#figure(
  image("figs/noise__planar.png", width: 90%),
  caption: [`noise` + `planar`: $H$ reszt $7.99 -> 8.85$ (511 symboli).
    Po `mod 256`: $H approx 7.99$.],
)

#figure(
  image("figs/kodak_kodim15__med.png", width: 90%),
  caption: [`kodim15` + `med`: $H$ z $7.48$ do $4.36$.],
)

== Energia na piksel

#figure(
  table(
    columns: (auto,) + (auto,) * 5,
    align: center,
    inset: 4.5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [$E_c$ oryg.], [`left`], [`planar`], [`med`], [`LPC o1`],
    [gradient_h], [5463], [4.0], [0.03], [0.03], [2.0],
    [smooth_blobs], [2202], [12], [1.5], [4.2], [14],
    [kodim15], [6712], [222], [113], [82], [238],
    [kodim08], [3802], [1065], [368], [273], [1087],
    [manuscript], [1940], [824], [772], [517], [829],
    [noise], [5468], [10935], [14098], [10941], [9946],
  ),
  caption: [$E_c$: oryginał po odjęciu średniej. `LPC o1` = `lpc_row_o1_b16`.],
)

== Porównanie trybów

#figure(
  image("figs/gradient_h_bars.png", width: 88%),
  caption: [Gradient poziomy. Przy `left` reszta jest prawie stała ($approx 2$),
    stąd $H approx 0.13$. LPC rzędu 2 na kolejnych odcinkach zeruje błąd, ale
    pierwszy odcinek zostaje jak `left`: w resztach są jednocześnie zera i
    dwójki, więc $H$ rośnie do ok. 0,59. Rząd 1 bez wyrazu wolnego nie modeluje
    stałego przyrostu ($H approx 2.08$). Niższa energia błędu nie musi iść w
    parze z niższą entropią.],
)

#figure(
  image("figs/noise_bars.png", width: 88%),
  caption: [Szum: entropia reszt powyżej $H_0$.],
)

#figure(
  image("figs/kodak_kodim15_bars.png", width: 88%),
  caption: [`kodim15`: najniższe $H$ ma `med` ($4.36$). LPC wierszowe
    ($4.96$–$5.03$) ustępuje `left` ($4.78$); LPC kolumnowe ($4.69$) ustępuje
    `above` ($4.50$).],
)

#figure(
  image("figs/kodak_kodim08_bars.png", width: 88%),
  caption: [`kodim08`: `med` i `paeth` przed pozostałymi trybami.],
)

#pagebreak()

== LPC 1D: poprawki i zależność od $N$

W pierwszej wersji LPC 1D dawało na gradientach wyraźnie gorsze wyniki
niż `left`. Przegląd kodu wykazał dwa błędy. Pierwszy odcinek każdego
wiersza dostawał predykcję 0 zamiast `left`, więc jego piksele trafiały
do reszt bez zmian. Drugi dotyczył fragmentów stałych: układ równań ma
tam nieskończenie wiele rozwiązań, a `numpy.linalg.lstsq` zwraca to
o najmniejszej normie, np. $c = (1\/3, 1\/3, 1\/3)$. Takiej wartości nie
da się zapisać na siatce $1\/256$, więc po zaokrągleniu suma
współczynników nie wynosi 1 i na stałym tle pojawiają się błędy
$plus.minus 1$. Obecnie w takim przypadku używamy `left`, a siatka
$1\/256$ zapisuje dokładnie typowe wartości $plus.minus 1$, $1\/2$,
$plus.minus 2$. Wszystkie tryby mają też wspólną obsługę krawędzi
(sekcja 3.1), więc porównanie z `left` i `above` nie zależy od tego,
jak traktowany jest pierwszy wiersz i pierwsza kolumna.

Na 11 zdjęciach rzeczywistych LPC wierszowe (rzędy 2 i 3) przegrywa z `left`
we wszystkich przypadkach; LPC kolumnowe przegrywa z `above` również na
wszystkich 11. Na syntetyce LPC bywa lepsze (np. szum, wybrane gradienty).
`med` zostaje wyraźnie z przodu.

#figure(
  image("figs/kodak_kodim15_lpc_sweep.png", width: 86%),
  caption: [LPC wierszowe na `kodim15`: $H$ względem $N$ dla rzędów 1–3.
    Odtworzenie: `benchmark --predictors lpc_row --data data/real/kodak_kodim15.png`.
    CSV: `sprawozdanie/dane/lpc_row_sweep.csv`.],
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Rząd*], [$N=8$], [$N=16$], [$N=32$], [$N=64$],
    [1], [4.986], [4.963], [4.952], [4.924],
    [2], [5.123], [5.019], [4.959], [4.939],
    [3], [5.471], [5.131], [5.030], [4.987],
  ),
  caption: [Entropia reszt LPC 1D (wiersz) na `kodim15`.
    `left` = 4.782, `above` = 4.498, `med` = 4.356.],
)

== LPC 2D na jedenastu zdjęciach

#figure(
  table(
    columns: (1.35fr, auto, auto, auto, auto),
    align: (left, center, center, center, center),
    inset: 4.5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [`med`], [LPC 2D], [*N*], [lepszy],
    [kodim05], [6.01], [5.93], [32], [LPC],
    [kodim08], [5.55], [5.72], [32], [MED],
    [kodim13], [6.31], [6.17], [64], [LPC],
    [kodim15], [4.36], [4.26], [32], [LPC],
    [kodim19], [4.84], [4.77], [32], [LPC],
    [kodim23], [3.89], [3.72], [32], [LPC],
    [wiki\_building], [5.27], [5.30], [32], [MED],
    [wiki\_field\_texture], [5.56], [5.51], [64], [LPC],
    [wiki\_manuscript], [5.92], [5.94], [64], [MED],
    [wiki\_oak\_foliage], [5.48], [5.44], [32], [LPC],
    [wiki\_portrait], [3.77], [3.50], [64], [LPC],
  ),
  caption: [LPC 2D: najlepsza suma $H$ + narzut wobec `med`. LPC wygrywa na
    8 z 11 zdjęć; MED zostaje przy ostrych liniach (`kodim08`, fasada,
    rękopis). Najczęściej $N=32$ lub $64$.],
)

#figure(
  image("figs/kodak_kodim15_lpc2d.png", width: 86%),
  caption: [`kodim15`: suma $H$+narzut zmienia się niewiele między $N=16$ a
    $N=64$. Na innych obrazach rozrzut bywa większy – np. na
    `wiki_building` różnica $N=16$ wobec $N=64$ to ok. 0,09
    (przy najlepszym $N=32$).],
)

#pagebreak()

== Huffman

Na zdjęciach $Delta$ jest zwykle $0.02$–$0.05$ bit/piksel. Przy bardzo małej
entropii $overline(L)$ nie spada poniżej ok. 1. Fragment książki kodowej
(tabeli słów kodowych Huffmana) dla `kodim15` + `med`:

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*$e$*], [*liczność*], [*dł.*], [*kod*],
    [0], [33797], [2], [`00`],
    [+1], [23397], [3], [`101`],
    [−1], [22982], [3], [`100`],
    [+2], [12586], [4], [`1101`],
    [−2], [12264], [4], [`1100`],
    [+3], [7265], [5], [`11110`],
  ),
  caption: [Najczęstsze symbole. Alfabet: 242 pozycje; szacunek narzutu tabeli
    ok. 0,02 bit/piksel (poza $overline(L)$).],
)

== Zestawienie

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Predyktor*], [śr. $H$], [śr. $overline(L)$], [śr. $Delta$], [wygrane\*],
    [med], [*4.05*], [*4.27*], [+0.23], [*11*],
    [paeth], [4.10], [4.33], [+0.23], [3],
    [selector_b8], [4.14], [4.34], [+0.20], [2],
    [planar], [4.19], [4.43], [+0.24], [5],
    [avg2], [4.24], [4.42], [+0.18], [2],
    [left], [4.41], [4.61], [+0.20], [1],
    [lpc_col_o2_b16], [4.53], [4.67], [+0.15], [1],
    [lpc_row_o2_b16], [4.66], [4.77], [+0.12], [1],
    [lpc_row_o1_b16], [4.76], [4.85], [+0.09], [1],
    [quadratic_row], [5.14], [5.31], [+0.17], [0],
  ),
  caption: [Średnie po 18 obrazach. \*remisy liczone jako wspólne zwycięstwa.],
)

#figure(
  grid(
    columns: 2,
    gutter: 0.4cm,
    [
      #image("figs/res_gradient_h_left.png", width: 100%)
      #align(center, text(size: 9pt)[gradient_h / left (+128)])
    ],
    [
      #image("figs/res_kodim15_med.png", width: 100%)
      #align(center, text(size: 9pt)[kodim15 / med (+128)])
    ],
  ),
  caption: [Mapy reszt. Gradient: prawie jednolity szary. Portret: błędy na
    krawędziach i fakturze.],
)

= Wnioski

Predykcja pomaga przy korelacji przestrzennej i szkodzi przy szumie
niezależnym. Entropia reszt powyżej 8 bitów wynika z alfabetu 511-symbolowego;
po `mod 256` wracamy blisko $H_0$.

Najlepszy tryb bez informacji dodatkowej to `med`. `planar` ($A+B-C$) dobrze
opisuje lokalnie płaskie obszary (`smooth_blobs`, `naturalish`). LPC 1D
przegrywa na zdjęciach z prostym predyktorem jednego sąsiada: wierszowe
z `left`, kolumnowe z `above`; na syntetyce bywa lepiej.
LPC 2D z narzutem współczynników wygrywa z `med` na 8 z 11 zdjęć (przegrywa
przy ostrych liniach). Typowy dobry rozmiar bloku to 32 lub 64; na `kodim15`
zależność od $N$ jest płaska, na innych obrazach rozrzut bywa większy.

Przy przeglądzie kodu poprawiliśmy zerowy pierwszy odcinek LPC oraz
obsługę osobliwych układów; gradienty wracają do niskiego $H$ dzięki
sprawdzeniu rzędu macierzy i siatce $1\/256$. Bezstratność sprawdziliśmy
testem przyczynowości oraz pełnym odtworzeniem: tryby z tabeli 1 na wycinku
$24 times 40$, LPC 2D na $140 times 140$.

= Podział zadań

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Os.*], [*Co zrobiła*],
    [Szymon Boniuk],
    [Środowisko Nix, wczytywanie/zapis PNG, generator próbek syntetycznych,
      pobieranie Kodak/Wikimedia i opis zbioru w sprawozdaniu.],
    [Michał Kopyciński],
    [Predyktory (sąsiedzi, MED, Paeth, selector), LPC 1D/2D z kwantyzacją
      i wspólną obsługą krawędzi, dekoder LPC 2D.],
    [Piotr Świtaj],
    [Metryki (energia, entropia), Huffman z książką kodową, ścieżka
      kodowania/weryfikacji oraz testy odtworzenia na wycinkach.],
    [Karolina Świątek],
    [Benchmarki, wykresy, tabele LPC 2D na 11 zdjęciach, redakcja
      sprawozdania Typst i wnioski.],
  ),
)

#v(0.35em)
#text(size: 9pt, fill: luma(90))[
  CSV: `sprawozdanie/dane/` (`benchmark_quick.csv`, `lpc_row_sweep.csv`,
  `lpc2d.csv`, `best_per_image.csv`, `mean_by_predictor.csv`).
]
