-- ============================================================
-- MIGRATION — Nouvelles fonctionnalités
-- Tâches récurrentes · Réunions (PV + présence) · Commentaires
-- · Suivi "base à jour" · Notifications simples
-- À exécuter dans Supabase > SQL Editor > Run. Sans danger.
-- ============================================================

-- 1) TÂCHES RÉCURRENTES ---------------------------------------
-- On ajoute la récurrence directement sur la tâche "modèle".
alter table public.tasks add column if not exists recurrence text default 'none'
  check (recurrence in ('none','weekly','monthly','quarterly','yearly'));
-- Date de la prochaine génération (calculée à la complétion).
alter table public.tasks add column if not exists recur_next date;

-- 2) COMMENTAIRES DE TÂCHE ------------------------------------
create table if not exists public.task_comments (
  id bigserial primary key,
  task_id uuid references public.tasks(id) on delete cascade,
  author_id uuid references public.profiles(id) on delete set null,
  author_name text default '',
  body text not null,
  created_at timestamptz default now()
);

-- 3) SUIVI "BASE À JOUR" (sans fichier) -----------------------
-- Un enregistrement = "la base du dossier C est à jour pour la semaine S".
create table if not exists public.base_status (
  client_id uuid references public.clients(id) on delete cascade,
  week_date date not null,               -- lundi de la semaine
  done boolean default true,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz default now(),
  primary key (client_id, week_date)
);

-- 4) RÉUNIONS (PV + présence) ---------------------------------
create table if not exists public.meetings (
  id uuid primary key default gen_random_uuid(),
  number int,                            -- numéro de PV
  meeting_date date not null,
  start_time text default '',
  end_time text default '',
  attendees jsonb default '[]'::jsonb,   -- [{name, role, present}]
  body text default '',                  -- corps du PV (points abordés)
  snapshot jsonb,                        -- état figé de la semaine (stats)
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- 5) NOTIFICATIONS SIMPLES ------------------------------------
create table if not exists public.notifications (
  id bigserial primary key,
  user_id uuid references public.profiles(id) on delete cascade,
  kind text default 'info',
  message text not null,
  link text default '',
  read boolean default false,
  created_at timestamptz default now()
);

-- ===== SÉCURITÉ =====
alter table public.task_comments enable row level security;
alter table public.base_status  enable row level security;
alter table public.meetings     enable row level security;
alter table public.notifications enable row level security;

-- Lecture cabinet
create policy "read comments" on public.task_comments for select to authenticated using (true);
create policy "read base_status" on public.base_status for select to authenticated using (true);
create policy "read meetings" on public.meetings for select to authenticated using (true);
create policy "read own notifs" on public.notifications for select to authenticated
  using (user_id = auth.uid());

-- Écriture commentaires : tout collaborateur peut commenter, chacun supprime les siens.
create policy "insert comments" on public.task_comments for insert to authenticated with check (true);
create policy "delete own comments" on public.task_comments for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- Base à jour : admin, ou responsable du dossier.
create policy "write base_status" on public.base_status for all to authenticated
  using (public.is_admin() or public.client_responsible(client_id) = auth.uid())
  with check (public.is_admin() or public.client_responsible(client_id) = auth.uid());

-- Réunions : admin gère, tout le monde lit.
create policy "write meetings" on public.meetings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Notifications : chacun marque les siennes comme lues ; insertion large (l'app cible le bon user).
create policy "update own notifs" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "insert notifs" on public.notifications for insert to authenticated with check (true);
create policy "delete own notifs" on public.notifications for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Temps réel
alter publication supabase_realtime add table public.task_comments;
alter publication supabase_realtime add table public.base_status;
alter publication supabase_realtime add table public.meetings;
alter publication supabase_realtime add table public.notifications;
