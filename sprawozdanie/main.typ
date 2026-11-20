// Technika obrazowa — sprawozdanie z projektu (temat 3)
// Kompilacja: typst compile sprawozdanie/main.typ

#set document(
  title: "Kompresja obrazu — kodowanie różnicowe/predykcyjne",
  author: "Zespół TO",
)
#set page(paper: "a4", margin: (x: 2.2cm, y: 2.4cm), numbering: "1")
#set text(lang: "pl", font: "Liberation Serif", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true, leading: 0.65em)
#show heading: set block(above: 1.15em, below: 0.55em)
#show figure: set block(breakable: false)
#show link: underline

#align(center)[
  #text(size: 12pt)[Politechnika Warszawska – Wydział Elektroniki i Technik Informacyjnych]

  #v(0.7cm)
  #text(size: 14pt, weight: "bold")[Technika obrazowa – projekt]

  #v(0.35cm)
  #text(size: 17pt, weight: "bold")[
    Kompresja obrazu z wykorzystaniem\
    kodowania różnicowego / predykcyjnego
  ]

  #v(0.5cm)
  #text(size: 11pt)[Temat 3, semestr zimowy 2026/27]

  #v(1.1cm)
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

  #v(1.3cm)
  #text(size: 10pt)[Data: listopad 2026]
]

#pagebreak()

= Cel i wymagania

Celem było zaimplementowanie bezstratnej kompresji obrazów w skali szarości
metodą kodowania różnicowego: piksel jest przewidywany z już znanych sąsiadów,
a dalej kodujemy resztę $e = I - hat(I)$. Zgodnie z kartą projektu sprawdzamy
kilka trybów predykcji (w tym 1, 2 i 3 sąsiadów oraz LPC przy różnych długościach
bloków), porównujemy oryginał z resztami pod kątem histogramu, energii i
entropii oraz budujemy statyczny kod Huffmana i zestawiamy jego średnią długość
z $H$.

W trakcie pracy wyszedł istotny błąd w LPC 1D (pierwszy segment wiersza miał
zerową predykcję). Opisujemy go w rozdziale wyników, bo bez poprawki wnioski
o LPC byłyby mylące.

= Dane testowe

Dwa zestawy PNG w skali szarości.

*Syntetyczne* (`data/samples/`, $128 times 128$): gradient poziomy i pionowy,
szachownica, krawędzie, gładkie plamy, szum i.i.d., pole „naturalish”
(widmo $1\/f$ z rozmyciem). Mają kontrolowaną strukturę, więc widać, kiedy
predykcja ma prawo działać, a kiedy nie.

*Rzeczywiste* (`data/real/`, dłuższy bok $lt.eq 512$): sześć klatek Kodak
(`kodim05/08/13/15/19/23`) oraz pięć obrazów z Wikimedia Commons (portret,
tekstura, fasada, rękopis, listowie). Źródła i licencje: `data/real/SOURCES.md`.

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
gdzie $Q$ to zaokrąglenie z obcięciem do $[0,255]$. Predyktory są przyczynowe
w porządku rastrowym, więc dekoder odtwarza $I$ z samego ciągu reszt
(ewentualnie z dodatkowymi współczynnikami przy LPC 2D).

== Tryby bez side-info

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Nazwa*], [*Opis*],
    [`left` / `above`], [jeden sąsiad: $A$ lub $B$],
    [`two_left` / `three_left`], [średnia dwóch lub trzech pikseli w wierszu],
    [`avg2` / `avg3`], [$(A+B)\/2$, $(A+B+C)\/3$],
    [`planar`], [$A+B-C$],
    [`weighted`], [$0.75 A + 0.25 B$],
    [`quadratic_row`], [ekstrapolacja kwadratowa w wierszu],
    [`median`], [mediana$(A,B,C)$ – nie mylić z MED],
    [`med`], [MED z JPEG-LS: mediana$(A,B,A+B-C)$],
    [`paeth`], [selektor Paetha (PNG)],
    [`lpc_row_*` / `lpc_col_*`], [LPC 1D, rząd 1–3, okno $B in {8,16,32,64}$],
    [`selector_b8`], [wybór $\{A,B,"planar"\}$ w bloku $8 times 8$],
  ),
  caption: [Zestaw predyktorów w rejestrze `predcomp`.],
)

*LPC 1D (bez side-info).* W segmencie długości $B$ współczynniki liczymy
z poprzedniego okna (najmniejsze kwadraty, bez wyrazu wolnego) i stosujemy
do bieżącego segmentu. Dekoder powtarza tę samą estymację. Pierwszy segment
(i każda nieudana estymacja) używa predykcji `left` – wcześniej był tu błąd
(patrz wyniki).

*`selector_b8`.* Kandydat wybieramy według energii błędu na *dostępnej ramce
przyczynowej*: wiersz nad blokiem, ewentualnie kolumna $b_x-1$ z wierszy
*powyżej* bloku oraz lewy fragment bieżącego wiersza przy $b_x>0$. Nie
korzystamy z wnętrza bloku.

== LPC 2D z side-info

Osobny wariant: w bloku $B times B$ estymujemy
$ hat(I) = alpha A + beta B + gamma C + delta D $,
gdzie $D$ to górny-prawy (już znany z poprzedniego wiersza). Cztery
współczynniki kwantujemy po 10 bitów i przesyłamy. Narzut:
$ (4 dot 10)\/B^2 $ bit/piksel. Pokazuje to realny kompromis: mały blok lepiej
dopasowuje lokalnie, ale drożej kosztuje zapis współczynników.

== Metryki

- energia na piksel $E\/N = (1\/N) sum_i x_i^2$; dla oryginału podajemy też
  energię po odjęciu średniej (inaczej porównanie z resztami jest trywialne,
  bo średnia jasność dominuje);
- entropia empiryczna $H = -sum_v p_v log_2 p_v$;
- średnia długość Huffmana $overline(L)$; różnica $Delta = overline(L) - H$.

Przy szumie reszty mogą wyjść poza ${-255,...,255}$ szerzej niż bajt;
entropia bywa wtedy $>8$. W PNG / JPEG-LS reszty i tak redukuje się modulo 256 –
dla porównania podajemy też $H$ po `mod 256`.

= Implementacja

Python (NumPy, Pillow, Matplotlib), środowisko: `nix develop`.
Główne komendy:

```
python -m predcomp.cli benchmark --predictors quick --summarize
python -m predcomp.cli benchmark --data ... --predictors lpc_row
python -m predcomp.cli lpc2d IMAGE
python -m predcomp.cli summarize --csv results/benchmark.csv
python -m predcomp.cli verify IMAGE --full-decode --crop 24x40
```

`summarize` zapisuje `best_per_image.csv` i `mean_by_predictor.csv`.
Kopie CSV użyte w tym sprawozdaniu leżą w `sprawozdanie/dane/`
(katalog `results/` jest w `.gitignore`).

Szybki test `verify` sprawdza przyczynowość (predykcja na obrazie obciętym
od punktu cięcia). Tożsamość `pred + e = I` wynika z definicji encode i sama
z siebie nic nie dowodzi. Pełne sekwencyjne decode uruchomiliśmy na wycinku
$24 times 40$ dla `left`, `planar`, `paeth`, `med`, `selector_b8` oraz LPC
wiersz/kolumna – wszystkie warianty: OK.

= Wyniki

Benchmark `quick`: 18 obrazów, 17 trybów (w tym `med` i poprawione LPC).

== Histogramy

#figure(
  image("figs/gradient_h__left.png", width: 92%),
  caption: [`gradient_h` + `left`: płaski histogram oryginału, reszty skupione
    przy zerze ($H approx 0.13$).],
)

#figure(
  image("figs/noise__planar.png", width: 92%),
  caption: [`noise` + `planar`: reszty szersze niż oryginał ($H$: $7.99 -> 8.85$).
    Po redukcji modulo 256 wychodzi $H approx 7.99$, więc „szkoda” znika –
    to artefakt zakresu $e in [-255,255]$, a nie magia predykcji.],
)

#figure(
  image("figs/kodak_kodim15__med.png", width: 92%),
  caption: [`kodim15` + `med`: spadek entropii z $7.48$ do $4.36$ bit/piksel.],
)

#figure(
  image("figs/edges__paeth.png", width: 92%),
  caption: [`edges` + `paeth`: niska entropia oryginału i jeszcze niższa reszt.],
)

#figure(
  image("figs/smooth_blobs__planar.png", width: 92%),
  caption: [`smooth_blobs` + `planar`: gładkie obszary – reszty prawie puste.],
)

== Energia (na piksel)

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
  caption: [Energia na piksel. $E_c$ – oryginał po odjęciu średniej.
    Reszty: energia bez dodatkowego centrowania (średnia reszt jest bliska 0).
    `LPC o1` = `lpc_row_o1_b16`. Na szumie energia reszt nie spada poniżej
    energii oryginału.],
)

== Porównanie trybów

#figure(
  image("figs/gradient_h_bars.png", width: 90%),
  caption: [Gradient poziomy: proste tryby i poprawione LPC dają $H < 0.3$
    (wcześniej LPC wyglądało źle przez bug pierwszego bloku).],
)

#figure(
  image("figs/noise_bars.png", width: 90%),
  caption: [Szum: entropia reszt powyżej $H_0$ (linia przerywana).],
)

#figure(
  image("figs/kodak_kodim15_bars.png", width: 90%),
  caption: [`kodim15`: wygrywa `med` ($H approx 4.36$), potem `paeth` /
    `selector_b8`. LPC 1D zostaje za `left`.],
)

#figure(
  image("figs/kodak_kodim08_bars.png", width: 90%),
  caption: [`kodim08`: znowu `med` / `paeth` wyraźnie przed LPC.],
)

#figure(
  image("figs/smooth_blobs_bars.png", width: 90%),
  caption: [Gładkie plamy: `planar` i `selector_b8` są mocne; LPC 1D średnio.],
)

== LPC 1D: bug i sweep po $B$

*Co było nie tak.* W `_lpc_line` przy `seg_start == 0` współczynniki były
`None`, a gałąź awaryjna ustawiała predykcję `left` tylko gdy
`seg_start > 0`. Pierwszy segment dostawał zera, więc reszta równała się
wartości piksela. Przy $B=16$ i szerokości 512 to ok. 3% pikseli, przy
$B=32$ ok. 6%, na syntetyce $128 times 128$ nawet 12,5%. Na `kodim15`
w pierwszym bloku predykcja była zerowa w praktycznie 100% pozycji.
Stąd m.in. wynik `lpc_row_o1_b16` gorszy od `left` oraz podejrzane $H$
na gradientach.

Po poprawce (pierwszy blok = `left`) na `kodim15`: `left` ma $H approx 4.80$,
a `lpc_row_o1_b16` ok. $4.96$. LPC wciąż przegrywa. Sensowne wyjaśnienie:
estymacja na 8–64 próbkach poprzedniego segmentu, tylko w 1D, bez wyrazu
wolnego i bez side-info – lokalny model jest zbyt ubogi i zbyt hałaśliwy,
żeby systematycznie bić prosty `left` / `med`.

#figure(
  image("figs/kodak_kodim15_lpc_sweep.png", width: 88%),
  caption: [LPC wierszowe na `kodim15`: entropia vs długość bloku $B$ dla rzędów
    1–3. Większe $B$ zwykle pomaga (stabilniejsza estymacja), wyższy rząd przy
    małym $B$ szkodzi.],
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Rząd*], [$B=8$], [$B=16$], [$B=32$], [$B=64$],
    [1], [4.985], [4.960], [4.949], [4.922],
    [2], [5.079], [4.986], [4.941], [4.933],
    [3], [5.388], [5.086], [4.997], [4.971],
  ),
  caption: [Entropia reszt LPC 1D (wiersz) na `kodim15`. Dla porównania:
    `left` = 4.797, `med` = 4.356.],
)

== LPC 2D z side-info

Tu długość bloku ma czytelny sens ekonomiczny.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Blok*], [$H$ reszt], [narzut], [$H$ + narzut],
    [$8 times 8$], [4.033], [0.630], [4.664],
    [$16 times 16$], [4.119], [0.161], [4.280],
    [$32 times 32$], [4.226], [0.040], [4.266],
    [$64 times 64$], [4.312], [0.011], [4.323],
  ),
  caption: [LPC 2D na `kodim15`, 4 współczynniki × 10 bitów.
    `paeth` bez side-info: $H approx 4.41$; `med`: $4.36$.],
)

#figure(
  image("figs/kodak_kodim15_lpc2d.png", width: 88%),
  caption: [Kompromis LPC 2D: spadek narzutu z rozmiarem bloku vs wzrost $H$ reszt.
    Minimum sumy wypada około $32 times 32$.],
)

== Huffman

Na zdjęciach $Delta$ jest zwykle $0.02$–$0.05$ bit/piksel. Przy bardzo małej
entropii (gradient, krawędzie) $overline(L)$ nie spada poniżej ok. 1 bit/symbol,
bo długości są całkowite.

Fragment książki kodowej dla `kodim15` + `med` (najczęstsze symbole):

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*$e$*], [*liczność*], [*długość*], [*kod*],
    [0], [33797], [2], [`00`],
    [+1], [23397], [3], [`101`],
    [−1], [22982], [3], [`100`],
    [+2], [12586], [4], [`1101`],
    [−2], [12264], [4], [`1100`],
    [+3], [7265], [5], [`11110`],
    [−3], [7193], [5], [`11101`],
    [+4], [4898], [5], [`01100`],
  ),
  caption: [Statyczny Huffman na resztach. Alfabet ma 242 symbole; szacunek
    narzutu na tabelę (symbol + długość) to rzędu 0.02 bit/piksel – w $overline(L)$
    go nie ma, bo liczymy tylko długości kodów payloadu.],
)

== Zestawienie zbiorcze

#figure(
  table(
    columns: (1.45fr, auto, 1.35fr, auto, auto),
    align: (left, center, left, center, center),
    inset: 4.5pt,
    stroke: 0.5pt + luma(180),
    [*Obraz*], [$H_0$], [*Najlepszy*], [$H$], [$overline(L)$],
    [checker], [1.00], [planar], [0.13], [1.02],
    [edges], [2.03], [selector_b8], [0.16], [1.05],
    [gradient\_h/v], [7.00], [planar / med], [0.07], [1.01],
    [smooth_blobs], [5.48], [planar], [1.21], [1.45],
    [naturalish], [6.89], [planar], [4.80], [4.83],
    [noise], [7.99], [avg3\*], [8.42], [8.44],
    [kodim05], [7.41], [med], [6.01], [6.04],
    [kodim08], [7.69], [med], [5.55], [5.58],
    [kodim13], [7.48], [weighted], [6.26], [6.28],
    [kodim15], [7.48], [med], [4.36], [4.38],
    [kodim19], [7.44], [med], [4.84], [4.87],
    [kodim23], [7.31], [med], [3.89], [3.94],
    [wiki\_building], [7.49], [med], [5.27], [5.30],
    [wiki\_field], [7.57], [med], [5.56], [5.60],
    [wiki\_manuscript], [7.04], [med], [5.92], [5.95],
    [wiki\_oak], [6.70], [med], [5.48], [5.51],
    [wiki\_portrait], [6.45], [avg2], [3.66], [3.69],
  ),
  caption: [Zwycięzca wg $H$ reszt. \*na szumie „najlepszy” i tak zwiększa $H$
    względem $H_0$.],
)

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Predyktor*], [śr. $H$], [śr. $overline(L)$], [śr. $Delta$], [wygrane],
    [med], [*4.05*], [*4.27*], [+0.23], [*9*],
    [paeth], [4.10], [4.33], [+0.23], [0],
    [selector_b8], [4.14], [4.34], [+0.20], [1],
    [planar], [4.19], [4.43], [+0.24], [5],
    [avg2], [4.29], [4.47], [+0.17], [1],
    [left], [4.44], [4.64], [+0.19], [0],
    [lpc_row_o1_b16], [4.76], [4.85], [+0.09], [0],
    [quadratic_row], [5.14], [5.31], [+0.17], [0],
  ),
  caption: [Średnie po 18 obrazach (wybrane tryby). Po dodaniu MED i poprawce LPC
    liderem jest `med`.],
)

#figure(
  grid(
    columns: 2,
    gutter: 0.45cm,
    [
      #image("figs/res_gradient_h_left.png", width: 100%)
      #align(center, text(size: 9pt)[gradient_h / left (+128)])
    ],
    [
      #image("figs/res_kodim15_med.png", width: 100%)
      #align(center, text(size: 9pt)[kodim15 / med (+128)])
    ],
  ),
  caption: [Mapy reszt (+128). Gradient: prawie jednolity szary. Portret: błędy
    głównie na krawędziach i fakturze.],
)

= Wnioski

Predykcja ma sens przy korelacji przestrzennej. Na gradientach i gładkich
obszarach $H$ i energia reszt spadają ostro; na szumie i.i.d. rosną. Sam fakt,
że surowa entropia reszt przekracza 8 bitów, wynika głównie z zakresu
$e in [-255,255]$ – po `mod 256` wracamy blisko $H_0$.

Na tym zbiorze najlepszy ogólny tryb bez side-info to `med` (JPEG-LS), potem
`paeth` i `selector_b8`. Zwykła `median(A,B,C)` jest wyraźnie słabsza od MED.

LPC 1D bez side-info, po naprawieniu pierwszego bloku, nadal nie bije `left` /
`med` na typowych zdjęciach. Krótkie okno, jeden wymiar i brak wyrazu wolnego
to za mało. Dopiero LPC 2D z przesyłanymi współczynnikami pokazuje, po co w ogóle
zmieniać długość bloku: przy $32 times 32$ suma $H$ + narzut na `kodim15`
wychodzi ok. 4.27, poniżej `paeth` (4.41).

Huffman trzyma się blisko entropii na resztach zdjęć; przy mocno skupionych
resztach limituje go całkowitość długości. Narzut na zapis alfabetu trzeba
pamiętać osobno – w naszych liczbach go nie ma.

Bezstratność potwierdziliśmy testem przyczynowości oraz pełnym decode na
wycinkach, nie samym sprawdzeniem `pred+e=I`.

= Podział zadań

#figure(
  table(
    columns: (auto, 1.15fr, 1.35fr),
    align: (left, left, left),
    inset: 5pt,
    stroke: 0.5pt + luma(180),
    [*Os.*], [*Zakres*], [*W sprawozdaniu*],
    [A], [`flake.nix`, I/O, `samples`, szkielet CLI, dane], [cel, opis zbioru],
    [B], [predyktory, LPC 1D/2D, `med`, selector], [opis metod, poprawka LPC],
    [C], [metryki, Huffman, codec, verify], [energia, Huffman, bezstratność],
    [D], [benchmark, wykresy, redakcja], [tabele, wnioski],
  ),
  caption: [Podział pracy w zespole czteroosobowym.],
)

Szacunkowy udział: A 25%, B 25%, C 25%, D 25%.

#v(0.8em)
#align(center, text(size: 9pt, fill: luma(100))[
  Pełne CSV: `sprawozdanie/dane/` (`benchmark_quick.csv`, `lpc_row_sweep.csv`,
  `lpc2d.csv`, `best_per_image.csv`, `mean_by_predictor.csv`). \
  Odtworzenie: `python -m predcomp.cli benchmark --summarize` oraz
  `lpc2d` / benchmark z `--predictors lpc_row`.
])
