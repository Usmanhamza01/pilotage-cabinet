-- ============================================================
-- MIGRATION — Fonction (poste) des utilisateurs
-- À exécuter dans Supabase > SQL Editor > Run. Sans danger.
-- ============================================================

-- Fonction/poste exact, affiché dans la feuille de présence et le PV.
alter table public.profiles add column if not exists job_title text default '';
