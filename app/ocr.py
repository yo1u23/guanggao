from pathlib import Path
from typing import Optional

import pytesseract
from PIL import Image


class OCRError(RuntimeError):
    pass


def assert_tesseract_available() -> None:
    try:
        _ = pytesseract.get_tesseract_version()
    except Exception as exc:
        raise OCRError(
            "Tesseract OCR 未安装或不可用。请先安装 tesseract-ocr 及中文语言包。"
        ) from exc


def extract_text_from_image(image_path: Path, languages: str) -> str:
    assert_tesseract_available()
    with Image.open(image_path) as img:
        img_converted = img.convert("RGB")
        text: str = pytesseract.image_to_string(img_converted, lang=languages)
        return text or ""