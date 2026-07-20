-- ============================================================
-- CORRECTIF v6b — Ajoute la colonne "equipe" manquante aux factures
-- (à lancer si vous aviez déjà passé migration_v6.sql avant l'ajout du modèle)
-- Supabase > SQL Editor > Run. Sans danger, ne touche pas aux données.
-- ============================================================
alter table public.invoices add column if not exists equipe text default '';

-- Rafraîchit le cache de schéma de l'API (pour que la colonne soit reconnue tout de suite)
notify pgrst, 'reload schema';
