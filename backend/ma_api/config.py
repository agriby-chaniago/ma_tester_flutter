from dataclasses import dataclass
import os


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_str(name: str, default: str) -> str:
    raw = os.getenv(name)
    if raw is None:
        return default
    value = raw.strip().lower()
    return value or default


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw.strip())
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw.strip())
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    api_version: str = "2.0.0"
    model_version: str = "sim-1.0.0"
    checkpoint_sha256: str = "simulated-local"
    device: str = "cpu"
    # IDRID images are commonly around 12 MP, so defaults are set above that.
    max_file_mb: int = _env_int("MAX_FILE_MB", 20)
    max_megapixels: float = _env_float("MAX_MEGAPIXELS", 16.0)
    max_batch_files: int = 10
    min_component_area: int = 8
    default_inference_mode: str = _env_str("DEFAULT_INFERENCE_MODE", "auto")
    enable_real_mode: bool = _env_bool("ENABLE_REAL_MODE", False)
    allow_real_fallback: bool = _env_bool("ALLOW_REAL_FALLBACK", True)
    real_pipeline_module: str = _env_str("REAL_PIPELINE_MODULE", "")
    real_pipeline_callable: str = _env_str("REAL_PIPELINE_CALLABLE", "predict")


settings = Settings()
