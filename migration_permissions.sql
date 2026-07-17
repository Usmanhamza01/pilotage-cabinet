-- ============================================================
-- MIGRATION — Permissions collaborateurs
-- Lecture : tout le cabinet (inchangé, nécessaire pour la réunion)
-- Écriture : restreinte. À exécuter dans Supabase > SQL Editor > Run.
-- Sans danger pour les données existantes.
-- ============================================================

-- Fonctions utilitaires (SECURITY DEFINER pour éviter la récursion RLS)
create or replace function public.client_responsible(cid uuid)
returns uuid language sql security definer stable set search_path=public as
$$ select responsible_id from public.clients where id = cid $$;

create or replace function public.journal_client_responsible(jid uuid)
returns uuid language sql security definer stable set search_path=public as
$$ select c.responsible_id from public.journals j
     join public.clients c on c.id = j.client_id where j.id = jid $$;

-- On retire les anciennes règles d'écriture « tout le monde »
drop policy if exists "write clients" on public.clients;
drop policy if exists "write tasks"   on public.tasks;
drop policy if exists "write journals" on public.journals;
drop policy if exists "write months"  on public.journal_months;
drop policy if exists "write counts"  on public.piece_counts;

-- ===== DOSSIERS =====
-- Création : tout collaborateur (il devient responsable de ce qu'il crée).
create policy "clients insert" on public.clients for insert to authenticated
  with check (true);
-- Modification / suppression : admin, ou responsable du dossier.
create policy "clients update" on public.clients for update to authenticated
  using (public.is_admin() or responsible_id = auth.uid())
  with check (public.is_admin() or responsible_id = auth.uid());
create policy "clients delete" on public.clients for delete to authenticated
  using (public.is_admin() or responsible_id = auth.uid());

-- ===== TÂCHES =====
-- Création : tout collaborateur.
create policy "tasks insert" on public.tasks for insert to authenticated
  with check (true);
-- Modification / suppression : admin, OU tâche assignée à soi, OU dossier dont on est responsable.
create policy "tasks update" on public.tasks for update to authenticated
  using (public.is_admin() or assignee_id = auth.uid()
         or public.client_responsible(client_id) = auth.uid())
  with check (public.is_admin() or assignee_id = auth.uid()
         or public.client_responsible(client_id) = auth.uid());
create policy "tasks delete" on public.tasks for delete to authenticated
  using (public.is_admin() or assignee_id = auth.uid()
         or public.client_responsible(client_id) = auth.uid());

-- ===== SUIVI DES BASES =====
-- Journaux / croix / pièces : admin, ou responsable du dossier concerné.
create policy "journals write" on public.journals for all to authenticated
  using (public.is_admin() or public.client_responsible(client_id) = auth.uid())
  with check (public.is_admin() or public.client_responsible(client_id) = auth.uid());

create policy "months write" on public.journal_months for all to authenticated
  using (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid())
  with check (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid());

create policy "counts write" on public.piece_counts for all to authenticated
  using (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid())
  with check (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid());

-- Les règles de LECTURE (« read ... ») restent en place : tout le cabinet voit tout.
