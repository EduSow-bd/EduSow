create table if not exists public.learning_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in ('quiz_attempt','lesson_completed','flashcard_review','study_session')),
  subject text not null default 'General' check (char_length(btrim(subject)) between 1 and 80),
  topic text not null default 'Uncategorized' check (char_length(btrim(topic)) between 1 and 160),
  title text not null check (char_length(btrim(title)) between 1 and 200),
  score integer,
  max_score integer,
  duration_seconds integer check (duration_seconds is null or duration_seconds between 0 and 86400),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object' and octet_length(details::text) <= 16384),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check ((score is null and max_score is null) or (score >= 0 and max_score > 0 and score <= max_score))
);

create index if not exists learning_events_user_time_idx on public.learning_events (user_id, occurred_at desc);
create index if not exists learning_events_user_topic_idx on public.learning_events (user_id, subject, topic);

create table if not exists public.learning_mistakes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question_hash text not null check (char_length(question_hash) between 8 and 64),
  subject text not null default 'General' check (char_length(btrim(subject)) between 1 and 80),
  topic text not null default 'Uncategorized' check (char_length(btrim(topic)) between 1 and 160),
  question text not null check (char_length(btrim(question)) between 1 and 1200),
  selected_answer text not null default '' check (char_length(selected_answer) <= 600),
  correct_answer text not null check (char_length(btrim(correct_answer)) between 1 and 600),
  explanation text not null default '' check (char_length(explanation) <= 1600),
  occurrences integer not null default 1 check (occurrences >= 1),
  status text not null default 'needs_review' check (status in ('needs_review','practicing','mastered')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, question_hash)
);

create index if not exists learning_mistakes_user_status_idx on public.learning_mistakes (user_id, status, last_seen_at desc);

create table if not exists public.learning_topic_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (char_length(btrim(subject)) between 1 and 80),
  topic text not null check (char_length(btrim(topic)) between 1 and 160),
  subject_key text not null,
  topic_key text not null,
  attempts integer not null default 0 check (attempts >= 0),
  correct_answers integer not null default 0 check (correct_answers >= 0),
  mastery_score numeric(5,2) not null default 0 check (mastery_score between 0 and 100),
  last_activity_at timestamptz,
  next_review_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, subject_key, topic_key),
  check (correct_answers <= attempts)
);

create index if not exists learning_topic_progress_user_mastery_idx on public.learning_topic_progress (user_id, mastery_score asc, last_activity_at desc);

alter table public.learning_events enable row level security;
alter table public.learning_mistakes enable row level security;
alter table public.learning_topic_progress enable row level security;

drop policy if exists "Students can manage their own learning events" on public.learning_events;
create policy "Students can manage their own learning events" on public.learning_events for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Students can manage their own learning mistakes" on public.learning_mistakes;
create policy "Students can manage their own learning mistakes" on public.learning_mistakes for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Students can manage their own topic progress" on public.learning_topic_progress;
create policy "Students can manage their own topic progress" on public.learning_topic_progress for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.learning_events to authenticated;
grant select, insert, update, delete on public.learning_mistakes to authenticated;
grant select, insert, update, delete on public.learning_topic_progress to authenticated;