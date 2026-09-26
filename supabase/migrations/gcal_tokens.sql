-- One Google Calendar refresh token per signed-in user, written and read only
-- by the gcal-token Edge Function (service role). Row-level security is on with
-- NO policies, so no client — not even the owning user's app — can read it.
create table if not exists public.gcal_tokens (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  refresh_token text        not null,
  updated_at    timestamptz not null default now()
);

alter table public.gcal_tokens enable row level security;
