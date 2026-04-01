from __future__ import annotations

from typing import Any

import numpy as np

REAL_PIPELINE_NAME = "template"
REAL_PIPELINE_VERSION = "0.1.0"
REAL_PIPELINE_READY = False
REAL_PIPELINE_ERROR = "Template pipeline is not implemented yet"


def predict(rgb_u8: np.ndarray, threshold: float) -> tuple[np.ndarray, np.ndarray, dict[str, Any], dict[str, float]]:
    """Template real pipeline contract.

    Replace this with actual model inference and set REAL_PIPELINE_READY=True
    when the implementation is complete.
    """
    raise RuntimeError(
        "real_pipeline_template.predict is not implemented. "
        "Implement this function and set REAL_PIPELINE_READY=True."
    )
