-- ============================================================
-- PILOTAGE CABINET — Configuration Supabase
-- À exécuter UNE FOIS dans : Supabase > SQL Editor > New query
-- ============================================================

-- 1) PROFILS UTILISATEURS -----------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  full_name text not null,
  role text not null default 'collab' check (role in ('admin','collab')),
  created_at timestamptz default now()
);

-- Le PREMIER compte créé devient automatiquement administrateur,
-- tous les suivants sont collaborateurs (l'admin peut promouvoir ensuite).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.profiles;
  insert into public.profiles (id, username, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    case when n = 0 then 'admin' else 'collab' end
  );
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Fonction utilitaire (évite la récursion RLS)
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public as
$$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') $$;

-- 2) DOSSIERS CLIENTS (portefeuille) ------------------------
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  type text default 'MENSUEL',                 -- MENSUEL / ANNUEL
  responsible_id uuid references public.profiles(id) on delete set null,
  responsible_name text default '',            -- nom importé si pas encore de compte
  created_at timestamptz default now()
);

-- 3) TÂCHES ---------------------------------------------------
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  num serial,
  title text not null,
  description text default '',
  client_id uuid references public.clients(id) on delete set null,
  category text default 'Client',
  assignee_id uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  start_date date,
  due_date date,
  est_duration text default '',
  priority text default 'p3',
  status text default 'todo',
  progress int default 0,
  last_action text default '',
  next_action text default '',
  comments text default '',
  block_cause text default '',
  block_action text default '',
  block_person text default '',
  completed_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.task_history (
  id bigserial primary key,
  task_id uuid,
  task_title text,
  user_name text,
  change text,
  ts timestamptz default now()
);

-- 4) SUIVI DES BASES -----------------------------------------
-- Codes journaux (section 'tenue') et déclarations (section 'declaration')
create table public.journals (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  section text not null default 'tenue' check (section in ('tenue','declaration')),
  code text not null,
  label text default '',
  position int default 0
);

-- Croix mensuelles (une écriture passée dans le mois)
create table public.journal_months (
  journal_id uuid references public.journals(id) on delete cascade,
  year int not null,
  month int not null check (month between 1 and 12),
  checked boolean default true,
  primary key (journal_id, year, month)
);

-- Nombre de pièces relevé chaque lundi, par code journal
create table public.piece_counts (
  journal_id uuid references public.journals(id) on delete cascade,
  week_date date not null,                     -- le lundi de la semaine
  count int default 0,
  entered_by uuid references public.profiles(id) on delete set null,
  primary key (journal_id, week_date)
);

-- 5) SÉCURITÉ (RLS) ------------------------------------------
alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.tasks enable row level security;
alter table public.task_history enable row level security;
alter table public.journals enable row level security;
alter table public.journal_months enable row level security;
alter table public.piece_counts enable row level security;

-- Tout le cabinet (utilisateurs connectés) peut LIRE l'ensemble :
-- indispensable pour la réunion du lundi.
create policy "read profiles" on public.profiles for select to authenticated using (true);
create policy "read clients" on public.clients for select to authenticated using (true);
create policy "read tasks" on public.tasks for select to authenticated using (true);
create policy "read history" on public.task_history for select to authenticated using (true);
create policy "read journals" on public.journals for select to authenticated using (true);
create policy "read months" on public.journal_months for select to authenticated using (true);
create policy "read counts" on public.piece_counts for select to authenticated using (true);

-- Écriture : tout collaborateur connecté (cabinet de confiance).
create policy "write clients" on public.clients for all to authenticated using (true) with check (true);
create policy "write tasks" on public.tasks for all to authenticated using (true) with check (true);
create policy "insert history" on public.task_history for insert to authenticated with check (true);
create policy "write journals" on public.journals for all to authenticated using (true) with check (true);
create policy "write months" on public.journal_months for all to authenticated using (true) with check (true);
create policy "write counts" on public.piece_counts for all to authenticated using (true) with check (true);

-- Profils : chacun modifie le sien, l'admin peut modifier tout le monde
-- (promotion en admin, correction de nom...).
create policy "update own profile" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- 6) TEMPS RÉEL (synchronisation multi-appareils) -------------
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.piece_counts;
alter publication supabase_realtime add table public.journal_months;
alter publication supabase_realtime add table public.journals;
alter publication supabase_realtime add table public.clients;

-- ============================================================
-- APRÈS CE SCRIPT :
-- 1. Authentication > Sign In / Providers > Email :
--    désactiver "Confirm email" (les comptes sont créés par l'admin).
-- 2. Récupérer Project URL + anon public key (Settings > API).
-- 3. Les renseigner au premier lancement de l'application.
-- 4. Créer le compte administrateur depuis l'écran de connexion
--    (le premier compte est automatiquement admin).
-- ============================================================
