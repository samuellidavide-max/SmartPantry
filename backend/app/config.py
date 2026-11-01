import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_url: str = os.getenv("DATABASE_URL", "postgresql://postgres@localhost:5432/smartpantry")
    jwt_secret: str = os.getenv("JWT_SECRET", "cambia-questo-segreto-in-produzione")
    dev_mode: bool = os.getenv("DEV_MODE", "1") == "1"            # abilita /v1/dev/* e Premium demo
    ocr_provider: str = os.getenv("OCR_PROVIDER", "demo")           # "demo" | "google_vision"
    google_vision_api_key: str | None = os.getenv("GOOGLE_VISION_API_KEY")
    price_max_age_days: int = int(os.getenv("PRICE_MAX_AGE_DAYS", "21"))
    free_max_radius_m: int = 5000
    premium_max_radius_m: int = 10000
    free_max_lists: int = 1
    receipts_per_day: int = 2
    credits_per_receipt: int = 10
    credits_streak_bonus: int = 5
    credits_for_premium_week: int = 100


settings = Settings()
