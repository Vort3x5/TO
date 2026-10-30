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


def verify_lossless(image: np.ndarray, predictor_name: str, *, full_decode: bool = False) -> bool:
    """
    Szybka weryfikacja: tożsamość encode + przyczynowość predyktora.
    full_decode=True uruchamia wolne sekwencyjne decode.
    """
    img = np.asarray(image, dtype=np.uint8)
    pred = get_predictor(predictor_name)
    residuals, recon = encode_with(img, pred)
    if not np.array_equal(img, recon):
        return False

    pred_q = quantize_pred(pred.fn(img))
    if not np.array_equal(pred_q + residuals, img.astype(np.int16)):
        return False

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
        decoded = decode(residuals, get_predictor(predictor_name).fn)
        if not np.array_equal(img, decoded):
            return False
    return True
