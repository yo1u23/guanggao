import asyncio
import time
from typing import Dict, Optional, Tuple

import httpx

# Runtime settings (global). These can be adjusted by commands at runtime.
AI_MODE = "off"  # off | openrouter
OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
OPENROUTER_API_KEY = ""
OPENROUTER_MODEL = "gpt-4o-mini"
AI_CLASSIFY_THRESHOLD = 0.7  # 0..1

# Basic rate accounting (best-effort, in-memory)
_ai_calls_total = 0
_ai_calls_failed = 0
_ai_last_error: Optional[str] = None


def set_ai_mode(mode: str) -> str:
    global AI_MODE
    if mode not in {"off", "openrouter"}:
        raise ValueError("invalid ai mode")
    AI_MODE = mode
    return AI_MODE


def set_ai_model(model: str) -> str:
    global OPENROUTER_MODEL
    OPENROUTER_MODEL = model.strip()
    return OPENROUTER_MODEL


def set_ai_threshold(val: float) -> float:
    global AI_CLASSIFY_THRESHOLD
    AI_CLASSIFY_THRESHOLD = max(0.0, min(1.0, float(val)))
    return AI_CLASSIFY_THRESHOLD


def load_ai_credentials(api_base: Optional[str], api_key: Optional[str]) -> None:
    global OPENROUTER_API_BASE, OPENROUTER_API_KEY
    if api_base:
        OPENROUTER_API_BASE = api_base.strip()
    if api_key:
        OPENROUTER_API_KEY = api_key.strip()


def get_ai_stats() -> Dict[str, object]:
    return {
        "mode": AI_MODE,
        "model": OPENROUTER_MODEL,
        "calls_total": _ai_calls_total,
        "calls_failed": _ai_calls_failed,
        "last_error": _ai_last_error or "",
        "threshold": AI_CLASSIFY_THRESHOLD,
    }


def should_use_ai() -> bool:
    return AI_MODE == "openrouter" and bool(OPENROUTER_API_KEY)


async def classify_text_with_openrouter(text: str) -> Tuple[bool, float, str]:
    """
    Returns: (is_ad, score, label)
    label in {ad, not_ad, unsure}
    """
    global _ai_calls_total, _ai_calls_failed, _ai_last_error
    _ai_calls_total += 1

    prompt = (
        "你是一个广告内容判别助手。给定一段中文或英文文本，请判断是否为广告/推广/代充/引流等。"
        "只输出一个JSON：{\"label\": \"ad|not_ad|unsure\", \"score\": 0..1}。文本：\n" + text[:4000]
    )
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": OPENROUTER_MODEL,
        "messages": [
            {"role": "system", "content": "You are a JSON-only classifier."},
            {"role": "user", "content": prompt},
        ],
        "response_format": {"type": "json_object"},
        "max_tokens": 100,
        "temperature": 0.0,
    }
    url = f"{OPENROUTER_API_BASE.rstrip('/')}/chat/completions"

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "{}")
            import json
            obj = json.loads(content)
            label = str(obj.get("label", "unsure")).lower()
            try:
                score = float(obj.get("score", 0.0))
            except Exception:
                score = 0.0
            is_ad = (label == "ad") and (score >= AI_CLASSIFY_THRESHOLD)
            return is_ad, score, label
    except Exception as exc:
        _ai_calls_failed += 1
        _ai_last_error = str(exc)[:200]
        return False, 0.0, "error"