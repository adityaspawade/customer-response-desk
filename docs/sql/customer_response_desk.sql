-- Schema snapshot for the dedicated, single-team pilot. No customer data or secrets.
create schema if not exists desk_private;
revoke all on schema desk_private from public, anon;
grant usage on schema desk_private to authenticated;

create table desk_private.access_list (
 email text primary key check (email = lower(btrim(email))),
 label text not null check (length(label) between 1 and 100),
 role text not null check (role in ('owner','agent')),
 enabled boolean not null default true,
 added_at timestamptz not null default now()
);
create table desk_private.case_revisions (
 case_id uuid not null,
 version integer not null,
 actor_id uuid not null,
 saved_at timestamptz not null default now(),
 data jsonb not null,
 primary key (case_id, version)
);
revoke all on all tables in schema desk_private from public, anon, authenticated;

-- Authorization comes from confirmed Auth identities and an administrator-owned
-- access list. User-editable JWT metadata is never used for authorization.
create function desk_private.pilot_profile() returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('role', a.role, 'label', a.label)
 from desk_private.access_list a join auth.users u on lower(u.email) = a.email
 where u.id = (select auth.uid()) and u.email_confirmed_at is not null and a.enabled
$$;
revoke all on function desk_private.pilot_profile() from public, anon;
grant execute on function desk_private.pilot_profile() to authenticated;

create function public.desk_profile() returns jsonb
language sql stable security invoker set search_path = '' as $$
 select desk_private.pilot_profile()
$$;
revoke all on function public.desk_profile() from public, anon;
grant execute on function public.desk_profile() to authenticated;

create table public.desk_cases (
 id uuid primary key default gen_random_uuid(),
 data jsonb not null,
 version integer not null default 1,
 created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index desk_cases_display_id on public.desk_cases ((data->>'id'));
create unique index desk_cases_reference_unique
 on public.desk_cases ((lower(btrim(data->>'externalRef'))))
 where btrim(coalesce(data->>'externalRef','')) <> '';
create index desk_cases_updated_at on public.desk_cases(updated_at desc);
create index desk_cases_created_by on public.desk_cases(created_by);
create index desk_cases_updated_by on public.desk_cases(updated_by);
alter table public.desk_cases enable row level security;
revoke all on public.desk_cases from public, anon, authenticated;
grant select, insert, update on public.desk_cases to authenticated;
create policy desk_team_read on public.desk_cases for select to authenticated
 using ((select desk_private.pilot_profile()) is not null);
create policy desk_team_insert on public.desk_cases for insert to authenticated
 with check ((select desk_private.pilot_profile()) is not null and created_by=(select auth.uid()) and updated_by=(select auth.uid()));
create policy desk_team_update on public.desk_cases for update to authenticated
 using ((select desk_private.pilot_profile()) is not null)
 with check ((select desk_private.pilot_profile()) is not null and updated_by=(select auth.uid()));

create function desk_private.validate_and_record_case() returns trigger
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); field text; old_length integer; event jsonb; state text;
begin
 if actor is null or desk_private.pilot_profile() is null then
  raise exception 'Pilot team access required' using errcode='42501';
 end if;
 if jsonb_typeof(new.data) <> 'object' or octet_length(new.data::text)>131072 then
  raise exception 'Case must be an object smaller than 128 KB';
 end if;
 foreach field in array array['id','customer','contact','category','subject','summary','source','remedy','owner','state','nextAction','due','waitingReason','externalRef','draft','resolution'] loop
  if jsonb_typeof(new.data->field) is distinct from 'string' then raise exception 'Invalid case field: %',field; end if;
 end loop;
 if btrim(new.data->>'id')='' or btrim(new.data->>'customer')='' or btrim(new.data->>'subject')='' or btrim(new.data->>'summary')='' then raise exception 'Customer, subject, summary and case ID are required'; end if;
 if new.data->>'category' not in ('Enquiry','Complaint') then raise exception 'Invalid category'; end if;
 state := new.data->>'state';
 if state not in ('New','Needs action','Waiting for customer','Waiting for team','Resolved') then raise exception 'Invalid state'; end if;
 if coalesce(new.data->>'due','')<>'' then perform (new.data->>'due')::timestamptz; end if;
 if state not in ('New','Resolved') and (btrim(new.data->>'owner')='' or btrim(new.data->>'nextAction')='' or new.data->>'due'='') then raise exception 'Active cases require an owner, action and deadline'; end if;
 if state in ('Waiting for customer','Waiting for team') and btrim(new.data->>'waitingReason')='' then raise exception 'Waiting reason required'; end if;
 if state='Resolved' and btrim(new.data->>'resolution')='' then raise exception 'Resolution outcome required'; end if;
 if jsonb_typeof(new.data->'timeline') is distinct from 'array' or jsonb_array_length(new.data->'timeline')<1 then raise exception 'Case history required'; end if;
 for event in select value from jsonb_array_elements(new.data->'timeline') loop
  if jsonb_typeof(event->'type') is distinct from 'string' or jsonb_typeof(event->'text') is distinct from 'string' or jsonb_typeof(event->'at') is distinct from 'string' then raise exception 'Invalid history event'; end if;
  perform (event->>'at')::timestamptz;
 end loop;
 if tg_op='UPDATE' then
  if new.id<>old.id or new.created_by<>old.created_by or new.data->>'id'<>old.data->>'id' then raise exception 'Case identity cannot be changed'; end if;
  old_length:=jsonb_array_length(old.data->'timeline');
  if jsonb_array_length(new.data->'timeline')<=old_length then raise exception 'Every change needs a new history event'; end if;
  if exists(select 1 from generate_series(0,old_length-1) i where new.data->'timeline'->i is distinct from old.data->'timeline'->i) then raise exception 'Previous history cannot be changed'; end if;
  if old.data->>'state'<>'Resolved' and state='Resolved' and new.data->'timeline'->-1->>'type'<>'Resolved' then raise exception 'Use the resolution workflow'; end if;
  if old.data->>'state'='Resolved' and state<>'Resolved' and new.data->'timeline'->-1->>'type'<>'Reopened' then raise exception 'Use the reopening workflow'; end if;
  new.version:=old.version+1;new.created_at:=old.created_at;
 else
  if state='Resolved' then raise exception 'Create an open case, then resolve it with an outcome'; end if;
  new.version:=1;new.created_by:=actor;new.created_at:=now();
 end if;
 new.updated_by:=actor;new.updated_at:=now();
 new.data:=jsonb_set(jsonb_set(new.data,'{createdAt}',to_jsonb(new.created_at)), '{updatedAt}',to_jsonb(new.updated_at));
 insert into desk_private.case_revisions(case_id,version,actor_id,data) values(new.id,new.version,actor,new.data);
 return new;
end $$;
revoke all on function desk_private.validate_and_record_case() from public, anon, authenticated;
create trigger desk_validate_case before insert or update on public.desk_cases
 for each row execute function desk_private.validate_and_record_case();

create function desk_private.manage_access(p_email text default null,p_label text default null,p_role text default null,p_enabled boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare own_email text; result jsonb;
begin
 if auth.uid() is null or (desk_private.pilot_profile()->>'role') is distinct from 'owner' then raise exception 'Pilot owner access required' using errcode='42501'; end if;
 if p_email is not null then
  p_email:=lower(btrim(p_email));
  if p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_email)>254 or length(btrim(p_label)) not between 1 and 100 or p_role not in ('owner','agent') or p_role is null or p_label is null then raise exception 'Valid email, name and role required'; end if;
  select lower(email) into own_email from auth.users where id=auth.uid();
  if p_email=own_email and (p_role<>'owner' or not p_enabled) then raise exception 'You cannot remove your own owner access'; end if;
  insert into desk_private.access_list(email,label,role,enabled) values(p_email,btrim(p_label),p_role,p_enabled)
   on conflict(email) do update set label=excluded.label,role=excluded.role,enabled=excluded.enabled;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('email',email,'label',label,'role',role,'enabled',enabled) order by email),'[]'::jsonb) into result from desk_private.access_list;
 return result;
end $$;
revoke all on function desk_private.manage_access(text,text,text,boolean) from public,anon;
grant execute on function desk_private.manage_access(text,text,text,boolean) to authenticated;
create function public.desk_manage_access(p_email text default null,p_label text default null,p_role text default null,p_enabled boolean default true) returns jsonb
language sql security invoker set search_path = '' as $$
 select desk_private.manage_access(p_email,p_label,p_role,p_enabled)
$$;
revoke all on function public.desk_manage_access(text,text,text,boolean) from public,anon;
grant execute on function public.desk_manage_access(text,text,text,boolean) to authenticated;

alter table desk_private.access_list enable row level security;
alter table desk_private.case_revisions enable row level security;
-- Private tables intentionally have no client policies. Only checked helper functions access them.
