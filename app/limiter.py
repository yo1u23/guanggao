import asyncio
from contextlib import asynccontextmanager

from .config import OCR_MAX_CONCURRENCY

_ocr_semaphore = asyncio.Semaphore(OCR_MAX_CONCURRENCY)

@asynccontextmanager
async def ocr_limited():
    await _ocr_semaphore.acquire()
    try:
        yield
    finally:
        _ocr_semaphore.release()