-- Enable pgvector extension (must be done in Supabase Dashboard > Extensions first)
create extension if not exists vector;

-- ============================================================
-- users
-- ============================================================
create table if not exists users (
    id          uuid primary key default gen_random_uuid(),
    email       text not null unique,
    name        text,
    academic_level  text,           -- e.g. "bachelor", "master", "phd"
    target_country  text[],         -- e.g. ["US", "UK"]
    interests       text[],         -- e.g. ["machine learning", "finance"]
    created_at  timestamptz not null default now()
);

-- ============================================================
-- programs
-- ============================================================
create table if not exists programs (
    id           uuid primary key default gen_random_uuid(),
    school_name  text not null,
    program_name text not null,
    degree_level text,              -- e.g. "master", "phd"
    country      text,
    tuition      numeric,           -- annual tuition in USD
    deadline     date,
    source_url   text unique,
    raw_text     text,
    created_at   timestamptz not null default now()
);

-- ============================================================
-- program_chunks  (RAG unit)
-- ============================================================
create table if not exists program_chunks (
    id          uuid primary key default gen_random_uuid(),
    program_id  uuid not null references programs(id) on delete cascade,
    chunk_index int  not null,
    chunk_text  text not null,
    embedding   vector(1536),       -- OpenAI text-embedding-3-small dimension
    created_at  timestamptz not null default now(),
    unique (program_id, chunk_index)
);

-- Index for ANN vector search
create index if not exists program_chunks_embedding_idx
    on program_chunks
    using ivfflat (embedding vector_cosine_ops)
    with (lists = 100);

-- ============================================================
-- qa_logs
-- ============================================================
create table if not exists qa_logs (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid references users(id) on delete set null,
    question   text not null,
    answer     text,
    created_at timestamptz not null default now()
);

-- ============================================================
-- Row Level Security (enable but keep open for backend service role)
-- ============================================================
alter table users          enable row level security;
alter table programs       enable row level security;
alter table program_chunks enable row level security;
alter table qa_logs        enable row level security;

-- Service role bypasses RLS by default in Supabase — no extra policy needed.
-- If you later add anon/user JWT access, add policies here.
