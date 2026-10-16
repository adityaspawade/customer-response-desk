-- Integration checks against the dedicated pilot database. Fixtures always roll back.
begin;
with u as (insert into auth.users(id,email,email_confirmed_at,aud,role) values(gen_random_uuid(),'desk-test-owner@example.invalid',now(),'authenticated','authenticated') returning id)
 select set_config('desk.test_owner',(select id::text from u),true);
with u as (insert into auth.users(id,email,email_confirmed_at,aud,role) values(gen_random_uuid(),'desk-test-agent@example.invalid',now(),'authenticated','authenticated') returning id)
 select set_config('desk.test_agent',(select id::text from u),true);
with u as (insert into auth.users(id,email,email_confirmed_at,aud,role) values(gen_random_uuid(),'desk-test-outside@example.invalid',now(),'authenticated','authenticated') returning id)
 select set_config('desk.test_outside',(select id::text from u),true);
insert into desk_private.access_list(email,label,role) values('desk-test-owner@example.invalid','Test owner','owner'),('desk-test-agent@example.invalid','Test agent','agent');
select set_config('request.jwt.claim.sub',current_setting('desk.test_owner'),true);
set local role authenticated;
do $$ begin
 if public.desk_profile()->>'role' is distinct from 'owner' then raise exception 'FAIL owner profile'; end if;
end $$;
insert into public.desk_cases(data) values(jsonb_build_object('id','RD-TEST-1','customer','Test customer','contact','','category','Enquiry','subject','Test delivery','summary','Fictional test','source','Test','remedy','','owner','Test owner','state','Needs action','nextAction','Check courier','due','2026-11-01T00:00:00Z','waitingReason','','externalRef','TEST-1','draft','','resolution','','escalated',false,'escalationReason','','timeline',jsonb_build_array(jsonb_build_object('type','Created','text','Fictional test','at','2026-10-16T00:00:00Z'))));
select set_config('desk.test_case',(select id::text from public.desk_cases where data->>'id'='RD-TEST-1'),true);
do $$ declare affected integer; c public.desk_cases; begin
 select * into c from public.desk_cases where id=current_setting('desk.test_case')::uuid;
 if c.version<>1 or c.created_by<>auth.uid() or c.updated_by<>auth.uid() then raise exception 'FAIL initial actor/version'; end if;
 update public.desk_cases set data=jsonb_set(data,'{timeline}',data->'timeline'||jsonb_build_array(jsonb_build_object('type','Internal note','text','Checked courier','at','2026-10-16T01:00:00Z'))) where id=c.id and version=1;
 get diagnostics affected=row_count;
 if affected<>1 then raise exception 'FAIL first update'; end if;
 update public.desk_cases set data=data where id=c.id and version=1;
 get diagnostics affected=row_count;
 if affected<>0 then raise exception 'FAIL stale version accepted'; end if;
 begin
  update public.desk_cases set data=jsonb_set(jsonb_set(data,'{timeline,0,text}','"Tampered"'),'{timeline}',jsonb_set(data->'timeline','{0,text}','"Tampered"')||jsonb_build_array(jsonb_build_object('type','Internal note','text','Tampered','at','2026-10-16T02:00:00Z'))) where id=c.id;
  raise exception 'FAIL history tampering accepted';
 exception when others then if sqlerrm not like '%Previous history cannot be changed%' then raise; end if; end;
 begin
  update public.desk_cases set data=jsonb_set(jsonb_set(data,'{owner}','""'),'{timeline}',data->'timeline'||jsonb_build_array(jsonb_build_object('type','Updated','text','Unassigned','at','2026-10-16T02:00:00Z'))) where id=c.id;
  raise exception 'FAIL active unassigned case accepted';
 exception when others then if sqlerrm not like '%Active cases require%' then raise; end if; end;
 begin
  insert into public.desk_cases(data) select jsonb_set(data,'{id}','"RD-TEST-2"') from public.desk_cases where id=c.id;
  raise exception 'FAIL duplicate reference accepted';
 exception when unique_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('desk.test_agent'),true);
do $$ begin
 if (select count(*) from public.desk_cases)<>1 then raise exception 'FAIL agent cannot read team case'; end if;
 begin perform public.desk_manage_access('not-allowed@example.invalid','Invalid','owner',true);raise exception 'FAIL agent granted access';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('desk.test_outside'),true);
do $$ declare affected integer; begin
 if public.desk_profile() is not null then raise exception 'FAIL outsider has profile'; end if;
 if (select count(*) from public.desk_cases)<>0 then raise exception 'FAIL outsider read cases'; end if;
 update public.desk_cases set data=data;
 get diagnostics affected=row_count;
 if affected<>0 then raise exception 'FAIL outsider updated cases'; end if;
 begin
  insert into public.desk_cases(data) values('{}');raise exception 'FAIL outsider inserted case';
 exception when insufficient_privilege then null;end;
 begin perform public.desk_manage_access();raise exception 'FAIL outsider read access list';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('desk.test_owner'),true);
select public.desk_manage_access('desk-test-agent@example.invalid','Test agent','agent',false);
do $$ begin
 begin perform public.desk_manage_access('desk-test-owner@example.invalid','Test owner','agent',true);raise exception 'FAIL owner removed own access';exception when others then if sqlerrm not like '%cannot remove your own owner access%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('desk.test_agent'),true);
do $$ begin if (select count(*) from public.desk_cases)<>0 then raise exception 'FAIL revocation not immediate';end if;end $$;
reset role;
set local role anon;
do $$ begin
 begin perform * from public.desk_cases;raise exception 'FAIL anonymous read';exception when insufficient_privilege then null;end;
 begin perform public.desk_profile();raise exception 'FAIL anonymous RPC';exception when insufficient_privilege then null;end;
 begin perform * from desk_private.access_list;raise exception 'FAIL anonymous private access';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if (select count(*) from desk_private.case_revisions where case_id=current_setting('desk.test_case')::uuid)<>2 then raise exception 'FAIL revision history';end if;
end $$;
rollback;
select 'All access, conflict, duplicate, history and revocation checks passed; fixtures rolled back' as result;
