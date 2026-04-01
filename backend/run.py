from ma_api.app import app


if __name__ == "__main__":
    import os
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port_raw = os.getenv("PORT", "8000")
    try:
        port = int(port_raw)
    except Exception:
        port = 8000

    uvicorn.run(app, host=host, port=port, log_level="info")
