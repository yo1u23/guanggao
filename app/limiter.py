import asyncio
from contextlib import asynccontextmanager

from .config import OCR_MAX_CONCURRENCY

_current_limit = OCR_MAX_CONCURRENCY
_ocr_semaphore = asyncio.Semaphore(_current_limit)

@asynccontextmanager
async def ocr_limited():
    await _ocr_semaphore.acquire()
    try:
        yield
    finally:
        _ocr_semaphore.release()


def get_ocr_limit() -> int:
    return _current_limit


def set_ocr_limit(new_limit: int) -> int:
    global _current_limit, _ocr_semaphore
    if new_limit < 1:
        new_limit = 1
    # Create a new semaphore; existing waiters will complete on old one
    _current_limit = int(new_limit)
    _ocr_semaphore = asyncio.Semaphore(_current_limit)
    return _current_limit