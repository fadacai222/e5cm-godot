import json
import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools.parity_compare.compare import ParityCompareError, compare_images
from tools.parity_compare.manifest import load_and_validate_manifest
from tools.parity_compare.original_driver import canonical_state


ROOT = Path(__file__).resolve().parents[1]


class ParityManifestTests(unittest.TestCase):
    def test_shared_manifest_and_six_fixture_types_are_valid(self):
        manifest = load_and_validate_manifest(ROOT / "parity" / "state_manifest.json")
        self.assertGreaterEqual(len(manifest["states"]), 13)
        self.assertEqual(len({state["id"] for state in manifest["states"]}), len(manifest["states"]))
        for name in (
            "profile.json",
            "settings.json",
            "favorites.json",
            "records.json",
            "match_state.json",
            "song_fixture.json",
        ):
            data = json.loads((ROOT / "parity" / "fixtures" / name).read_text(encoding="utf-8"))
            self.assertIsNotNone(data, name)
        video_meta = json.loads(
            (ROOT / "parity" / "fixtures" / "video_coin_2_500.json").read_text(encoding="utf-8")
        )
        video_path = ROOT / video_meta["godotSourcePath"]
        frame_path = ROOT / "parity" / "fixtures" / video_meta["frameFile"]
        self.assertEqual(hashlib.sha256(video_path.read_bytes()).hexdigest(), video_meta["sourceSha256"])
        with Image.open(frame_path) as frame_image:
            self.assertEqual(frame_image.size, tuple(video_meta["frameSize"]))
        self.assertEqual(video_meta["timeSeconds"], 2.5)


class ParityCompareTests(unittest.TestCase):
    def test_compare_generates_strict_visual_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = np.zeros((1080, 1920, 3), dtype=np.uint8)
            godot = original.copy()
            godot[100:120, 200:240] = (255, 255, 255)
            Image.fromarray(original).save(root / "original.png")
            Image.fromarray(godot).save(root / "godot.png")
            metrics = compare_images(
                state_id="coin.idle",
                original_path=root / "original.png",
                godot_path=root / "godot.png",
                output_dir=root / "diff",
            )
            self.assertEqual(metrics["differentPixelCount"], 800)
            self.assertEqual(metrics["differenceBoundingBox"], [200, 100, 240, 120])
            for name in (
                "original.png",
                "godot.png",
                "overlay_50.png",
                "absolute_diff.png",
                "edge_diff.png",
                "marked_diff.png",
                "regions.json",
                "metrics.json",
            ):
                self.assertTrue((root / "diff" / name).is_file(), name)

    def test_compare_rejects_non_native_size_without_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            Image.new("RGB", (1886, 1061)).save(root / "original.png")
            Image.new("RGB", (1920, 1080)).save(root / "godot.png")
            with self.assertRaises(ParityCompareError):
                compare_images(
                    state_id="invalid.size",
                    original_path=root / "original.png",
                    godot_path=root / "godot.png",
                    output_dir=root / "diff",
                )
            self.assertFalse((root / "diff").exists())


class OriginalParityDriverTests(unittest.TestCase):
    def test_original_state_is_exported_to_shared_names(self):
        raw = {
            "credit": 3,
            "players": 2,
            "mode": {"major": "竞速", "sub": "club"},
            "scene": {"name": "投币"},
            "sceneState": {
                "phase": "玩家选择",
                "focusedPlayers": 2,
                "selectionAnimating": False,
            },
        }
        state = canonical_state(raw, "coin.player_select.2p")
        self.assertEqual(state["stateId"], "coin.player_select.2p")
        self.assertEqual(state["global"]["credit"], 3)
        self.assertEqual(state["global"]["players"], 2)
        self.assertEqual(state["scene"]["name"], "coin")
        self.assertEqual(state["scene"]["focusedPlayers"], 2)


if __name__ == "__main__":
    unittest.main()
