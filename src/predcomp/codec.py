"""Bezstratne kodowanie różnicowe na mapach predykcji."""

from __future__ import annotations

import numpy as np

from .predictors import PredictMap, Predictor, get_predictor


def quantize_pred(pred: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(pred), 0, 255).astype(np.int16)


def encode(image: np.ndarray, predict_map: PredictMap) -> tuple[np.ndarray, np.ndarray]:
    """reszty = obraz − Q(predykcja); rekonstrukcja z encode = kopia obrazu."""
    img = np.asarray(image, dtype=np.uint8)
    pred_q = quantize_pred(predict_map(img))
    residuals = img.astype(np.int16) - pred_q
    return residuals, img.copy()


def encode_with(image: np.ndarray, predictor: Predictor) -> tuple[np.ndarray, np.ndarray]:
    return encode(image, predictor.fn)


def decode(residuals: np.ndarray, predict_map: PredictMap) -> np.ndarray:
    """
    Sekwencyjna rekonstrukcja (przyczynowa).

    Koszt O(H·W) wywołań predict_map — OK do weryfikacji na małych obrazach;
    benchmark używa wyłącznie encode.
    """
    res = np.asarray(residuals, dtype=np.int16)
    h, w = res.shape
    recon = np.zeros((h, w), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            pred_q = int(np.clip(np.rint(predict_map(recon)[y, x]), 0, 255))
            val = pred_q + int(res[y, x])
            if not 0 <= val <= 255:
                raise ValueError(
                    f"rekonstrukcja poza zakresem przy ({x},{y}): "
                    f"pred={pred_q} res={int(res[y, x])} → {val}"
                )
            recon[y, x] = np.uint8(val)
    return recon


def verify_lossless(
    image: np.ndarray,
    predictor_name: str,
    *,
    full_decode: bool = False,
    crop: tuple[int, int] | None = None,
) -> bool:
    """
    Weryfikacja:
    1) przyczynowość (predykcja na obrazie obciętym od punktu cięcia),
    2) opcjonalnie pełne sekwencyjne decode (wolne; sensowne na wycinku).

    Samo `pred_q + residuals == img` wynika z definicji encode i nie jest
    wystarczającym testem bezstratności.
    """
    img = np.asarray(image, dtype=np.uint8)
    if crop is not None:
        ch, cw = crop
        img = img[:ch, :cw]
    pred = get_predictor(predictor_name)
    residuals, _ = encode_with(img, pred)

    h, w = img.shape
    y0, x0 = max(h // 2, 1), max(w // 2, 1)
    masked = img.copy()
    masked[y0, x0:] = 0
    masked[y0 + 1 :, :] = 0
    full = pred.fn(img)
    part = pred.fn(masked)
    if not (np.allclose(full[:y0], part[:y0]) and np.allclose(full[y0, :x0], part[y0, :x0])):
        return False

    if full_decode:
        decoded = decode(residuals, pred.fn)
        if not np.array_equal(img, decoded):
            return False
    return True
