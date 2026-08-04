-- ---------------------------------------------------------------------------
-- Stock Options Academy — let a learner delete their own account.
--
-- Google Play requires any app that offers account creation to also offer
-- account deletion, from inside the app and from a public web URL. This is the
-- server half.
--
-- Deleting the auth.users row is enough to remove everything: profiles,
-- lesson_progress and streaks all reference auth.users(id) ON DELETE CASCADE
-- (see 20260730120000_phase6_init.sql), so the cascade clears them in the same
-- transaction. Nothing is left behind holding the username.
--
-- Idempotent: safe to re-run.
-- ---------------------------------------------------------------------------

-- Deletes the CALLER's account. Takes no arguments on purpose — the identity
-- comes from the JWT via auth.uid(), so this cannot be pointed at anyone else
-- no matter what a modified client sends.
--
-- SECURITY DEFINER because auth.users belongs to the auth schema and a normal
-- signed-in role cannot delete from it. search_path is pinned empty so that
-- nothing here resolves through a caller-controlled schema.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    -- 28000 = invalid_authorization_specification. An anonymous caller must
    -- not be able to probe this function's behaviour.
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  delete from auth.users where id = uid;
end;
$$;

-- A SECURITY DEFINER function is executable by PUBLIC unless told otherwise,
-- and this one deletes data — so revoke first, then grant only to signed-in
-- users. `anon` must never reach it.
revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;

comment on function public.delete_own_account() is
  'Deletes the calling user''s auth.users row; profile, progress and streak '
  'rows cascade. Irreversible. Required by Google Play account-deletion policy.';
