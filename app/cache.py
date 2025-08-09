from collections import OrderedDict
from typing import Optional

class LRUCache:
    def __init__(self, capacity: int = 512) -> None:
        self.capacity = capacity
        self.store: OrderedDict[str, str] = OrderedDict()

    def get(self, key: str) -> Optional[str]:
        if key in self.store:
            self.store.move_to_end(key)
            return self.store[key]
        return None

    def set(self, key: str, value: str) -> None:
        if key in self.store:
            self.store.move_to_end(key)
        self.store[key] = value
        if len(self.store) > self.capacity:
            self.store.popitem(last=False)


ocr_text_cache = LRUCache(capacity=1024)