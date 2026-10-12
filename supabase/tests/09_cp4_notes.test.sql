begin;
create extension if not exists pgtap with schema extensions;
select plan(2);
select ok(exists (select 1 from pg_policies where tablename='cp4_notes' and policyname='cp4_notes_owner'), 'owner policy exists');
select ok((select relrowsecurity from pg_class where oid='dogpack.cp4_notes'::regclass), 'rls on');
select * from finish();
rollback;
