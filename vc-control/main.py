"""
RustPVC vc-control メインエントリポイント
Phase0: /health エンドポイントのみ実装
"""
import time

from fastapi import FastAPI

# アプリケーション起動時刻（tick カウント用の基準）
_start_time = time.monotonic()

app = FastAPI(title="RustPVC vc-control", version="0.1.0")


@app.get("/health")
async def health() -> dict:
    """
    ヘルスチェックエンドポイント。
    Docker の HEALTHCHECK および疎通確認に使用する。
    """
    tick = int(time.monotonic() - _start_time)
    return {"status": "ok", "clients": 0, "tick": tick}
