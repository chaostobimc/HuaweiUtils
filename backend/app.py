"""
Private KI-Assistent Backend - Raspberry Pi 5 Optimized - VOLLSTÄNDIG
- FastAPI + dsk (deepseek4free)
- Features: chat, summarize, translate, weather (mock + AI), health
- Battery/Data optimized
- Erweiterbar
"""
import os
import asyncio
import logging
import time
import json
from typing import Optional, Dict, Any, List
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import ORJSONResponse
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()

# --- Config ---
DEEPSEEK_TOKEN = os.getenv("DEEPSEEK_USER_TOKEN") or os.getenv("DEEPSEEK_AUTH_TOKEN", "")
MAX_PROMPT_LEN = int(os.getenv("MAX_PROMPT_LEN", "500"))
MAX_RESPONSE_LEN = int(os.getenv("MAX_RESPONSE_LEN", "800"))
ENABLE_THINKING = os.getenv("ENABLE_THINKING", "false").lower() == "true"  # false spart Daten
ENABLE_SEARCH = os.getenv("ENABLE_SEARCH", "false").lower() == "true"
RATE_LIMIT_SECONDS = float(os.getenv("RATE_LIMIT_SECONDS", "1.2"))
CACHE_TTL = int(os.getenv("CACHE_TTL", "60"))  # 60s cache spart API calls
VERSION = "1.1.0"

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("ai-bridge")

executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="dsk-worker")
_last_request_time: Dict[str, float] = {}
_simple_cache: Dict[str, Dict] = {}
_api_instance = None

def get_deepseek_api():
    global _api_instance
    if not DEEPSEEK_TOKEN:
        raise HTTPException(status_code=500, detail="DEEPSEEK_USER_TOKEN not configured")
    if _api_instance is None:
        try:
            from dsk.api import DeepSeekAPI
            _api_instance = DeepSeekAPI(DEEPSEEK_TOKEN)
            logger.info("DeepSeekAPI initialized")
        except Exception as e:
            logger.exception("Failed to init DeepSeekAPI")
            raise HTTPException(status_code=500, detail=f"DeepSeek init failed: {e}")
    return _api_instance

# --- Models ---
class ChatRequest(BaseModel):
    prompt: str = Field(..., min_length=1, max_length=2000)
    history_id: Optional[str] = Field(None)
    thinking: Optional[bool] = Field(None)
    search: Optional[bool] = Field(False)
    target_lang: Optional[str] = Field(None, description="For translate feature")
    id: Optional[str] = Field(None)

class ChatResponse(BaseModel):
    response: str
    thinking: str = ""
    truncated: bool = False
    model: str = "deepseek-r1"
    took_ms: int = 0
    type: str = "chat"
    id: Optional[str] = None

class HealthResponse(BaseModel):
    status: str
    version: str = VERSION
    token_configured: bool
    cache_size: int = 0
    uptime_seconds: int = 0

class FeatureListResponse(BaseModel):
    features: List[Dict[str, str]]

# --- Rate limit ---
async def rate_limit(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    now = time.time()
    last = _last_request_time.get(client_ip, 0)
    if now - last < RATE_LIMIT_SECONDS:
        raise HTTPException(status_code=429, detail=f"Rate limited, wait {RATE_LIMIT_SECONDS}s")
    _last_request_time[client_ip] = now

# --- Core blocking call ---
def _blocking_chat_completion(prompt: str, thinking_enabled: bool, search_enabled: bool) -> Dict[str, Any]:
    from dsk.api import AuthenticationError, RateLimitError, NetworkError, CloudflareError, APIError

    api = get_deepseek_api()
    if len(prompt) > MAX_PROMPT_LEN:
        prompt = prompt[:MAX_PROMPT_LEN]

    chat_id = api.create_chat_session()
    thinking_parts = []
    text_parts = []

    try:
        chunks = api.chat_completion(
            chat_id,
            prompt,
            thinking_enabled=thinking_enabled,
            search_enabled=search_enabled
        )
        for chunk in chunks:
            c_type = chunk.get("type")
            content = chunk.get("content", "")
            if not content:
                continue
            if c_type == "thinking":
                thinking_parts.append(content)
            elif c_type == "text":
                text_parts.append(content)
                if sum(len(p) for p in text_parts) > MAX_RESPONSE_LEN + 300:
                    break

    except AuthenticationError as e:
        raise ValueError(f"AUTH_FAILED: {e}")
    except RateLimitError as e:
        raise ValueError(f"RATE_LIMIT: {e}")
    except CloudflareError as e:
        raise ValueError(f"CLOUDFLARE: {e} - Run python -m dsk.bypass")
    except (NetworkError, APIError) as e:
        raise ValueError(f"API_ERROR: {e}")
    
    full_text = "".join(text_parts).strip()
    full_thinking = "".join(thinking_parts).strip()

    truncated = False
    if len(full_text) > MAX_RESPONSE_LEN:
        # Cut at last space
        cut = full_text[:MAX_RESPONSE_LEN]
        if ' ' in cut:
            cut = cut.rsplit(' ', 1)[0]
        full_text = cut + "…"
        truncated = True

    return {
        "response": full_text or "Keine Antwort erhalten.",
        "thinking": full_thinking[:800] if thinking_enabled else "",
        "truncated": truncated
    }

# --- Lifespan ---
start_time = time.time()

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"🚀 AI Bridge v{VERSION} starting - Pi5 optimized")
    if not DEEPSEEK_TOKEN:
        logger.warning("⚠️ No DEEPSEEK_USER_TOKEN set!")
    yield
    executor.shutdown(wait=False)
    logger.info("👋 Shutdown")

# --- App ---
app = FastAPI(
    title="Private AI Bridge - Pi5",
    description="FastAPI Backend für Huawei Watch GT6 - Vollständig",
    version=VERSION,
    default_response_class=ORJSONResponse,
    lifespan=lifespan
)

app.add_middleware(GZipMiddleware, minimum_size=200)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)

# --- Endpoints ---
@app.get("/health", response_model=HealthResponse, tags=["System"])
async def health():
    return HealthResponse(
        status="ok",
        token_configured=bool(DEEPSEEK_TOKEN),
        cache_size=len(_simple_cache),
        uptime_seconds=int(time.time() - start_time)
    )

@app.get("/api/features", response_model=FeatureListResponse, tags=["System"])
async def list_features():
    """Liste aller verfügbaren Features - für Watch Quick Actions"""
    return FeatureListResponse(features=[
        {"id": "chat", "name": "Chat", "endpoint": "/api/chat", "description": "Normaler Chat"},
        {"id": "summarize", "name": "Zusammenfassen", "endpoint": "/api/summarize", "description": "Text zusammenfassen (max 3 Sätze)"},
        {"id": "translate", "name": "Übersetzen", "endpoint": "/api/translate", "description": "Übersetzt Text, param target_lang"},
        {"id": "weather", "name": "Wetter", "endpoint": "/api/weather", "description": "Wetter + AI Erklärung (mock)"},
        {"id": "explain", "name": "Erklären", "endpoint": "/api/explain", "description": "Erklärt einfach"},
    ])

async def cached_chat(prompt: str, thinking_enabled: bool, search_enabled: bool, cache_key: str):
    if CACHE_TTL > 0 and cache_key in _simple_cache:
        cached = _simple_cache[cache_key]
        if time.time() - cached["ts"] < CACHE_TTL:
            logger.info(f"Cache hit for key {cache_key[:50]}")
            return cached["data"]
    return None

def set_cache(cache_key: str, data: dict):
    if CACHE_TTL > 0:
        _simple_cache[cache_key] = {"data": data, "ts": time.time()}
        if len(_simple_cache) > 100:
            oldest = min(_simple_cache, key=lambda k: _simple_cache[k]["ts"])
            del _simple_cache[oldest]

@app.post("/api/chat", response_model=ChatResponse, dependencies=[Depends(rate_limit)], tags=["AI"])
async def chat_endpoint(req: ChatRequest, request: Request):
    start = time.time()
    prompt = req.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="Empty prompt")

    cache_key = f"chat:{prompt[:120]}:{req.thinking}:{req.search}"
    cached = await cached_chat(prompt, req.thinking or ENABLE_THINKING, req.search or ENABLE_SEARCH, cache_key)
    if cached:
        return ChatResponse(**cached, took_ms=1, id=req.id)

    thinking_enabled = req.thinking if req.thinking is not None else ENABLE_THINKING
    search_enabled = req.search if req.search else ENABLE_SEARCH

    loop = asyncio.get_event_loop()
    try:
        result = await loop.run_in_executor(executor, _blocking_chat_completion, prompt, thinking_enabled, search_enabled)
    except ValueError as ve:
        msg = str(ve)
        if "AUTH_FAILED" in msg:
            raise HTTPException(status_code=401, detail=msg)
        if "RATE_LIMIT" in msg:
            raise HTTPException(status_code=429, detail=msg)
        raise HTTPException(status_code=502, detail=msg)
    except Exception as e:
        logger.exception("Unexpected error")
        raise HTTPException(status_code=500, detail=f"Internal error: {e}")

    took_ms = int((time.time() - start) * 1000)
    response = ChatResponse(
        response=result["response"],
        thinking=result["thinking"],
        truncated=result["truncated"],
        took_ms=took_ms,
        type="chat",
        id=req.id
    )
    set_cache(cache_key, response.model_dump())
    logger.info(f"Chat OK {took_ms}ms len={len(prompt)}->{len(result['response'])}")
    return response

@app.post("/api/summarize", response_model=ChatResponse, dependencies=[Depends(rate_limit)], tags=["AI-Ext"])
async def summarize(req: ChatRequest, request: Request):
    """Zusammenfassen - erweiterbares Feature"""
    new_prompt = f"Fasse den folgenden Text sehr kurz zusammen, max 3 Sätze, auf Deutsch, prägnant für Smartwatch Display (max 600 Zeichen):\n\n{req.prompt}"
    req_copy = req.model_copy(update={"prompt": new_prompt})
    resp = await chat_endpoint(req_copy, request)
    resp.type = "summarize"
    return resp

@app.post("/api/translate", response_model=ChatResponse, dependencies=[Depends(rate_limit)], tags=["AI-Ext"])
async def translate(req: ChatRequest, request: Request):
    """Übersetzen - erweiterbares Feature"""
    target = req.target_lang or "en"
    lang_names = {"en": "Englisch", "de": "Deutsch", "fr": "Französisch", "es": "Spanisch", "it": "Italienisch"}
    lang_name = lang_names.get(target, target)
    new_prompt = f"Übersetze den folgenden Text nach {lang_name} ({target}). Nur Übersetzung, keine Erklärung, max 600 Zeichen:\n\n{req.prompt}"
    req_copy = req.model_copy(update={"prompt": new_prompt})
    resp = await chat_endpoint(req_copy, request)
    resp.type = "translate"
    return resp

@app.post("/api/explain", response_model=ChatResponse, dependencies=[Depends(rate_limit)], tags=["AI-Ext"])
async def explain(req: ChatRequest, request: Request):
    """Einfach erklären - für Watch GT6 kleines Display"""
    new_prompt = f"Erkläre das folgende Thema sehr einfach und kurz, als würdest du es einem Kind erklären, max 5 Sätze, für Smartwatch:\n\n{req.prompt}"
    req_copy = req.model_copy(update={"prompt": new_prompt})
    resp = await chat_endpoint(req_copy, request)
    resp.type = "explain"
    return resp

@app.post("/api/weather", response_model=ChatResponse, dependencies=[Depends(rate_limit)], tags=["AI-Ext"])
async def weather(req: ChatRequest, request: Request):
    """
    Wetter Feature - Mock + AI
    In Zukunft: echte Wetter API (OpenWeather) einbinden, dann via AI zusammenfassen
    """
    # Hier könnte man OpenWeatherMap API call machen
    # Für jetzt: AI generiert Wetter Erklärung basierend auf Prompt
    # Prompt z.B. "Wetter in Berlin"
    new_prompt = f"Du bist ein Wetterassistent. Der Nutzer fragt: '{req.prompt}'. Gib eine kurze, hilfreiche Wettervorhersage (fiktiv aber plausibel) für heute, max 4 Sätze, inkl. Temperatur und Tipp für Kleidung. Für Smartwatch Display optimiert."
    req_copy = req.model_copy(update={"prompt": new_prompt, "search": True})  # search true für aktuelles Wetter wenn möglich
    resp = await chat_endpoint(req_copy, request)
    resp.type = "weather"
    return resp

@app.post("/api/quick", response_model=ChatResponse, dependencies=[Depends(rate_limit)], tags=["AI-Ext"])
async def quick_actions(req: ChatRequest, request: Request):
    """Generischer Quick Action Endpoint - für zukünftige Buttons auf Uhr"""
    # Mapping von type via prompt prefix
    prompt_lower = req.prompt.lower()
    if "wetter" in prompt_lower or "weather" in prompt_lower:
        return await weather(req, request)
    if "zusammenfass" in prompt_lower or "summarize" in prompt_lower:
        return await summarize(req, request)
    if "übersetz" in prompt_lower or "translate" in prompt_lower:
        return await translate(req, request)
    if "erklär" in prompt_lower or "explain" in prompt_lower:
        return await explain(req, request)
    return await chat_endpoint(req, request)

# --- Main ---
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8000, log_level="info")
