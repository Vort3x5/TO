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
      \[Imię Nazwisko\] – osoba A \
      \[Imię Nazwisko\] – osoba B \
      \[Imię Nazwisko\] – osoba C \
      \[Imię Nazwisko\] – osoba D
    ],
    align(left)[
      *Prowadzący* \
      \[dr inż. …\] \
      \
      *Repozytorium* \
      `predcomp` (Python, Nix)
    ],
  )
  #v(1.2cm)
  #text(size: 10pt)[Data: listopad 2026]
]

#pagebreak()

= Cel i wymagania

Celem było zaimplementowanie bezstratnej kompresji obrazów w skali szarości
metodą kodowania różnicowego: piksel przewidujemy z już znanych sąsiadów
i kodujemy resztę $e = I - hat(I)$. Z karty projektu wynikają trzy obowiązki:
kilka trybów predykcji (w tym 1–3 sąsiadów oraz LPC przy różnych długościach
bloków), porównanie oryginału z resztami (histogram, energia, entropia) oraz
statyczny Huffman zestawiony z entropią $H$.

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

Dla $I in {0,...,255}^(H times W)$ i predyktora $P$:
$ hat(I) = Q(P(I)), quad e = I - hat(I), $
gdzie $Q$ to zaokrąglenie z obcięciem do $[0,255]$. Predyktory w rejestrze są
przyczynowe w porządku rastrowym. LPC 2D dodatkowo przesyła współczynniki
bloku.

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
    [`lpc_row_*` / `lpc_col_*`], [LPC 1D, rząd 1–3, okno $B in {8,16,32,64}$],
    [`selector_b8`], [wybór $\{A,B,"planar"\}$ w bloku $8 times 8$],
  ),
  caption: [Predyktory w `predcomp`.],
)

*LPC 1D.* Współczynniki z poprzedniego okna (najmniejsze kwadraty, bez wyrazu
wolnego). Po estymacji stosujemy kwantyzację $hat(c) = "round"(c dot 256)\/256$
w zakresie $[-2,2]$ – typowe wartości $plus.minus 1$, $1\/2$, $plus.minus 2$
są reprezentowane dokładnie. Kwantyzacja zmniejsza ryzyko rozjazdu między
maszynami, ale go nie usuwa (wartość na granicy progu nadal może się
przeskoczyć); pewniejsze byłoby przesyłanie współczynników albo estymacja
wyłącznie na liczbach całkowitych. Pierwszy segment wiersza / kolumny używa
predykcji `left` (odpowiednio `above` po transpozycji).

*`selector_b8`.* Kandydat wybieramy według energii na dostępnej ramce:
wiersz nad blokiem, kolumna $b_x-1$ z wierszy powyżej oraz lewy fragment
bieżącego wiersza.

== LPC 2D z informacją dodatkową

W bloku $B times B$ estymujemy
$ hat(I) = alpha A + beta B + gamma C + delta D $,
gdzie $D$ jest górnym-prawym sąsiadem. Przy $x = w-1$ przyjmujemy $D = B$.
Cztery współczynniki po 11 bitów ($k = "round"(c dot 256)$) dają narzut
$(4 dot 11)\/B^2$ bit/piksel. Dekoder odtwarza obraz sekwencyjnie z reszt
i siatki współczynników.

== Metryki

Energia na piksel; dla oryginału także po odjęciu średniej.
Entropia empiryczna $H$. Średnia długość Huffmana $overline(L)$ oraz
$Delta = overline(L) - H$.

Reszty leżą w ${-255,...,255}$, czyli w alfabecie 511-symbolowym – stąd $H$
może przekroczyć 8 bitów. Po redukcji modulo 256 (jak w PNG / JPEG-LS)
entropia wraca bliżej $H_0$.

= Implementacja

Środowisko: `nix develop`.

```
python -m predcomp.cli benchmark --predictors quick --summarize
python -m predcomp.cli lpc2d data/real
python -m predcomp.cli verify IMAGE --full-decode --crop 24x40 --lpc2d
```

`summarize` przy remisie wypisuje wszystkich zwycięzców i liczy wspólne
wygrane. CSV: `sprawozdanie/dane/`.

Bezstratność rejestru sprawdzamy testem przyczynowości oraz pełnym
odtworzeniem na wycinku $24 times 40$. Dla LPC 2D domyślny wycinek to
$140 times 140$ (obejmuje granice kilku bloków także przy $B=64$).

= Wyniki

Benchmark `quick`: 18 obrazów $times$ 17 trybów.

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
    [smooth_blobs], [2202], [175], [1.5], [4.2], [14],
    [kodim15], [6712], [242], [113], [82], [238],
    [kodim08], [3802], [1084], [368], [273], [1087],
    [manuscript], [1940], [887], [772], [517], [830],
    [noise], [5468], [11030], [14098], [10941], [9946],
  ),
  caption: [$E_c$: oryginał po odjęciu średniej. `LPC o1` = `lpc_row_o1_b16`.],
)

== Porównanie trybów

#figure(
  image("figs/gradient_h_bars.png", width: 88%),
  caption: [Gradient poziomy. Przy `left` reszta jest prawie stała ($approx 2$),
    więc $H$ jest niskie. LPC rzędu 2 na dalszych segmentach przewiduje rampę
    prawie bezbłędnie, ale pierwszy segment nadal zachowuje się jak `left`:
    w histogramie pojawiają się jednocześnie zera i dwójki, a $H$ rośnie
    (ok. 0,59 wobec 0,13). LPC rzędu 1 bez wyrazu wolnego nie modeluje
    stałego przyrostu ($H approx 2.08$). Niższa energia błędu nie musi więc
    oznaczać niższej entropii.],
)

#figure(
  image("figs/noise_bars.png", width: 88%),
  caption: [Szum: entropia reszt powyżej $H_0$.],
)

#figure(
  image("figs/kodak_kodim15_bars.png", width: 88%),
  caption: [`kodim15`: najniższe $H$ ma `med` ($4.36$). LPC wierszowe
    ($4.96$) ustępuje `left` ($4.80$); LPC kolumnowe ($4.70$) ustępuje
    `above` ($4.52$).],
)

#figure(
  image("figs/kodak_kodim08_bars.png", width: 88%),
  caption: [`kodim08`: `med` i `paeth` przed pozostałymi trybami.],
)

== LPC 1D: poprawka w kodzie i zależność od $B$

W pierwszej wersji LPC 1D na gradientach i części zdjęć wypadało wyraźnie
gorzej niż `left`. Przy przeglądzie implementacji okazało się, że w
`_lpc_line` pierwszy segment wiersza zostawiał zerową predykcję: gałąź
zastępcza ustawiała `left` tylko dla `seg_start > 0`. Po poprawce (pierwszy
segment = `left`) wyniki wróciły do sensownych wartości.

Porównanie z sąsiadem w tym samym kierunku: na 11 zdjęciach rzeczywistych
LPC wierszowe przegrywa z `left` we wszystkich przypadkach; LPC kolumnowe
wygrywa z `above` tylko na `wiki_portrait`. Na syntetyce LPC bywa lepsze –
m.in. na `naturalish`, na szumie oraz na części gradientów (np. remis
`lpc_row_o1_b16` na `gradient_v`).

Kwantyzacja $c\/256$ ma swój koszt na skomplikowanych obrazach (drobne
pogorszenie względem czystego float), ale przywraca poprawne zachowanie na
rampach i szachownicy, gdzie potrzebne są dokładne $1$, $1\/2$ albo $2$.

#figure(
  image("figs/kodak_kodim15_lpc_sweep.png", width: 86%),
  caption: [LPC wierszowe na `kodim15`: $H$ względem $B$ dla rzędów 1–3.],
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Rząd*], [$B=8$], [$B=16$], [$B=32$], [$B=64$],
    [1], [4.986], [4.963], [4.952], [4.924],
    [2], [5.123], [5.019], [4.959], [4.939],
    [3], [5.475], [5.132], [5.030], [4.987],
  ),
  caption: [Entropia reszt LPC 1D (wiersz) na `kodim15`.
    `left` = 4.797, `above` = 4.524, `med` = 4.356.],
)

== LPC 2D na jedenastu zdjęciach

#figure(
  table(
    columns: (1.35fr, auto, auto, auto, auto),
    align: (left, center, center, center, center),
    inset: 4.5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [`med`], [LPC 2D], [*B*], [lepszy],
    [kodim05], [6.01], [5.93], [32], [LPC],
    [kodim08], [5.55], [5.72], [32], [MED],
    [kodim13], [6.31], [6.17], [64], [LPC],
    [kodim15], [4.36], [4.26], [32], [LPC],
    [kodim19], [4.84], [4.77], [32], [LPC],
    [kodim23], [3.89], [3.72], [32], [LPC],
    [wiki\_building], [5.27], [5.30], [32], [MED],
    [wiki\_field], [5.56], [5.51], [64], [LPC],
    [wiki\_manuscript], [5.92], [5.94], [64], [MED],
    [wiki\_oak], [5.48], [5.44], [32], [LPC],
    [wiki\_portrait], [3.77], [3.50], [64], [LPC],
  ),
  caption: [LPC 2D: najlepsza suma $H$ + narzut wobec `med`. LPC wygrywa na
    8 z 11 zdjęć; MED zostaje przy ostrych liniach (`kodim08`, fasada,
    rękopis). Najczęściej wybierane $B$ to 32 lub 64.],
)

#figure(
  image("figs/kodak_kodim15_lpc2d.png", width: 86%),
  caption: [`kodim15`: suma $H$+narzut zmienia się niewiele między $B=16$ a
    $B=64$ (różnica 16 vs 32 ok. 0,03). Na innych obrazach spread bywa większy
    – np. na `wiki_building` różnica $B=16$ wobec $B=64$ to ok. 0,09.],
)

== Huffman

Na zdjęciach $Delta$ jest zwykle $0.02$–$0.05$ bit/piksel. Przy bardzo małej
entropii $overline(L)$ nie spada poniżej ok. 1. Fragment książki dla
`kodim15` + `med`:

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
    [med], [*4.05*], [*4.27*], [+0.23], [*12*],
    [paeth], [4.10], [4.33], [+0.23], [3],
    [selector_b8], [4.14], [4.34], [+0.20], [1],
    [planar], [4.19], [4.43], [+0.24], [5],
    [avg2], [4.29], [4.47], [+0.17], [1],
    [left], [4.44], [4.64], [+0.19], [0],
    [lpc_col_o2_b16], [4.54], [4.68], [+0.14], [1],
    [lpc_row_o2_b16], [4.67], [4.79], [+0.12], [1],
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

Najlepszy tryb bez informacji dodatkowej to `med`. LPC 1D na zdjęciach
rzeczywistych zwykle ustępuje sąsiadowi w tym samym kierunku; wyjątki i
wygrane pojawiają się głównie na syntetyce (`naturalish`, szum, wybrane
gradienty). LPC 2D z narzutem współczynników wygrywa z `med` na 8 z 11
zdjęć; przegrywa przy ostrych liniach. Typowy dobry rozmiar bloku to 32 lub
64 – zależność od $B$ bywa płaska (jak na `kodim15`), ale nie zawsze.

Przy przeglądzie kodu wyszła usterka zerowego pierwszego segmentu LPC 1D;
po poprawce i kwantyzacji $c\/256$ wyniki na rampach wróciły do oczekiwanych.
Bezstratność rejestru i LPC 2D sprawdziliśmy przyczynowością oraz pełnym
odtworzeniem na wycinkach ($24 times 40$ oraz $140 times 140$ dla LPC 2D).

= Podział zadań

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Os.*], [*Co zrobiła*],
    [A],
    [Środowisko Nix, wczytywanie/zapis PNG, generator próbek syntetycznych,
      pobieranie Kodak/Wikimedia i opis zbioru w sprawozdaniu.],
    [B],
    [Predyktory (sąsiedzi, MED, Paeth, selector), LPC 1D/2D z kwantyzacją
      współczynników, poprawka pierwszego segmentu i dekoder LPC 2D.],
    [C],
    [Metryki (energia, entropia), Huffman z książką kodową, ścieżka
      kodowania/weryfikacji oraz testy odtworzenia na wycinkach.],
    [D],
    [Benchmarki, wykresy, tabele LPC 2D na 11 zdjęciach, redakcja
      sprawozdania Typst i wnioski.],
  ),
  caption: [Podział pracy. Udział orientacyjny: po ok. 25%.],
)

#v(0.35em)
#text(size: 9pt, fill: luma(90))[
  CSV: `sprawozdanie/dane/` (`benchmark_quick.csv`, `lpc_row_sweep.csv`,
  `lpc2d.csv`, `best_per_image.csv`, `mean_by_predictor.csv`).
]
