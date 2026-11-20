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

Przy pierwszych pomiarach LPC 1D wypadało zaskakująco słabo nawet na
gradientach. Dopiero przegląd mapy predykcji pokazał przyczynę w kodzie
(rozdział wyników). Bez tej poprawki część wniosków byłaby fałszywa.

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
    [`median`], [mediana$(A,B,C)$ – to nie jest MED],
    [`med`], [MED z JPEG-LS: mediana$(A,B,A+B-C)$],
    [`paeth`], [selektor Paetha (PNG)],
    [`lpc_row_*` / `lpc_col_*`], [LPC 1D, rząd 1–3, okno $B in {8,16,32,64}$],
    [`selector_b8`], [wybór $\{A,B,"planar"\}$ w bloku $8 times 8$],
  ),
  caption: [Predyktory w `predcomp` (bez osobnego strumienia współczynników).],
)

*LPC 1D.* Współczynniki z poprzedniego okna (najmniejsze kwadraty, bez wyrazu
wolnego), kwantowane do 10 bitów w zakresie ok. $[-2,2]$, żeby koder i dekoder
dostawały te same wartości niezależnie od drobnych różnic float między maszynami.
Pierwszy segment używa `left`.

*`selector_b8`.* Kandydat wybieramy według energii na dostępnej ramce:
wiersz nad blokiem, kolumna $b_x-1$ z wierszy powyżej oraz lewy fragment
bieżącego wiersza. Wnętrza bloku nie używamy.

== LPC 2D z informacją dodatkową

W bloku $B times B$ estymujemy
$ hat(I) = alpha A + beta B + gamma C + delta D $,
gdzie $D$ jest górnym-prawym sąsiadem (już znany z poprzedniego wiersza).
Przy prawej krawędzi obrazu ($x = w-1$) przyjmujemy $D = B$. Cztery
współczynniki po 10 bitów dają narzut $(4 dot 10)\/B^2$ bit/piksel.
Jest pełne sekwencyjne dekodowanie z siatki współczynników.

== Metryki

Energia na piksel $E\/N$; dla oryginału także po odjęciu średniej.
Entropia empiryczna $H$. Średnia długość Huffmana $overline(L)$ i
$Delta = overline(L) - H$.

Reszty mieszczą się w ${-255,...,255}$ (511 symboli), więc $H$ może
przekroczyć 8 bitów, mimo że nadal jest to jeden „bajtowy” sygnał różnicowy.
W PNG / JPEG-LS stosuje się redukcję modulo 256; dla szumu podajemy też $H$
po `mod 256`.

= Implementacja

Środowisko: `nix develop`. Przydatne komendy:

```
python -m predcomp.cli benchmark --predictors quick --summarize
python -m predcomp.cli benchmark --predictors lpc_row --data ...
python -m predcomp.cli lpc2d data/real
python -m predcomp.cli verify IMAGE --full-decode --crop 24x40 --lpc2d
```

`summarize` przy remisie wypisuje wszystkich zwycięzców (`a|b|c`) i liczy
wspólne wygrane. CSV ze sprawozdania: `sprawozdanie/dane/`.

Szybki test bezstratności sprawdza przyczynowość (predykcja na obrazie
uciętym od punktu cięcia). Sama równość „predykcja + reszta = obraz” wynika
z definicji kodowania i nie wystarcza. Pełne odtworzenie sekwencyjne
uruchomiliśmy na wycinku $24 times 40$ dla trybów z rejestru oraz dla LPC 2D
(`--lpc2d`).

= Wyniki

Benchmark `quick`: 18 obrazów $times$ 17 trybów.

== Histogramy

#figure(
  image("figs/gradient_h__left.png", width: 90%),
  caption: [`gradient_h` + `left`: oryginał płaski, reszty przy zerze.],
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
    [gradient_h], [5463], [4.0], [0.03], [0.03], [2.1],
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
  caption: [Gradient poziomy. `left` daje prawie stałą resztę 2 ($H approx 0.13$).
    LPC rzędu 2 dobrze przewiduje rampę (reszta 0), ale w pierwszym segmencie
    działa jak `left` (reszta 2): mieszanka zer i dwójek ma *wyższą* entropię
    ($H approx 0.59$) niż same dwójki. LPC rzędu 1 bez wyrazu wolnego w ogóle
    nie odtwarza stałego przyrostu ($H approx 2.03$). Entropia nie jest więc
    prostą miarą „jakości” predykcji.],
)

#figure(
  image("figs/noise_bars.png", width: 88%),
  caption: [Szum: entropia reszt powyżej $H_0$.],
)

#figure(
  image("figs/kodak_kodim15_bars.png", width: 88%),
  caption: [`kodim15`: najlepszy `med` ($4.36$). LPC wierszowe przegrywa z `left`
    ($4.96$ wobec $4.80$). LPC kolumnowe ($4.70$) jest lepsze od `left`, ale
    przegrywa z uczciwym punktem odniesienia `above` ($4.52$).],
)

#figure(
  image("figs/kodak_kodim08_bars.png", width: 88%),
  caption: [`kodim08`: znowu `med` / `paeth`; LPC wierszowe daleko z tyłu.],
)

== LPC 1D: znaleziona usterka i zależność od $B$

Na początku LPC na `kodim15` i na gradientach wyglądało podejrzanie: na rampie
poziomej entropia LPC bywała rzędu 1 bit/piksel, choć `left` miał ok. 0,13.
Sprawdziliśmy mapę predykcji w pierwszym segmencie wiersza – była wypełniona
zerami. W `_lpc_line` przy starcie segmentu współczynniki były puste, a
zastępstwo przez `left` uruchamiało się tylko dla `seg_start > 0`. Pierwszy
blok każdego wiersza nie dostawał więc żadnej sensownej predykcji.

Udział tego bloku rośnie, gdy obraz jest wąski albo $B$ duże (przy szerokości
512 i $B=16$ to kilka procent pikseli; na syntetyce $128 times 128$ wyraźnie
więcej). Po ustawieniu pierwszego segmentu na `left` wyniki wróciły do
sensownych wartości, ale LPC 1D nadal nie wygrywa z prostymi sąsiadami:
porównanie wierszowe z `left` i kolumnowe z `above` wypada na niekorzyść LPC
(krótkie okno, jeden wymiar, brak wyrazu wolnego).

Współczynniki LPC 1D są kwantowane tak jak w LPC 2D. Bez tego drobne różnice
arytmetyki zmiennoprzecinkowej między maszynami dawały inne zaokrąglone
predykcje – przy kodowaniu wstecznie adaptacyjnym plik mógłby się nie
odtworzyć.

#figure(
  image("figs/kodak_kodim15_lpc_sweep.png", width: 86%),
  caption: [LPC wierszowe na `kodim15`: $H$ względem długości bloku $B$ dla rzędów
    1–3. Większe $B$ zwykle pomaga; wysoki rząd przy małym $B$ szkodzi.],
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Rząd*], [$B=8$], [$B=16$], [$B=32$], [$B=64$],
    [1], [4.991], [4.963], [4.956], [4.924],
    [2], [5.126], [5.019], [4.953], [4.935],
    [3], [5.475], [5.133], [5.030], [4.988],
  ),
  caption: [Entropia reszt LPC 1D (wiersz) na `kodim15`.
    `left` = 4.797, `above` = 4.524, `med` = 4.356.],
)

== LPC 2D na jedenastu zdjęciach

Tu długość bloku ma konkretny koszt: im mniejszy blok, tym lepsze lokalne
dopasowanie, ale droższy zapis współczynników.

#figure(
  table(
    columns: (1.35fr, auto, auto, auto, auto),
    align: (left, center, center, center, center),
    inset: 4.5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [`med`], [LPC 2D], [*B*], [lepszy?],
    [kodim05], [6.01], [5.92], [16], [LPC],
    [kodim08], [5.55], [5.72], [32], [MED],
    [kodim13], [6.31], [6.17], [64], [LPC],
    [kodim15], [4.36], [4.26], [32], [LPC],
    [kodim19], [4.84], [4.76], [32], [LPC],
    [kodim23], [3.89], [3.72], [32], [LPC],
    [wiki\_building], [5.27], [5.30], [64], [MED],
    [wiki\_field], [5.56], [5.51], [64], [LPC],
    [wiki\_manuscript], [5.92], [5.94], [64], [MED],
    [wiki\_oak], [5.48], [5.44], [32], [LPC],
    [wiki\_portrait], [3.77], [3.50], [32], [LPC],
  ),
  caption: [LPC 2D: najlepsza suma $H$ + narzut wobec `med`. Wygrana LPC na
    8 z 11 zdjęć. MED zostaje na ostrych krawędziach (`kodim08`, fasada,
    rękopis). Optymalne $B$ to zwykle 32 albo 64.],
)

#figure(
  image("figs/kodak_kodim15_lpc2d.png", width: 86%),
  caption: [`kodim15`: krzywa $H$+narzut jest płaska w zakresie $B in [16,64]$
    (różnica 16 vs 32 ok. 0,02 bit/piksel). Minimum wypada przy 32.],
)

== Huffman

Na zdjęciach $Delta$ jest zwykle $0.02$–$0.05$ bit/piksel. Przy bardzo małej
entropii $overline(L)$ nie spada poniżej ok. 1, bo długości są całkowite.
Fragment książki dla `kodim15` + `med`:

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
    ok. 0,02 bit/piksel (poza $overline(L)$, bo liczymy tylko długości kodu
    właściwego).],
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
    [lpc_row_o1_b16], [4.76], [4.84], [+0.09], [1],
    [quadratic_row], [5.14], [5.31], [+0.17], [0],
  ),
  caption: [Średnie po 18 obrazach. \*remisy liczone jako wspólne zwycięstwa
    (np. na gradientach `med`/`paeth`/`planar` mają to samo $H$).],
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
niezależnym. Entropia reszt powyżej 8 bitów na szumie wynika z alfabetu
511-symbolowego, a nie z wyjścia poza ${-255,...,255}$; po `mod 256`
wracamy blisko $H_0$.

Najlepszy tryb bez informacji dodatkowej to `med` (często remisuje z `paeth`
i `planar` na syntetyce). Uczciwe porównanie LPC 1D to wiersz wobec `left`
i kolumna wobec `above` – w obu układach LPC przegrywa. LPC 2D z narzutem
współczynników wygrywa z `med` na 8 z 11 zdjęć; przegrywa tam, gdzie MED
korzysta z ostrych krawędzi. Sensowny zakres bloków to 32–64 (krzywa sumy
jest płaska już od 16).

Usterka pierwszego segmentu LPC 1D pokazała, że warto oglądać mapę
predykcji, a nie tylko tabelę $H$. Kwantyzacja współczynników LPC 1D jest
potrzebna do powtarzalności między maszynami. Bezstratność rejestru i LPC 2D
sprawdziliśmy przyczynowością oraz pełnym odtworzeniem na wycinkach.

= Podział zadań

#figure(
  table(
    columns: (auto, 1.15fr, 1.25fr),
    align: (left, left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Os.*], [*Zakres*], [*W sprawozdaniu*],
    [A], [Nix, I/O, próbki, dane], [cel, opis zbioru],
    [B], [predyktory, LPC 1D/2D, MED], [metody, poprawki LPC],
    [C], [metryki, Huffman, weryfikacja], [energia, Huffman, bezstratność],
    [D], [pomiary, wykresy, redakcja], [tabele, wnioski],
  ),
  caption: [Podział w zespole czteroosobowym. Udział: po 25%.],
)

#v(0.4em)
#text(size: 9pt, fill: luma(90))[
  CSV: `sprawozdanie/dane/` (`benchmark_quick.csv`, `lpc_row_sweep.csv`,
  `lpc2d.csv`, `best_per_image.csv`, `mean_by_predictor.csv`).
  Odtworzenie: `benchmark --summarize`, `lpc2d data/real`, benchmark z
  `--predictors lpc_row`.
]
