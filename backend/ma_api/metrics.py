from collections import deque
from dataclasses import dataclass


@dataclass
class TimingSample:
    pre_ms: float
    infer_ms: float
    post_ms: float
    total_ms: float


class RollingStats:
    def __init__(self, maxlen: int = 256) -> None:
        self._samples: deque[TimingSample] = deque(maxlen=maxlen)

    def add(self, pre_ms: float, infer_ms: float, post_ms: float) -> None:
        total = pre_ms + infer_ms + post_ms
        self._samples.append(TimingSample(pre_ms, infer_ms, post_ms, total))

    def as_dict(self) -> dict:
        if not self._samples:
            return {
                "count_requests": 0,
                "avg_pre_ms": 0.0,
                "avg_infer_ms": 0.0,
                "avg_post_ms": 0.0,
                "avg_total_ms": 0.0,
                "p95_total_ms": 0.0,
            }

        items = list(self._samples)
        n = len(items)

        avg_pre = sum(i.pre_ms for i in items) / n
        avg_inf = sum(i.infer_ms for i in items) / n
        avg_post = sum(i.post_ms for i in items) / n
        avg_total = sum(i.total_ms for i in items) / n

        sorted_totals = sorted(i.total_ms for i in items)
        idx_95 = min(n - 1, max(0, round(0.95 * (n - 1))))
        p95 = sorted_totals[idx_95]

        return {
            "count_requests": n,
            "avg_pre_ms": round(avg_pre, 3),
            "avg_infer_ms": round(avg_inf, 3),
            "avg_post_ms": round(avg_post, 3),
            "avg_total_ms": round(avg_total, 3),
            "p95_total_ms": round(p95, 3),
        }
