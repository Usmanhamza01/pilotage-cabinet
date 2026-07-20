-- ============================================================
-- CORRECTIF — Écriture du suivi des bases (croix / pièces)
-- À exécuter si les croix des mois "sautent" (ne s'enregistrent pas).
-- Rejoue proprement les fonctions et politiques. Sans danger.
-- ============================================================

-- 1) Fonctions (SECURITY DEFINER pour traverser la RLS sans blocage)
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') $$;

create or replace function public.client_responsible(cid uuid)
returns uuid language sql security definer stable set search_path=public as
$$ select responsible_id from public.clients where id = cid $$;

create or replace function public.journal_client_responsible(jid uuid)
returns uuid language sql security definer stable set search_path=public as
$$ select c.responsible_id from public.journals j
     join public.clients c on c.id = j.client_id where j.id = jid $$;

-- 2) On recrée les politiques d'écriture des croix et pièces
drop policy if exists "months write" on public.journal_months;
create policy "months write" on public.journal_months for all to authenticated
  using (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid())
  with check (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid());

drop policy if exists "counts write" on public.piece_counts;
create policy "counts write" on public.piece_counts for all to authenticated
  using (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid())
  with check (public.is_admin() or public.journal_client_responsible(journal_id) = auth.uid());

-- 3) Vérifiez votre rôle : cette requête doit renvoyer 'admin' pour votre compte.
--    (Remplacez par votre nom si besoin.)
-- select full_name, role from public.profiles order by role;
