create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new."updatedAt" := now();
  return new;
end;
$$;

revoke all on function private.touch_updated_at() from public, anon, authenticated;
