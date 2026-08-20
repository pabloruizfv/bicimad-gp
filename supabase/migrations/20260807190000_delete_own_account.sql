create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requesting_user_id uuid := auth.uid();
begin
  if requesting_user_id is null then
    raise exception 'authentication_required';
  end if;

  -- Application data is removed through the existing ON DELETE CASCADE
  -- constraints. The function can only target the authenticated caller.
  delete from auth.users where id = requesting_user_id;

  if not found then
    raise exception 'user_not_found';
  end if;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
