-- "Delete my DogPack data": removes everything DogPack stores about the caller
-- and returns how many rows went. It does NOT delete the sign-in itself
-- (auth.users: the account the DevDogs sign-in made), and it does not touch
-- moderation.user_states: deleting your data does not lift a suspension or a
-- ban. Signing in again starts from an empty profile.
--
-- Sessions the caller hosts are deleted with their rosters; memberships in
-- other people's sessions, the blocks the caller placed, enrollments and the
-- profile go too. Blocks OTHER members placed against the caller stay: they
-- are those members' data and their protection, and the sign-in (so the uuid)
-- is kept, so deleting your data must not lift a block. The one-time
-- initial-enrollment exception is not reset either (private.onboarded_users). Account deletion proper (the Store Release milestone)
-- builds on this.
create function dogpack.delete_my_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_sessions integer;
  v_memberships integer;
  v_blocks integer;
  v_enrollments integer;
  v_profiles integer;
begin
  if v_user is null then
    raise exception 'not_signed_in' using errcode = 'PT401';
  end if;

  -- Memberships first: deleting a member fires the counter on a session that
  -- may be about to go too, and that is fine either way.
  delete from dogpack.session_members m where m."userId" = v_user;
  get diagnostics v_memberships = row_count;

  delete from dogpack.sessions s where s."hostId" = v_user;
  get diagnostics v_sessions = row_count;

  delete from dogpack.blocks b where b."blockerId" = v_user;
  get diagnostics v_blocks = row_count;

  delete from dogpack.enrollments e where e."userId" = v_user;
  get diagnostics v_enrollments = row_count;

  delete from dogpack.profiles p where p."userId" = v_user;
  get diagnostics v_profiles = row_count;

  return jsonb_build_object(
    'sessions', v_sessions,
    'memberships', v_memberships,
    'blocks', v_blocks,
    'enrollments', v_enrollments,
    'profiles', v_profiles
  );
end;
$$;

revoke all on function dogpack.delete_my_data() from public, anon;
grant execute on function dogpack.delete_my_data() to authenticated;
