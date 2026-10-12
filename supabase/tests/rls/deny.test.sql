begin;
select plan(1);
select ok(false, 'deliberately failing deny test');
select * from finish();
rollback;
