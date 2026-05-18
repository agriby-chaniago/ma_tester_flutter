from __future__ import annotations

import base64
from collections import deque
from io import BytesIO
from typing import Iterable

import numpy as np
from PIL import Image, ImageFilter


def image_to_png_bytes(arr_u8: np.ndarray) -> bytes:
    img = Image.fromarray(arr_u8)
    buff = BytesIO()
    img.save(buff, format="PNG")
    return buff.getvalue()


def png_data_url(arr_u8: np.ndarray) -> str:
    b = image_to_png_bytes(arr_u8)
    return "data:image/png;base64," + base64.b64encode(b).decode("ascii")


def npy_b64(arr: np.ndarray) -> str:
    buff = BytesIO()
    np.save(buff, arr)
    return base64.b64encode(buff.getvalue()).decode("ascii")


def create_overlay(rgb_u8: np.ndarray, mask_u8: np.ndarray) -> np.ndarray:
    overlay = rgb_u8.copy()
    # Emphasize detections in red while keeping background visible.
    red = np.maximum(overlay[:, :, 0], (mask_u8 > 0).astype(np.uint8) * 255)
    overlay[:, :, 0] = red
    overlay[:, :, 1] = np.where(mask_u8 > 0, overlay[:, :, 1] * 0.5, overlay[:, :, 1]).astype(np.uint8)
    overlay[:, :, 2] = np.where(mask_u8 > 0, overlay[:, :, 2] * 0.5, overlay[:, :, 2]).astype(np.uint8)
    return overlay


def preprocess_probability(rgb_u8: np.ndarray) -> np.ndarray:
    arr = rgb_u8
    if arr.ndim == 2:
        arr = np.stack([arr, arr, arr], axis=-1)       # (H,W) → (H,W,3)
    elif arr.ndim == 3 and arr.shape[2] == 1:
        arr = np.repeat(arr, 3, axis=2)                # (H,W,1) → (H,W,3)
    elif arr.ndim == 3 and arr.shape[2] > 3:
        arr = arr[:, :, :3]                            # RGBA/multi → (H,W,3)
    if arr.ndim != 3 or arr.shape[2] < 3:
        raise ValueError(f"Unsupported image shape after normalization: {arr.shape}")

    green = arr[:, :, 1].astype(np.float32)
    min_v = float(green.min())
    max_v = float(green.max())
    if max_v - min_v < 1e-6:
        norm = np.zeros_like(green, dtype=np.float32)
    else:
        norm = (green - min_v) / (max_v - min_v)

    enhanced = np.power(norm, 0.8)
    # uint8 round-trip required for PIL GaussianBlur; quantization acceptable for 8-bit fundus input
    smooth = np.array(
        Image.fromarray((enhanced * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(radius=2)
        ),
        dtype=np.float32,
    ) / 255.0
    smooth = np.nan_to_num(smooth, nan=0.0, posinf=1.0, neginf=0.0)

    proba = np.clip(enhanced - smooth + 0.5, 0.0, 1.0)
    return proba


def connected_components_areas(mask_bool: np.ndarray) -> list[int]:
    h, w = mask_bool.shape
    visited = np.zeros((h, w), dtype=np.uint8)
    areas: list[int] = []

    for y in range(h):
        for x in range(w):
            if not mask_bool[y, x] or visited[y, x]:
                continue

            q = deque([(y, x)])
            visited[y, x] = 1
            area = 0

            while q:
                cy, cx = q.popleft()
                area += 1

                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if ny < 0 or ny >= h or nx < 0 or nx >= w:
                        continue
                    if visited[ny, nx] or not mask_bool[ny, nx]:
                        continue
                    visited[ny, nx] = 1
                    q.append((ny, nx))

            areas.append(area)

    return sorted(areas, reverse=True)


def remove_small_components(mask_u8: np.ndarray, min_area: int) -> np.ndarray:
    mask_bool = mask_u8 > 0
    h, w = mask_bool.shape
    visited = np.zeros((h, w), dtype=np.uint8)
    out = np.zeros((h, w), dtype=np.uint8)

    for y in range(h):
        for x in range(w):
            if not mask_bool[y, x] or visited[y, x]:
                continue

            q = deque([(y, x)])
            visited[y, x] = 1
            coords: list[tuple[int, int]] = []

            while q:
                cy, cx = q.popleft()
                coords.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if ny < 0 or ny >= h or nx < 0 or nx >= w:
                        continue
                    if visited[ny, nx] or not mask_bool[ny, nx]:
                        continue
                    visited[ny, nx] = 1
                    q.append((ny, nx))

            if len(coords) >= min_area:
                for cy, cx in coords:
                    out[cy, cx] = 255

    return out


def compute_statistics(mask_u8: np.ndarray) -> dict:
    if mask_u8.ndim == 3:
        mask_u8 = mask_u8[:, :, 0]
    h, w = mask_u8.shape
    mask_bool = mask_u8 > 0
    areas = connected_components_areas(mask_bool)
    total_area = int(mask_bool.sum())
    total_px = max(1, h * w)

    if areas:
        largest = int(areas[0])
        smallest = int(areas[-1])
        mean_sz = float(sum(areas) / len(areas))
    else:
        largest = 0
        smallest = 0
        mean_sz = 0.0

    return {
        "num_microaneurysms": len(areas),
        "total_area_pixels": total_area,
        "coverage_percentage": (total_area / total_px) * 100.0,
        "largest_component": largest,
        "smallest_component": smallest,
        "mean_component_size": mean_sz,
        "component_areas": areas,
    }
