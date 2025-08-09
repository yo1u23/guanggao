"""Video helpers: first-frame extraction and perceptual hashing.

extract_first_frame uses ffmpeg to grab a frame from a video file.
compute_image_phash computes a perceptual hash (pHash) for near-duplicate checks.
"""
import subprocess
from pathlib import Path
from typing import Optional

from PIL import Image
import imagehash


def extract_first_frame(video_path: Path, output_path: Path, time_pos: str = "00:00:00.5") -> bool:
    try:
        # -ss before -i for faster seek, -frames:v 1 to get one frame
        subprocess.run([
            "ffmpeg", "-y", "-ss", time_pos, "-i", str(video_path), "-frames:v", "1", str(output_path)
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return output_path.exists()
    except Exception:
        return False


def compute_image_phash(image_path: Path) -> Optional[str]:
    try:
        with Image.open(image_path) as img:
            img = img.convert("L").resize((256, 256))
            ph = imagehash.phash(img)
            return str(ph)
    except Exception:
        return None