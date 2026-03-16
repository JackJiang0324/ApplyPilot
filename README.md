# ApplyPilot — AI-Powered University Application Assistant

A minimal, production-ready backend that helps students discover and apply to university programs using RAG-based Q&A, profile-driven recommendations, and automated notifications.

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| API Framework | FastAPI | Async, fast, auto-docs |
| Database | Supabase (Postgres + pgvector) | Managed Postgres with built-in vector search and auth |
| Embeddings | OpenAI `text-embedding-3-small` | High quality, cheap, 1536-dim vectors |
| LLM | Claude (Anthropic) | Used for RAG answer generation |
| Web Scraping | httpx + BeautifulSoup4 | Lightweight, no browser needed for MVP |
| Auth | JWT via Supabase Auth | Stateless, easy to integrate |
| Scheduling | APScheduler | In-process job scheduling for notifications |
| Deployment | Docker + any cloud (Railway, Render, Fly.io) | Single container, no infra overhead |

---

## Project Structure

```
applypilot/
├── app/
│   ├── main.py                    # FastAPI app entry point — registers all routers
│   ├── config.py                  # Loads all env vars via pydantic-settings
│   │
│   ├── api/
│   │   ├── deps.py                # Shared dependencies: auth guard, db session
│   │   └── v1/
│   │       ├── router.py          # Aggregates all v1 routers into one
│   │       ├── users.py           # POST /users, GET /users/me, PUT /users/me
│   │       ├── programs.py        # GET /programs, GET /programs/{id}
│   │       ├── ingest.py          # POST /ingest — admin: scrape + embed a URL
│   │       ├── qa.py              # POST /qa — RAG question answering
│   │       └── recommendations.py # GET /recommendations — profile-matched programs
│   │
│   ├── core/
│   │   ├── security.py            # JWT encode/decode helpers
│   │   └── supabase.py            # Supabase client singleton
│   │
│   ├── models/
│   │   ├── user.py                # Pydantic schemas: UserCreate, UserResponse
│   │   ├── program.py             # Pydantic schemas: Program, ProgramChunk
│   │   └── notification.py        # Pydantic schemas: Notification
│   │
│   ├── services/
│   │   ├── user_service.py        # Profile CRUD — create, read, update user
│   │   ├── ingest_service.py      # Scrape URL → chunk text → embed → store
│   │   ├── rag_service.py         # Embed query → vector search → LLM answer
│   │   ├── recommend_service.py   # Embed profile → similarity search → ranked list
│   │   └── notification_service.py# Send email or push via Supabase / SendGrid
│   │
│   └── db/
│       ├── queries.py             # pgvector SQL helpers (cosine similarity search)
│       └── migrations/
│           └── 001_init.sql       # DDL: users, programs, documents, notifications
│
├── tests/
│   ├── test_ingest.py
│   ├── test_rag.py
│   └── test_recommendations.py
│
├── Dockerfile
├── docker-compose.yml             # Local dev: app + Supabase local
├── pyproject.toml
├── .env.example
└── README.md
```

---

## How Each Layer Connects

```
Incoming Request
      │
      ▼
  main.py              ← boots FastAPI, mounts router
      │
      ▼
  api/v1/*.py          ← receives HTTP request, validates input via models/
      │
  api/deps.py          ← injects auth (JWT check) and db session
      │
      ▼
  services/*.py        ← ALL business logic lives here
      │
  core/supabase.py     ← single DB client shared across services
      │
      ▼
  db/queries.py        ← SQL + pgvector queries
      │
      ▼
  Supabase Postgres    ← stores users, programs, document chunks, embeddings
```

No business logic in the API layer. No SQL in the service layer. Each layer has one job.

---

## Data Flow per Feature

### User Profile
```
POST /users
  → user_service: save profile to users table
  → embed profile text → store vector in users.embedding
```

### Ingest (Admin)
```
POST /ingest  { "url": "https://mit.edu/cs-program" }
  → ingest_service: scrape page with httpx + BeautifulSoup
  → split into ~500 token chunks
  → embed each chunk via OpenAI
  → upsert into documents table with program_id
```

### RAG Q&A
```
POST /qa  { "question": "Does MIT require GRE?" }
  → embed question
  → pgvector cosine search → top 5 matching chunks
  → build prompt: chunks + question
  → call Claude API → stream answer back
```

### Recommendations
```
GET /recommendations
  → load current user's profile embedding
  → pgvector cosine search against programs.embedding
  → return ranked list of best-fit programs
```

### Notifications
```
APScheduler job (daily)
  → for each user: run recommendation
  → if new matches found → notification_service sends email
```

---

## Database Schema (Supabase Postgres + pgvector)

```sql
users         — id, email, profile_json, embedding vector(1536), created_at
programs      — id, url, name, description, embedding vector(1536)
documents     — id, program_id, chunk_text, embedding vector(1536)
notifications — id, user_id, message, sent_at
```

Vector search uses pgvector's `<->` cosine distance operator — no external vector DB needed.

---

## Running Locally

```bash
cp .env.example .env        # fill in your keys
docker compose up           # starts app + local Supabase
```

API docs available at `http://localhost:8000/docs`

---

## Deployment

The entire backend is a single Docker container. Recommended platforms:

- **Railway** — push to deploy, free tier available
- **Render** — Dockerfile deploy, easy env var management
- **Fly.io** — global edge deployment, great for latency

Point `SUPABASE_URL` and `SUPABASE_KEY` to your Supabase cloud project. Done.

---

## Testing Strategy

### Unit Tests
Test each service in isolation by mocking the Supabase client and OpenAI calls.

```
tests/test_ingest.py          — mock httpx, assert chunks stored correctly
tests/test_rag.py             — mock embeddings + vector search, assert prompt built correctly
tests/test_recommendations.py — mock user embedding + similarity results
```

### Integration Tests
Spin up a local Supabase instance (via `docker compose`) and run real queries against it. No mocks — this catches SQL bugs and migration issues before production.

### Crawler Testing
- Use `pytest` + `respx` to mock HTTP responses for specific university URLs
- Maintain a small fixture set of real HTML pages to test parser robustness
- Add a smoke test that hits 2–3 real URLs in CI to catch site structure changes early

---

## Future: Message Queue for Performance

The current MVP runs ingest and notifications synchronously. Under load, this blocks API workers. The fix is a task queue.

### Proposed upgrade path

```
Current (MVP):
  POST /ingest → ingest_service.run() → response (slow, blocks)

With queue (v2):
  POST /ingest → enqueue task → return job_id immediately
  Worker process → picks up task → scrapes + embeds → stores result
  GET /ingest/{job_id} → poll status
```

### Recommended stack
- **Redis + ARQ** — lightweight, async-native, fits FastAPI's async model well
- **Alternative**: Celery + Redis if you need more mature task management

### What goes in the queue

| Task | Why async |
|---|---|
| `ingest_url` | Scraping + embedding takes 5–30s per URL |
| `send_notification` | Email delivery should never block an API response |
| `batch_recommend` | Nightly re-ranking for all users |

This upgrade requires adding one worker service to `docker-compose.yml` and changing service calls from `await service.run()` to `await queue.enqueue(task)`. The rest of the architecture stays identical.
