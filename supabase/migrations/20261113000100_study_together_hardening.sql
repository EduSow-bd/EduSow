-- Follow-up hardening for Study Together
drop policy if exists study_group_members_delete_owner_or_self on public.study_group_members;
create policy study_group_members_delete_owner_or_self on public.study_group_members
for delete to authenticated using (
 (select auth.jwt()->>'is_anonymous')='true'
 and (
  (user_id=(select auth.uid()) and role='member')
  or exists(
   select 1 from public.study_groups g
   where g.id=study_group_members.group_id
    and g.owner_id=(select auth.uid())
    and study_group_members.user_id<>(select auth.uid())
  )
 )
);

create index if not exists study_group_activity_actor_idx on public.study_group_activity(actor_id);
create index if not exists study_group_activity_item_idx on public.study_group_activity(item_id);
create index if not exists study_group_invites_created_by_idx on public.study_group_invites(created_by);
create index if not exists study_group_items_created_by_idx on public.study_group_items(created_by);
create index if not exists study_groups_owner_idx on public.study_groups(owner_id);

drop policy if exists study_group_files_upload_member on storage.objects;
create policy study_group_files_upload_member on storage.objects for insert to authenticated with check (
 bucket_id='study-group-files'
 and (storage.foldername(name))[2]=(select auth.uid())::text
 and (select auth.jwt()->>'is_anonymous')='true'
 and private.is_study_group_member(((storage.foldername(name))[1])::uuid)
);
drop policy if exists study_group_files_read_member on storage.objects;
create policy study_group_files_read_member on storage.objects for select to authenticated using (
 bucket_id='study-group-files'
 and (select auth.jwt()->>'is_anonymous')='true'
 and private.is_study_group_member(((storage.foldername(name))[1])::uuid)
);
drop policy if exists study_group_files_delete_owner_or_uploader on storage.objects;
create policy study_group_files_delete_owner_or_uploader on storage.objects for delete to authenticated using (
 bucket_id='study-group-files'
 and (select auth.jwt()->>'is_anonymous')='true'
 and (
  (storage.foldername(name))[2]=(select auth.uid())::text
  or exists(select 1 from public.study_groups g where g.id::text=(storage.foldername(name))[1] and g.owner_id=(select auth.uid()))
 )
);
