-- ============================================================
-- MIGRATION — Chat : accusés de lecture (non-lus par conversation)
-- À exécuter dans Supabase > SQL Editor > Run. Sans danger.
-- ============================================================

-- Dernière lecture de chaque canal par chaque utilisateur.
-- channel = 'general' ou 'dm:<idAutre>' (du point de vue du lecteur)
create table if not exists public.chat_reads (
  user_id uuid references public.profiles(id) on delete cascade,
  channel text not null,
  last_read timestamptz default now(),
  primary key (user_id, channel)
);

alter table public.chat_reads enable row level security;
create policy "own reads" on public.chat_reads for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

alter publication supabase_realtime add table public.chat_reads;
