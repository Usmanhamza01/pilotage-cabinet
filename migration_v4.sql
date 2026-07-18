-- ============================================================
-- MIGRATION — Chat d'équipe (salon commun + messages privés)
-- À exécuter dans Supabase > SQL Editor > Run. Sans danger.
-- ============================================================

create table if not exists public.chat_messages (
  id bigserial primary key,
  channel text not null default 'general',   -- 'general' ou 'dm:<uidA>_<uidB>' (uid triés)
  sender_id uuid references public.profiles(id) on delete set null,
  sender_name text default '',
  recipient_id uuid references public.profiles(id) on delete set null, -- null pour le salon commun
  body text not null,
  created_at timestamptz default now()
);

create index if not exists idx_chat_channel on public.chat_messages(channel, created_at);

alter table public.chat_messages enable row level security;

-- Lecture : le salon commun est visible par tout le cabinet ;
-- un message privé n'est visible que par l'expéditeur et le destinataire.
create policy "read chat" on public.chat_messages for select to authenticated
  using (recipient_id is null or sender_id = auth.uid() or recipient_id = auth.uid());

-- Envoi : on ne peut écrire qu'en son propre nom.
create policy "send chat" on public.chat_messages for insert to authenticated
  with check (sender_id = auth.uid());

-- Suppression : son propre message, ou admin.
create policy "delete chat" on public.chat_messages for delete to authenticated
  using (sender_id = auth.uid() or public.is_admin());

alter publication supabase_realtime add table public.chat_messages;
