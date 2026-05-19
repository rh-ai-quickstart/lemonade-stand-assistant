"""
Lemonade Stand Chat - NeMo Guardrails Edition
FastAPI production server with SSE streaming backed by NeMo Guardrails.

Guardrail detection works by inspecting the first character of each NeMo response:
each refusal bot message starts with a unique emoji, which maps to a detector type
for frontend styling and Prometheus metric tracking.
"""

import asyncio
import json
import logging
import os
import re
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import aiohttp
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel

# =============================================================================
# Logging
# =============================================================================

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# =============================================================================
# Configuration
# =============================================================================

NEMO_HOST = os.getenv("NEMO_GUARDRAILS_HOST", "localhost")
NEMO_PORT = os.getenv("NEMO_GUARDRAILS_PORT", "8000")
NEMO_SCHEME = os.getenv("NEMO_GUARDRAILS_SCHEME", "http")
# Model name passed to NeMo — must match the model configured in the NemoGuardrails CR.
# The NeMo config (guardrail rules) is selected automatically via default: true in the CRD.
NEMO_MODEL = os.getenv("NEMO_MODEL", "granite-3-2-8b-instruct")

NEMO_API_URL = f"{NEMO_SCHEME}://{NEMO_HOST}:{NEMO_PORT}/v1/chat/completions"

# =============================================================================
# Local Regex Pre-filter (English fruit patterns)
# Matches the check_forbidden_words action in the NeMo config.
# Blocks obvious violations locally to avoid an unnecessary NeMo round-trip.
# =============================================================================

_LOCAL_FRUIT_PATTERN = re.compile(
    r"\b(?i:oranges?|apples?|cranberr(?:y|ies)|pineapples?|grapes?|strawberr(?:y|ies)|"
    r"blueberr(?:y|ies)|watermelons?|durians?|cloudberr(?:y|ies)|bananas?|mango(?:es)?|"
    r"peach(?:es)?|pears?|plums?|cherr(?:y|ies)|kiwifruits?|kiwis?|papayas?|avocados?|"
    r"coconuts?|raspberr(?:y|ies)|blackberr(?:y|ies)|pomegranates?|figs?|apricots?|"
    r"nectarines?|tangerines?|clementines?|grapefruits?|limes?|passionfruits?|"
    r"dragonfruits?|lychees?|guavas?|persimmons?)\b"
)

# =============================================================================
# Refusal Signature Detection
#
# NeMo Guardrails returns the bot's refusal message as normal response content
# when a rail blocks — there is no separate metadata field indicating which
# guardrail fired. Each bot message in rails.co starts with a unique emoji,
# so we detect the guardrail by checking the first content chunk.
#
# Maps: emoji_prefix → (detector_name, direction, frontend_css_class)
# frontend_css_class is appended to "error-" in the UI: "error-hap", etc.
# None means the generic "error" style (no suffix).
# =============================================================================

REFUSAL_SIGNATURES: dict[str, tuple[str, str, str | None]] = {
    "📏": ("message_length", "input", None),
    "🌐": ("language", "input", "language"),
    "🍊": ("regex_fruit", "input", "regex"),
    "🔒": ("pii", "input", None),
    "🛡": ("prompt_injection", "input", "prompt-injection"),  # 🛡️ starts with 🛡 (U+1F6E1)
    "🚫": ("hap", "input", "hap"),
    "😔": ("hap", "output", "hap"),
    "🍋": ("topic_relevance", "input", "regex"),
}


def _detect_refusal(content: str) -> tuple[str | None, str | None, str | None]:
    """Return (detector_name, direction, css_class) if content is a refusal, else (None, None, None)."""
    stripped = content.lstrip()
    for emoji, info in REFUSAL_SIGNATURES.items():
        if stripped.startswith(emoji):
            return info
    return None, None, None


# =============================================================================
# Prometheus Metrics (app-layer, async-safe)
# =============================================================================

class AsyncMetricsCollector:
    DETECTOR_NAMES = [
        "message_length", "language", "regex_fruit",
        "pii", "prompt_injection", "hap", "topic_relevance",
    ]

    def __init__(self):
        self._lock = asyncio.Lock()
        self._sources: dict = {}

    def _ensure_source(self, source: str):
        if source not in self._sources:
            self._sources[source] = {
                "total_requests": 0,
                "local_regex_blocks": 0,
                "detections": {d: {"input": 0, "output": 0} for d in self.DETECTOR_NAMES},
            }

    async def increment_request(self, source: str = "audience"):
        async with self._lock:
            self._ensure_source(source)
            self._sources[source]["total_requests"] += 1

    async def increment_local_regex_block(self, source: str = "audience"):
        async with self._lock:
            self._ensure_source(source)
            self._sources[source]["local_regex_blocks"] += 1
            self._sources[source]["detections"]["regex_fruit"]["input"] += 1

    async def record_detection(self, detector: str, direction: str, source: str = "audience"):
        async with self._lock:
            self._ensure_source(source)
            if detector in self._sources[source]["detections"]:
                self._sources[source]["detections"][detector][direction] += 1

    async def get_prometheus_metrics(self) -> str:
        async with self._lock:
            lines = [
                "# HELP guardrail_requests_total Total requests processed",
                "# TYPE guardrail_requests_total counter",
            ]
            for source, data in self._sources.items():
                lines.append(f'guardrail_requests_total{{source="{source}"}} {data["total_requests"]}')

            lines += [
                "",
                "# HELP guardrail_local_regex_blocks_total Requests blocked locally before reaching NeMo",
                "# TYPE guardrail_local_regex_blocks_total counter",
            ]
            for source, data in self._sources.items():
                lines.append(f'guardrail_local_regex_blocks_total{{source="{source}"}} {data["local_regex_blocks"]}')

            lines += [
                "",
                "# HELP guardrail_detections_total Guardrail detections by detector, direction, and source",
                "# TYPE guardrail_detections_total counter",
            ]
            for source, data in self._sources.items():
                for detector, directions in data["detections"].items():
                    for direction, count in directions.items():
                        lines.append(
                            f'guardrail_detections_total{{detector="{detector}",direction="{direction}",source="{source}"}} {count}'
                        )

            lines += [
                "",
                "# HELP guardrail_detections_by_detector Total detections per detector (input + output)",
                "# TYPE guardrail_detections_by_detector counter",
            ]
            for source, data in self._sources.items():
                for detector, directions in data["detections"].items():
                    total = directions["input"] + directions["output"]
                    lines.append(f'guardrail_detections_by_detector{{detector="{detector}",source="{source}"}} {total}')

            lines += [
                "",
                "# HELP guardrail_detections_by_direction Total detections by direction",
                "# TYPE guardrail_detections_by_direction counter",
            ]
            for source, data in self._sources.items():
                input_total = sum(d["input"] for d in data["detections"].values())
                output_total = sum(d["output"] for d in data["detections"].values())
                lines.append(f'guardrail_detections_by_direction{{direction="input",source="{source}"}} {input_total}')
                lines.append(f'guardrail_detections_by_direction{{direction="output",source="{source}"}} {output_total}')

            return "\n".join(lines)


metrics = AsyncMetricsCollector()
aiohttp_session: aiohttp.ClientSession | None = None

# =============================================================================
# Application Lifespan
# =============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    global aiohttp_session
    connector = aiohttp.TCPConnector(
        limit=200,
        limit_per_host=100,
        keepalive_timeout=30,
        enable_cleanup_closed=True,
    )
    aiohttp_session = aiohttp.ClientSession(
        connector=connector,
        timeout=aiohttp.ClientTimeout(total=120, sock_connect=5, sock_read=60),
    )
    logger.info("NeMo Guardrails API: %s", NEMO_API_URL)
    logger.info("NeMo model: %s", NEMO_MODEL)
    yield
    await aiohttp_session.close()
    logger.info("aiohttp session closed")


# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title="Lemonade Stand Chat (NeMo Guardrails)",
    description="Chat API backed by NeMo Guardrails with SSE streaming and Prometheus metrics",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str


# =============================================================================
# Core Chat Logic
# =============================================================================

async def process_chat(message: str, source: str = "audience") -> AsyncGenerator[dict, None]:
    """Process a chat message through NeMo Guardrails and yield SSE events."""

    await metrics.increment_request(source)

    # Local regex pre-filter — catch obvious English fruit mentions before the NeMo round-trip.
    # NeMo's check_forbidden_words action does the same check; this just saves latency.
    if _LOCAL_FRUIT_PATTERN.search(message):
        logger.info("LOCAL REGEX blocked: %.80r", message)
        await metrics.increment_local_regex_block(source)
        yield {
            "type": "error",
            "message": "🍊 I noticed you mentioned other fruits or off-topic subjects. I'm specialized exclusively in lemons! Please ask me about lemons only.",
            "detector_type": "regex",
        }
        return

    payload = {
        "model": NEMO_MODEL,
        "messages": [{"role": "user", "content": message}],
        "stream": True,
    }

    max_retries = 2
    base_delay = 0.1

    for attempt in range(max_retries + 1):
        try:
            logger.debug("POST to NeMo (attempt %d/%d)", attempt + 1, max_retries + 1)
            async with aiohttp_session.post(NEMO_API_URL, json=payload) as response:
                if response.status != 200:
                    error_text = await response.text()
                    logger.error("NeMo returned %d: %.200s", response.status, error_text)
                    yield {"type": "error", "message": f"Service error: {response.status}"}
                    return

                # Read the SSE stream line by line.
                # Strategy: peek at the first content chunk to detect a refusal emoji.
                #   - Refusal detected → buffer all remaining chunks, yield a single error event.
                #   - Normal response → stream chunks directly for real-time output.
                first_content_seen = False
                is_refusal = False
                refusal_buffer = ""
                detector_name = direction = css_class = None
                stream_started = False

                while True:
                    try:
                        raw = await response.content.readline()
                    except Exception:
                        break
                    if not raw:
                        break

                    line = raw.decode("utf-8", errors="ignore").strip()
                    if not line:
                        continue  # blank line between SSE events
                    if line == "data: [DONE]":
                        break
                    if not line.startswith("data: "):
                        continue

                    try:
                        chunk_data = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue

                    choices = chunk_data.get("choices", [])
                    if not choices:
                        continue

                    choice = choices[0]
                    finish_reason = choice.get("finish_reason")
                    content = choice.get("delta", {}).get("content", "")

                    if not content:
                        if finish_reason == "length" and stream_started:
                            truncation = (
                                "\n\n---\n🍋🍋🍋 Maximum Response Length Reached 🍋🍋🍋"
                                "\n\n_Try asking a question with a shorter answer!_"
                            )
                            yield {"type": "chunk", "content": truncation}
                        continue

                    # First content chunk — check for a refusal emoji prefix.
                    if not first_content_seen:
                        first_content_seen = True
                        detector_name, direction, css_class = _detect_refusal(content)
                        is_refusal = detector_name is not None
                        if is_refusal:
                            logger.debug("Refusal detected: detector=%s direction=%s", detector_name, direction)

                    if is_refusal:
                        refusal_buffer += content
                    else:
                        stream_started = True
                        yield {"type": "chunk", "content": content}

                # End of SSE stream.
                if is_refusal:
                    full_msg = refusal_buffer.strip()
                    logger.info("NeMo BLOCKED [%s/%s]: %.80r", detector_name, direction, full_msg)
                    await metrics.record_detection(detector_name, direction, source)
                    yield {
                        "type": "error",
                        "message": full_msg,
                        "detector_type": css_class,
                    }
                elif stream_started:
                    yield {"type": "done"}
                else:
                    # Empty response — stale connection, retry.
                    if attempt < max_retries:
                        delay = 0 if attempt == 0 else base_delay * (2 ** (attempt - 1))
                        if delay:
                            await asyncio.sleep(delay)
                        continue
                    yield {"type": "error", "message": "No response received. Please try again."}

                return

        except aiohttp.ClientError as e:
            if attempt < max_retries:
                await asyncio.sleep(base_delay * (2 ** attempt))
                continue
            yield {"type": "error", "message": f"Connection error: {e}"}
            return
        except asyncio.TimeoutError:
            if attempt < max_retries:
                await asyncio.sleep(base_delay * (2 ** attempt))
                continue
            yield {"type": "error", "message": "Request timed out"}
            return
        except Exception as e:
            logger.exception("Unexpected error")
            yield {"type": "error", "message": f"Error: {e}"}
            return


# =============================================================================
# Endpoints
# =============================================================================

@app.post("/api/chat")
async def chat(request: ChatRequest, raw_request: Request):
    """SSE streaming chat endpoint."""
    source = raw_request.headers.get("x-source", "audience")

    async def generate():
        async for event in process_chat(request.message, source=source):
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint — app-layer counters derived from NeMo refusal detection."""
    return PlainTextResponse(
        content=await metrics.get_prometheus_metrics(),
        media_type="text/plain",
    )


@app.get("/", response_class=HTMLResponse)
async def root():
    static_path = os.path.join(os.path.dirname(__file__), "static", "index.html")
    if os.path.exists(static_path):
        with open(static_path, "r") as f:
            return HTMLResponse(content=f.read())
    return HTMLResponse(content="<html><body><h1>Lemonade Stand</h1></body></html>")


# =============================================================================
# Entry Point
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)