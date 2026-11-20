"""Measure the actual Compatibility captures, rather than predicted GPU state."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def measure(image: Image.Image, box: tuple[int, int, int, int], white: bool = True) -> dict:
    points = []
    peak = (0, 0, 0)
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            rgb = image.getpixel((x, y))
            selected = min(rgb) > 230 if white else rgb[0] > 60
            if selected:
                points.append((x, y))
                if sum(rgb) > sum(peak):
                    peak = rgb
    if not points:
        raise ValueError(f"No particle pixels in {box}")
    xs, ys = zip(*points)
    return {
        "width": max(xs) - min(xs) + 1,
        "height": max(ys) - min(ys) + 1,
        "cx": (min(xs) + max(xs)) / 2,
        "cy": (min(ys) + max(ys)) / 2,
        "pixels": len(points),
        "peak_rgb": peak,
    }


def analyze(directory: Path) -> dict:
    run = json.loads((directory / "run.json").read_text(encoding="utf-8"))
    if run["failures"] or run["configured_renderer"] != "gl_compatibility":
        raise ValueError("Engine-side checks failed, or renderer configuration differs")
    if run["display_driver"].lower() == "headless":
        raise ValueError("A headless run is not rendering evidence")
    log = (directory / "run.log").read_text(encoding="utf-8", errors="replace")
    if "PARTICLE_GRAPH_E0_FINISHED failures=[]" not in log:
        raise ValueError("Missing successful completion marker; stale captures are not evidence")
    if "Compatibility" not in log or "OpenGL API" not in log or "ERROR:" in log:
        raise ValueError("Rendering log is missing the actual backend or contains errors")

    samples = []
    for sample in run["samples"]:
        if sample["frame"] < 0:
            continue
        image = Image.open(directory / (sample["label"] + ".png")).convert("RGB")
        if image.size != (1280, 720):
            raise ValueError(f"Unexpected viewport: {image.size}")
        rows = {
            str(y): measure(image, (180, y - 10, 940, y + 11))
            for y in (140, 220, 300, 380, 540)
        }
        for y, length in ((140, 4), (220, 8), (300, 12)):
            observed = rows[str(y)]
            if abs(observed["width"] - length) > 1 or observed["height"] != 2:
                raise ValueError(f"Speed/length mismatch at row {y}: {observed}")
        if rows["220"] != rows["540"]:
            # The vertical center differs; all other sampled properties must match.
            original = {k: v for k, v in rows["220"].items() if k != "cy"}
            reloaded = {k: v for k, v in rows["540"].items() if k != "cy"}
            if original != reloaded:
                raise ValueError("Reloaded material differs from generated material")
        samples.append({
            **sample,
            "rows": rows,
            "fade": measure(image, (180, 450, 940, 471), white=False),
            "gravity": measure(image, (970, 110, 1270, 570)),
        })
    if len(samples) != 3:
        raise ValueError("Expected three independent frame captures")
    first, middle, last = samples
    if first["rows"]["380"]["width"] - last["rows"]["380"]["width"] < 3:
        raise ValueError("Damped particle did not shrink while aging")
    if abs(last["rows"]["300"]["width"] - first["rows"]["300"]["width"]) > 1:
        raise ValueError("Undamped control changed length")
    for y, speed in ((140, 100), (220, 250), (300, 400)):
        elapsed = last["elapsed_seconds"] - first["elapsed_seconds"]
        observed_speed = (last["rows"][str(y)]["cx"] - first["rows"][str(y)]["cx"]) / elapsed
        if abs(observed_speed - speed) > speed * 0.12:
            raise ValueError(f"Unexpected rendered displacement at row {y}: {observed_speed}")
    damped_motion = last["rows"]["380"]["cx"] - middle["rows"]["380"]["cx"]
    control_motion = last["rows"]["300"]["cx"] - middle["rows"]["300"]["cx"]
    if damped_motion >= control_motion * 0.25:
        raise ValueError("Damped movement was not slower than the control")
    if last["gravity"]["cy"] <= first["gravity"]["cy"] + 60:
        raise ValueError("Gravity did not change the rendered trajectory")
    if last["gravity"]["height"] <= last["gravity"]["width"]:
        raise ValueError("Particle long axis did not follow the downward motion")
    if first["fade"]["peak_rgb"][0] - last["fade"]["peak_rgb"][0] < 30:
        raise ValueError("Constant-white particle did not fade against black")
    for sample in samples:
        rgb = sample["fade"]["peak_rgb"]
        if max(rgb) - min(rgb) > 1:
            raise ValueError("The alpha-isolation case changed RGB chroma")
    event_image = Image.open(directory / "removal_event.png").convert("RGB")
    burst = measure(event_image, (800, 420, 1200, 700), white=False)
    if run["removal_signal_count"] != 1 or burst["pixels"] < 20:
        raise ValueError("Removal signal did not produce visible sparks")
    if not burst["peak_rgb"][0] > burst["peak_rgb"][1] > burst["peak_rgb"][2]:
        raise ValueError("Removal burst did not show the warm color gradient")
    files = [*directory.glob("frame_*.png"), directory / "removal_event.png",
             directory / "native_material.tres", directory / "run.json", directory / "run.log"]
    return {
        "status": "passed",
        "length_tolerance_pixels": 1,
        "width_pixels": 2,
        "samples": samples,
        "removal_burst": burst,
        "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)},
        "fixture_sha256": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(Path(__file__).parent.iterdir())
            if p.suffix in {".gd", ".tscn", ".py"}
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    report = analyze(args.directory)
    (args.directory / "pixel_analysis.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("E0_PIXEL_ANALYSIS_PASSED")
    for sample in report["samples"]:
        sizes = {y: (row["width"], row["height"]) for y, row in sample["rows"].items()}
        print(sample["label"], sizes)


if __name__ == "__main__":
    main()
