from __future__ import annotations

import argparse
import json
import math
import shutil
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import distance_transform_edt
from skimage.measure import label, regionprops
from skimage.metrics import structural_similarity


EXPECTED_SIZE = (1920, 1080)


class ParityCompareError(ValueError):
    pass


def _read_rgb(path: Path) -> tuple[Image.Image, np.ndarray]:
    try:
        image = Image.open(path).convert("RGB")
        image.load()
    except (OSError, ValueError) as error:
        raise ParityCompareError(f"cannot read image {path}: {error}") from error
    return image, np.asarray(image, dtype=np.uint8)


def _edge_mask(image: Image.Image) -> np.ndarray:
    edges = image.convert("L").filter(ImageFilter.FIND_EDGES)
    return np.asarray(edges, dtype=np.uint8) >= 24


def _edge_distance(first: np.ndarray, second: np.ndarray) -> dict[str, float]:
    if not first.any() and not second.any():
        return {"meanPixels": 0.0, "maxPixels": 0.0}
    if not first.any() or not second.any():
        maximum = float(math.hypot(*EXPECTED_SIZE))
        return {"meanPixels": maximum, "maxPixels": maximum}
    to_second = distance_transform_edt(~second)[first]
    to_first = distance_transform_edt(~first)[second]
    merged = np.concatenate((to_second, to_first))
    return {"meanPixels": float(merged.mean()), "maxPixels": float(merged.max())}


def _regions(mask: np.ndarray, limit: int = 100) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for region in sorted(regionprops(label(mask, connectivity=2)), key=lambda item: item.area, reverse=True)[:limit]:
        min_row, min_col, max_row, max_col = region.bbox
        items.append(
            {
                "area": int(region.area),
                "boundingBox": [int(min_col), int(min_row), int(max_col), int(max_row)],
                "centroid": [float(region.centroid[1]), float(region.centroid[0])],
            }
        )
    return items


def compare_images(
    *, state_id: str, original_path: Path | str, godot_path: Path | str, output_dir: Path | str
) -> dict[str, Any]:
    original_path = Path(original_path)
    godot_path = Path(godot_path)
    output_dir = Path(output_dir)
    original_image, original = _read_rgb(original_path)
    godot_image, godot = _read_rgb(godot_path)
    if original_image.size != EXPECTED_SIZE or godot_image.size != EXPECTED_SIZE:
        raise ParityCompareError(
            f"native size required: original={original_image.size}, godot={godot_image.size}, expected={EXPECTED_SIZE}"
        )

    delta = np.abs(original.astype(np.int16) - godot.astype(np.int16)).astype(np.uint8)
    mask = np.any(delta != 0, axis=2)
    different_count = int(mask.sum())
    pixel_count = int(mask.size)
    difference_bbox = None
    if different_count:
        ys, xs = np.nonzero(mask)
        difference_bbox = [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]
    region_items = _regions(mask)
    original_edges = _edge_mask(original_image)
    godot_edges = _edge_mask(godot_image)
    edge_delta = np.logical_xor(original_edges, godot_edges)
    edge_distance = _edge_distance(original_edges, godot_edges)
    rmse = float(np.sqrt(np.mean((original.astype(np.float64) - godot.astype(np.float64)) ** 2)))
    ssim = float(structural_similarity(original, godot, channel_axis=2, data_range=255))
    metrics: dict[str, Any] = {
        "stateId": state_id,
        "originalSize": list(original_image.size),
        "godotSize": list(godot_image.size),
        "differentPixelCount": different_count,
        "differentPixelRatio": different_count / pixel_count,
        "rmse": rmse,
        "ssim": ssim,
        "differenceBoundingBox": difference_bbox,
        "connectedRegionCount": len(regionprops(label(mask, connectivity=2))),
        "reportedRegionCount": len(region_items),
        "edgeDifferentPixelCount": int(edge_delta.sum()),
        "edgeOffset": edge_distance,
    }

    output_dir.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(original_path, output_dir / "original.png")
    shutil.copyfile(godot_path, output_dir / "godot.png")
    Image.blend(original_image, godot_image, 0.5).save(output_dir / "overlay_50.png")
    Image.fromarray(delta, mode="RGB").save(output_dir / "absolute_diff.png")
    Image.fromarray((edge_delta.astype(np.uint8) * 255), mode="L").save(output_dir / "edge_diff.png")
    marked = godot_image.copy()
    draw = ImageDraw.Draw(marked)
    for item in region_items[:25]:
        draw.rectangle(item["boundingBox"], outline=(255, 0, 0), width=2)
    marked.save(output_dir / "marked_diff.png")
    (output_dir / "regions.json").write_text(
        json.dumps({"stateId": state_id, "regions": region_items}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (output_dir / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8"
    )
    return metrics


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare original and Godot frames without alignment")
    parser.add_argument("--state-id", required=True)
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        metrics = compare_images(
            state_id=args.state_id,
            original_path=args.original,
            godot_path=args.godot,
            output_dir=args.output,
        )
    except ParityCompareError as error:
        parser.error(str(error))
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
