-- ============================================================
-- MIGRATION v6 — Module de Facturation
-- Factures, clients de facturation, encaissements, historique.
-- À exécuter dans Supabase > SQL Editor > Run. Sans danger.
-- ============================================================

-- 1) Profil "assistante" : on étend le rôle possible.
--    (l'app gère : admin voit tout, assistante accède au module facturation)
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('admin','collab','assistante'));

-- 2) CLIENTS DE FACTURATION (base dédiée, distincte des dossiers de suivi)
create table if not exists public.billing_clients (
  id uuid primary key default gen_random_uuid(),
  raison_sociale text not null,
  adresse text default '',
  telephone text default '',
  email text default '',
  ninea text default '',
  reference text default '',              -- référence client
  montant_ht numeric(14,2) default 0,     -- montant mensuel HT
  taux_tva numeric(5,2) default 18,       -- TVA sénégalaise par défaut 18%
  actif boolean default true,             -- client actif = facturé automatiquement
  observations text default '',
  created_at timestamptz default now()
);

-- 3) FACTURES
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  numero text unique not null,            -- numérotation automatique (ex : FAC-2026-0001)
  client_id uuid references public.billing_clients(id) on delete restrict,
  -- instantané des infos client au moment de la facture (immuable)
  client_nom text,
  client_adresse text,
  client_telephone text,
  client_ninea text,
  designation text default '',
  periode text default '',                -- période concernée (ex : "Juillet 2026")
  mois int,                               -- mois de facturation 1-12
  exercice int,                           -- exercice comptable
  date_facture date default current_date,
  date_echeance date,
  montant_ht numeric(14,2) default 0,
  taux_tva numeric(5,2) default 18,
  montant_tva numeric(14,2) default 0,
  montant_ttc numeric(14,2) default 0,
  statut text default 'brouillon'         -- brouillon, validee, annulee
    check (statut in ('brouillon','validee','annulee')),
  statut_paiement text default 'non_encaissee'
    check (statut_paiement in ('non_encaissee','partiel','encaissee')),
  total_paye numeric(14,2) default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  unique (client_id, mois, exercice)      -- anti-doublon : 1 facture / client / mois / exercice
);

-- 4) ENCAISSEMENTS (paiements, un ou plusieurs par facture)
create table if not exists public.payments (
  id bigserial primary key,
  invoice_id uuid references public.invoices(id) on delete cascade,
  date_reglement date default current_date,
  mode text default 'especes'            -- especes, cheque, virement, wave, orange_money, autre
    check (mode in ('especes','cheque','virement','wave','orange_money','autre')),
  reference text default '',
  montant numeric(14,2) not null,
  observations text default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- 5) HISTORIQUE des actions de facturation
create table if not exists public.invoice_history (
  id bigserial primary key,
  invoice_id uuid references public.invoices(id) on delete set null,
  invoice_numero text default '',
  action text not null,                   -- création, modification, impression, PDF, paiement, annulation
  user_id uuid references public.profiles(id) on delete set null,
  user_name text default '',
  ts timestamptz default now()
);

-- 6) Compteur de numérotation par exercice
create table if not exists public.invoice_counters (
  exercice int primary key,
  last_num int default 0
);

-- ===== SÉCURITÉ (RLS) =====
alter table public.billing_clients  enable row level security;
alter table public.invoices         enable row level security;
alter table public.payments         enable row level security;
alter table public.invoice_history  enable row level security;
alter table public.invoice_counters enable row level security;

-- Qui peut accéder au module facturation : admin ou assistante.
create or replace function public.is_billing_user()
returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from public.profiles where id = auth.uid() and role in ('admin','assistante')) $$;

-- Lecture + écriture réservées aux utilisateurs facturation.
create policy "billing_clients rw" on public.billing_clients for all to authenticated
  using (public.is_billing_user()) with check (public.is_billing_user());
create policy "invoices rw" on public.invoices for all to authenticated
  using (public.is_billing_user()) with check (public.is_billing_user());
create policy "payments rw" on public.payments for all to authenticated
  using (public.is_billing_user()) with check (public.is_billing_user());
create policy "invoice_history rw" on public.invoice_history for all to authenticated
  using (public.is_billing_user()) with check (public.is_billing_user());
create policy "invoice_counters rw" on public.invoice_counters for all to authenticated
  using (public.is_billing_user()) with check (public.is_billing_user());

-- Temps réel
alter publication supabase_realtime add table public.billing_clients;
alter publication supabase_realtime add table public.invoices;
alter publication supabase_realtime add table public.payments;

-- Ajout : équipe de mission sur la facture (pour le modèle CMD)
alter table public.invoices add column if not exists equipe text default '';
