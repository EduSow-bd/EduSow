-- EduSow Study Together core schema
-- Additive migration: existing EduSow tables and learning tools are not modified.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.study_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check(char_length(trim(display_name)) between 2 and 24),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.study_groups (
 id uuid primary key default gen_random_uuid(),
 name text not null check(char_length(trim(name)) between 2 and 50),
 description text check(description is null or char_length(description)<=240),
 owner_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.study_group_members (
 group_id uuid not null references public.study_groups(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null default 'member' check(role in ('owner','member')),
 joined_at timestamptz not null default now(),
 primary key(group_id,user_id)
);
create table if not exists public.study_group_invites (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.study_groups(id) on delete cascade,
 token_hash text not null unique,
 created_by uuid not null references auth.users(id) on delete cascade,
 expires_at timestamptz not null,
 max_uses integer not null default 20 check(max_uses between 1 and 100),
 use_count integer not null default 0 check(use_count>=0),
 revoked_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.study_group_items (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.study_groups(id) on delete cascade,
 created_by uuid not null references auth.users(id) on delete cascade,
 item_type text not null check(item_type in ('lesson','quiz','flashcards','study_material')),
 title text not null check(char_length(trim(title)) between 1 and 120),
 content jsonb not null check(jsonb_typeof(content)='object' and octet_length(content::text)<=1048576),
 created_at timestamptz not null default now()
);
create table if not exists public.study_group_activity (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.study_groups(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,
 activity_type text not null check(activity_type in ('group_created','member_joined','item_shared')),
 item_id uuid references public.study_group_items(id) on delete cascade,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create index if not exists study_group_members_user_idx on public.study_group_members(user_id,group_id);
create index if not exists study_group_items_group_created_idx on public.study_group_items(group_id,created_at desc);
create index if not exists study_group_activity_group_created_idx on public.study_group_activity(group_id,created_at desc);
create index if not exists study_group_invites_group_idx on public.study_group_invites(group_id);

alter table public.study_profiles enable row level security;
alter table public.study_groups enable row level security;
alter table public.study_group_members enable row level security;
alter table public.study_group_invites enable row level security;
alter table public.study_group_items enable row level security;
alter table public.study_group_activity enable row level security;

create or replace function private.is_study_group_member(p_group_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$ select exists(select 1 from public.study_group_members m where m.group_id=p_group_id and m.user_id=auth.uid()); $$;
create or replace function private.are_study_group_peers(p_other_user_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$ select exists(select 1 from public.study_group_members mine join public.study_group_members theirs on theirs.group_id=mine.group_id where mine.user_id=auth.uid() and theirs.user_id=p_other_user_id); $$;
revoke all on function private.is_study_group_member(uuid) from public,anon;
revoke all on function private.are_study_group_peers(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.is_study_group_member(uuid) to authenticated;
grant execute on function private.are_study_group_peers(uuid) to authenticated;

drop policy if exists study_profiles_select_related on public.study_profiles;
create policy study_profiles_select_related on public.study_profiles for select to authenticated using(
 user_id=auth.uid() or ((auth.jwt()->>'is_anonymous')='true' and private.are_study_group_peers(user_id))
);
drop policy if exists study_profiles_insert_self on public.study_profiles;
create policy study_profiles_insert_self on public.study_profiles for insert to authenticated with check(user_id=auth.uid() and (auth.jwt()->>'is_anonymous')='true');
drop policy if exists study_profiles_update_self on public.study_profiles;
create policy study_profiles_update_self on public.study_profiles for update to authenticated using(user_id=auth.uid() and (auth.jwt()->>'is_anonymous')='true') with check(user_id=auth.uid() and (auth.jwt()->>'is_anonymous')='true');

drop policy if exists study_groups_select_members on public.study_groups;
create policy study_groups_select_members on public.study_groups for select to authenticated using((auth.jwt()->>'is_anonymous')='true' and private.is_study_group_member(id));
drop policy if exists study_groups_update_owner on public.study_groups;
create policy study_groups_update_owner on public.study_groups for update to authenticated using(owner_id=auth.uid() and (auth.jwt()->>'is_anonymous')='true') with check(owner_id=auth.uid() and (auth.jwt()->>'is_anonymous')='true');
drop policy if exists study_groups_delete_owner on public.study_groups;
create policy study_groups_delete_owner on public.study_groups for delete to authenticated using(owner_id=auth.uid() and (auth.jwt()->>'is_anonymous')='true');

drop policy if exists study_group_members_select_group on public.study_group_members;
create policy study_group_members_select_group on public.study_group_members for select to authenticated using((auth.jwt()->>'is_anonymous')='true' and private.is_study_group_member(group_id));
drop policy if exists study_group_members_delete_owner_or_self on public.study_group_members;
create policy study_group_members_delete_owner_or_self on public.study_group_members for delete to authenticated using(
 (auth.jwt()->>'is_anonymous')='true' and ((user_id=auth.uid() and role='member') or exists(select 1 from public.study_groups g where g.id=study_group_members.group_id and g.owner_id=auth.uid() and study_group_members.user_id<>auth.uid()))
);

drop policy if exists study_group_invites_select_owner on public.study_group_invites;
create policy study_group_invites_select_owner on public.study_group_invites for select to authenticated using((auth.jwt()->>'is_anonymous')='true' and exists(select 1 from public.study_groups g where g.id=group_id and g.owner_id=auth.uid()));
drop policy if exists study_group_invites_update_owner on public.study_group_invites;
create policy study_group_invites_update_owner on public.study_group_invites for update to authenticated using((auth.jwt()->>'is_anonymous')='true' and exists(select 1 from public.study_groups g where g.id=group_id and g.owner_id=auth.uid())) with check(exists(select 1 from public.study_groups g where g.id=group_id and g.owner_id=auth.uid()));

drop policy if exists study_group_items_select_members on public.study_group_items;
create policy study_group_items_select_members on public.study_group_items for select to authenticated using((auth.jwt()->>'is_anonymous')='true' and private.is_study_group_member(group_id));
drop policy if exists study_group_items_insert_members on public.study_group_items;
create policy study_group_items_insert_members on public.study_group_items for insert to authenticated with check(created_by=auth.uid() and (auth.jwt()->>'is_anonymous')='true' and private.is_study_group_member(group_id));
drop policy if exists study_group_items_delete_creator_or_owner on public.study_group_items;
create policy study_group_items_delete_creator_or_owner on public.study_group_items for delete to authenticated using((auth.jwt()->>'is_anonymous')='true' and (created_by=auth.uid() or exists(select 1 from public.study_groups g where g.id=group_id and g.owner_id=auth.uid())));

drop policy if exists study_group_activity_select_members on public.study_group_activity;
create policy study_group_activity_select_members on public.study_group_activity for select to authenticated using((auth.jwt()->>'is_anonymous')='true' and private.is_study_group_member(group_id));

grant usage on schema public to authenticated;
grant select,insert,update on public.study_profiles to authenticated;
grant select,update,delete on public.study_groups to authenticated;
grant select,delete on public.study_group_members to authenticated;
grant select,update on public.study_group_invites to authenticated;
grant select,insert,delete on public.study_group_items to authenticated;
grant select on public.study_group_activity to authenticated;

create or replace function public.create_study_group(p_name text,p_description text default null)
returns uuid language plpgsql security definer set search_path=public,extensions
as $$
declare v_uid uuid:=auth.uid(); v_group_id uuid; v_name text:=trim(coalesce(p_name,'')); v_description text:=nullif(trim(coalesce(p_description,'')),'');
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'Anonymous Study Together session required'; end if;
 if char_length(v_name)<2 or char_length(v_name)>50 then raise exception 'Group name must be between 2 and 50 characters'; end if;
 if v_description is not null and char_length(v_description)>240 then raise exception 'Description must be 240 characters or fewer'; end if;
 insert into public.study_groups(name,description,owner_id) values(v_name,v_description,v_uid) returning id into v_group_id;
 insert into public.study_group_members(group_id,user_id,role) values(v_group_id,v_uid,'owner');
 insert into public.study_group_activity(group_id,actor_id,activity_type,details) values(v_group_id,v_uid,'group_created',jsonb_build_object('group_name',v_name));
 return v_group_id;
end; $$;

create or replace function public.create_study_group_invite(p_group_id uuid,p_expires_in_hours integer default 168,p_max_uses integer default 20)
returns text language plpgsql security definer set search_path=public,extensions
as $$
declare v_uid uuid:=auth.uid(); v_code text;
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'Anonymous Study Together session required'; end if;
 if not exists(select 1 from public.study_groups where id=p_group_id and owner_id=v_uid) then raise exception 'Only the group owner can create invitations'; end if;
 if p_expires_in_hours<1 or p_expires_in_hours>720 or p_max_uses<1 or p_max_uses>100 then raise exception 'Invalid invitation expiry or use limit'; end if;
 v_code:=upper(encode(extensions.gen_random_bytes(16),'hex'));
 insert into public.study_group_invites(group_id,token_hash,created_by,expires_at,max_uses) values(p_group_id,encode(extensions.digest(v_code,'sha256'),'hex'),v_uid,now()+make_interval(hours=>p_expires_in_hours),p_max_uses);
 return v_code;
end; $$;

create or replace function public.join_study_group(p_invite_code text)
returns uuid language plpgsql security definer set search_path=public,extensions
as $$
declare v_uid uuid:=auth.uid(); v_invite public.study_group_invites%rowtype;
begin
 if v_uid is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'Anonymous Study Together session required'; end if;
 if p_invite_code is null or char_length(trim(p_invite_code))<>32 then raise exception 'Invalid invitation code'; end if;
 select * into v_invite from public.study_group_invites where token_hash=encode(extensions.digest(upper(trim(p_invite_code)),'sha256'),'hex') for update;
 if not found or v_invite.revoked_at is not null or v_invite.expires_at<=now() or v_invite.use_count>=v_invite.max_uses then raise exception 'This invitation is invalid, expired, or no longer available'; end if;
 if exists(select 1 from public.study_group_members where group_id=v_invite.group_id and user_id=v_uid) then return v_invite.group_id; end if;
 insert into public.study_group_members(group_id,user_id,role) values(v_invite.group_id,v_uid,'member');
 update public.study_group_invites set use_count=use_count+1 where id=v_invite.id;
 insert into public.study_group_activity(group_id,actor_id,activity_type,details) values(v_invite.group_id,v_uid,'member_joined','{}'::jsonb);
 return v_invite.group_id;
end; $$;

revoke all on function public.create_study_group(text,text) from public;
revoke all on function public.create_study_group_invite(uuid,integer,integer) from public;
revoke all on function public.join_study_group(text) from public;
grant execute on function public.create_study_group(text,text) to authenticated;
grant execute on function public.create_study_group_invite(uuid,integer,integer) to authenticated;
grant execute on function public.join_study_group(text) to authenticated;

create or replace function private.log_study_group_item_share()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
 insert into public.study_group_activity(group_id,actor_id,activity_type,item_id,details)
 values(new.group_id,new.created_by,'item_shared',new.id,jsonb_build_object('item_type',new.item_type,'title',new.title));
 return new;
end; $$;
revoke all on function private.log_study_group_item_share() from public,anon,authenticated;
drop trigger if exists study_group_item_share_activity on public.study_group_items;
create trigger study_group_item_share_activity after insert on public.study_group_items for each row execute function private.log_study_group_item_share();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('study-group-files','study-group-files',false,20971520,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do nothing;

drop policy if exists study_group_files_upload_member on storage.objects;
create policy study_group_files_upload_member on storage.objects for insert to authenticated with check(
 bucket_id='study-group-files' and (storage.foldername(name))[2]=auth.uid()::text
 and (auth.jwt()->>'is_anonymous')='true' and private.is_study_group_member(((storage.foldername(name))[1])::uuid)
);
drop policy if exists study_group_files_read_member on storage.objects;
create policy study_group_files_read_member on storage.objects for select to authenticated using(
 bucket_id='study-group-files' and (auth.jwt()->>'is_anonymous')='true'
 and private.is_study_group_member(((storage.foldername(name))[1])::uuid)
);
drop policy if exists study_group_files_delete_owner_or_uploader on storage.objects;
create policy study_group_files_delete_owner_or_uploader on storage.objects for delete to authenticated using(
 bucket_id='study-group-files' and (auth.jwt()->>'is_anonymous')='true'
 and ((storage.foldername(name))[2]=auth.uid()::text or exists(select 1 from public.study_groups g where g.id::text=(storage.foldername(name))[1] and g.owner_id=auth.uid()))
);
