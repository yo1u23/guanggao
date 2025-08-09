"""Text utilities: normalization and link detection.

normalize_text applies NFKC normalization, removes zero-width characters,
lowers case, and applies simple leet mappings to mitigate obfuscation.
contains_link uses a regex to detect URLs/t.me/tg:// patterns.
"""
import re
import unicodedata
from typing import Tuple

# Zero-width and special chars to strip
_ZERO_WIDTH_PATTERN = re.compile(r"[\u200B\u200C\u200D\u200E\u200F\uFEFF]")
# Simple leet mapping
_LEET_MAP = str.maketrans({
    "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
    "@": "a", "$": "s",
})

_URL_PATTERN = re.compile(r"https?://|www\.|t\.me/|tg://", re.IGNORECASE)


def normalize_text(text: str) -> str:
    if not text:
        return ""
    # NFKC normalization
    t = unicodedata.normalize("NFKC", text)
    # strip zero-width
    t = _ZERO_WIDTH_PATTERN.sub("", t)
    # lower
    t = t.lower()
    # leet normalize
    t = t.translate(_LEET_MAP)
    return t


def contains_link(text: str) -> bool:
    if not text:
        return False
    return bool(_URL_PATTERN.search(text))