-- The moderation receiver, in one transaction. The `platform-moderation` Edge
-- Function verifies the signature, then calls this with the webhook id and the
-- message. The three rules are the reference receiver's (the SDK's
-- `applyModerationEvent`), ported to SQL:
--
--   1. Idempotent: an id is applied at most once. A replay answers
--      'duplicate'.
--   2. Order-safe: a message dated before the last decision on the same item
--      answers 'stale' and changes nothing.
--   3. Atomic: the id, the decision and the change commit together. If the
--      change fails, the id is not recorded, so the platform's retry is
--      applied rather than ignored as a duplicate.
--
-- What a message does:
--   content.hide / content.remove   quarantinedBy on the session or profile, so
--                                   RLS shows the row to its author only
--   content.restore                 clears it
--   user.suspend / user.ban         the user cannot sign in and every policy
--                                   treats them as restricted
--   user.restore                    lifts both
--   user.delete                     the platform account is gone (DevDogs
--                                   account deletion). Here: the same lockout
--                                   as a ban, the state recorded as 'deleted'
--                                   with the reason dropped. The auth user
--                                   itself is deleted by the Edge Function
--                                   through the admin API right after this
--                                   commits, and DogPack's own foreign keys
--                                   (all on delete cascade) remove the rest.
--
-- A message about content or a user DogPack has no row for is recorded and
-- answers 'applied': there is nothing to hide, and a later row would not be
-- hidden retroactively, which is the platform's decision to resend.
create function moderation.apply_event(p_id text, p_message jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := p_message ->> 'type';
  v_data jsonb := p_message -> 'data';
  v_decided timestamptz := (p_message ->> 'timestamp')::timestamptz;
  v_is_content boolean := v_type like 'content.%';
  v_key text;
  v_last timestamptz;
  v_inserted integer;
  v_ref uuid;
  v_platform_user uuid;
  v_user uuid;
  v_ban_until constant timestamptz := now() + interval '100 years';
begin
  if p_id is null or p_id = '' then
    raise exception 'missing message id';
  end if;
  if v_type not in ('content.hide', 'content.remove', 'content.restore',
                    'user.suspend', 'user.ban', 'user.restore', 'user.delete') then
    raise exception 'unknown message type %', v_type;
  end if;
  if v_decided is null then
    raise exception 'missing timestamp';
  end if;

  if v_is_content then
    v_key := 'content:' || (v_data ->> 'contentType') || ':' || (v_data ->> 'contentRef');
  else
    v_platform_user := (v_data ->> 'userId')::uuid;
    v_key := 'user:' || v_platform_user::text;
  end if;

  -- 1. Idempotent. The id is recorded before the ordering check, so a stale
  -- message that is replayed is a duplicate, not stale twice.
  insert into moderation.events ("id", "type", "itemKey", "decidedAt", "payload")
  values (p_id, v_type, v_key, v_decided,
          -- A deleted account keeps no free text about the person, here either.
          case when v_type = 'user.delete' then jsonb_set(p_message, '{data,reason}', 'null'::jsonb) else p_message end)
  on conflict ("id") do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return 'duplicate';
  end if;

  -- 2. Order-safe. The advisory lock makes two messages for one item apply one
  -- after the other, even when neither has a decision row to lock yet.
  perform pg_advisory_xact_lock(hashtextextended(v_key, 0));
  select d."decidedAt" into v_last from moderation.decisions d where d."itemKey" = v_key for update;
  if found and v_decided < v_last then
    update moderation.events e set "outcome" = 'stale' where e."id" = p_id;
    return 'stale';
  end if;

  insert into moderation.decisions ("itemKey", "type", "decidedAt")
  values (v_key, v_type, v_decided)
  on conflict ("itemKey") do update set "type" = excluded."type", "decidedAt" = excluded."decidedAt";

  -- 3. Apply.
  if v_is_content then
    -- A content ref that is not a uuid cannot be one of our rows.
    if (v_data ->> 'contentRef') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_ref := (v_data ->> 'contentRef')::uuid;
      if (v_data ->> 'contentType') = 'session' then
        update dogpack.sessions s
           set "quarantinedBy" = case when v_type = 'content.restore' then null else p_id end,
               "quarantinedAt" = case when v_type = 'content.restore' then null else v_decided end
         where s."id" = v_ref;
      elsif (v_data ->> 'contentType') = 'profile' then
        update dogpack.profiles p
           set "quarantinedBy" = case when v_type = 'content.restore' then null else p_id end,
               "quarantinedAt" = case when v_type = 'content.restore' then null else v_decided end
         where p."userId" = v_ref;
      end if;
    end if;
  else
    insert into moderation.user_states ("platformUserId", "state", "reason", "decidedAt")
    values (
      v_platform_user,
      case v_type when 'user.suspend' then 'suspended' when 'user.ban' then 'banned'
                  when 'user.delete' then 'deleted' else 'active' end,
      -- A deleted account keeps no free text about the person.
      case when v_type = 'user.delete' then null else v_data ->> 'reason' end,
      v_decided
    )
    on conflict ("platformUserId") do update
      set "state" = excluded."state", "reason" = excluded."reason", "decidedAt" = excluded."decidedAt";

    select i.user_id into v_user
      from auth.identities i
     where i.provider = 'custom:devdogsuga' and i.provider_id = v_platform_user::text;

    if v_user is not null then
      if v_type = 'user.restore' then
        update auth.users u set banned_until = null where u.id = v_user;
      else
        -- Sign-in is refused from now on, and the sessions they hold die with
        -- the ban rather than at their next refresh.
        update auth.users u set banned_until = v_ban_until where u.id = v_user;
        delete from auth.sessions s where s.user_id = v_user;
      end if;
    end if;
  end if;

  return 'applied';
end;
$$;

revoke all on function moderation.apply_event(text, jsonb) from public, anon, authenticated;
grant execute on function moderation.apply_event(text, jsonb) to service_role;
