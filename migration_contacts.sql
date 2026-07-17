-- ============================================================
-- MIGRATION — Ajout des informations de contact des dossiers
-- À exécuter dans : Supabase > SQL Editor > New query > Run
-- (sans danger : n'affecte pas les données existantes)
-- ============================================================

alter table public.clients add column if not exists interlocutor text default '';
alter table public.clients add column if not exists address      text default '';
alter table public.clients add column if not exists phone        text default '';
alter table public.clients add column if not exists email        text default '';
