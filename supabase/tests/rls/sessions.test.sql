begin;
select plan(2);
select has_table('dogpack', 'sessions', 'sessions exists');
select ok((select relrowsecurity from pg_class where oid = 'dogpack.sessions'::regclass), 'RLS is on');
select * from finish();
rollback;
