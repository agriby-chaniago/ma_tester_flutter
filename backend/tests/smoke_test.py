import argparse
from pathlib import Path

import requests


def check(r, name):
    if r.status_code >= 400:
        raise RuntimeError(f"{name} failed: HTTP {r.status_code} -> {r.text[:300]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    parser.add_argument("--image", default=None)
    parser.add_argument("--mode", default="auto", choices=["auto", "sim", "real"])
    parser.add_argument("--allow-fallback", default="true", choices=["true", "false"])
    args = parser.parse_args()

    base = args.base.rstrip("/")

    r = requests.get(f"{base}/healthz", timeout=10)
    check(r, "/healthz")
    print("/healthz OK", r.json().get("ready"))

    r = requests.get(f"{base}/model_info", timeout=10)
    check(r, "/model_info")
    print("/model_info OK", r.json().get("arch"))

    r = requests.get(f"{base}/metrics_basic", timeout=10)
    check(r, "/metrics_basic")
    print("/metrics_basic OK", r.json().get("count_requests"))

    if args.image:
        image_path = Path(args.image)
        if not image_path.exists():
            raise RuntimeError(f"Image file not found: {image_path}")

        with image_path.open("rb") as f:
            files = {"file": (image_path.name, f, "image/jpeg")}
            r = requests.post(
                f"{base}/predict",
                params={
                    "fmt": "json",
                    "threshold": 0.75,
                    "return_overlay": "true",
                    "mode": args.mode,
                    "allow_fallback": args.allow_fallback,
                },
                files=files,
                timeout=60,
            )
        check(r, "/predict fmt=json")
        payload = r.json()
        print(
            "/predict OK",
            payload.get("status"),
            payload.get("statistics", {}).get("num_microaneurysms"),
            "requested=",
            r.headers.get("x-model-mode-requested"),
            "used=",
            r.headers.get("x-model-mode-used"),
            "fallback=",
            r.headers.get("x-model-fallback"),
        )

    print("Smoke test passed")


if __name__ == "__main__":
    main()
