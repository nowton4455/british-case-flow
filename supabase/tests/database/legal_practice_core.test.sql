create extension if not exists pgtap with schema extensions;

begin;
select plan(25);

select ok(to_regclass('public.contacts') is not null, 'contacts table exists');
select ok(to_regclass('public.contact_aliases') is not null, 'contact aliases table exists');
select ok(to_regclass('public.matters') is not null, 'matters table exists');
select ok(to_regclass('public.matter_contacts') is not null, 'matter contacts table exists');
select ok(to_regclass('public.conflict_checks') is not null, 'conflict checks table exists');
select ok(to_regclass('public.conflict_check_terms') is not null, 'conflict check terms table exists');
select ok(to_regclass('public.conflict_check_hits') is not null, 'conflict check hits table exists');
select ok(to_regclass('public.enquiry_conversions') is not null, 'enquiry conversions table exists');
select ok(to_regclass('public.matter_tasks') is not null, 'matter tasks table exists');
select ok(to_regclass('public.matter_notes') is not null, 'matter notes table exists');

select ok(
  to_regprocedure('public.start_enquiry_conflict_check(text,text[])') is not null,
  'conflict check start RPC exists'
);
select ok(
  to_regprocedure('public.resolve_conflict_check(uuid,public.conflict_review_outcome,text)') is not null,
  'conflict resolution RPC exists'
);
select ok(
  to_regprocedure('public.convert_enquiry_to_matter(text,uuid,text,text)') is not null,
  'enquiry conversion RPC exists'
);

select ok(
  has_function_privilege('authenticated','public.start_enquiry_conflict_check(text,text[])','EXECUTE'),
  'authenticated staff can invoke conflict check RPC'
);
select ok(
  has_function_privilege('authenticated','public.resolve_conflict_check(uuid,public.conflict_review_outcome,text)','EXECUTE'),
  'authenticated staff can invoke conflict resolution RPC subject to server-side role checks'
);
select ok(
  has_function_privilege('authenticated','public.convert_enquiry_to_matter(text,uuid,text,text)','EXECUTE'),
  'authenticated staff can invoke conversion RPC subject to server-side role checks'
);

select ok(
  not has_table_privilege('anon','public.matters','SELECT'),
  'anonymous users cannot read matters'
);
select ok(
  not has_table_privilege('anon','public.contacts','SELECT'),
  'anonymous users cannot read contacts'
);
select ok(
  not has_table_privilege('anon','public.conflict_checks','SELECT'),
  'anonymous users cannot read conflict checks'
);

select ok(
  not has_table_privilege('authenticated','public.matters','INSERT'),
  'authenticated clients cannot directly insert matters'
);
select ok(
  not has_table_privilege('authenticated','public.contacts','INSERT'),
  'authenticated clients cannot directly insert contacts'
);
select ok(
  not has_table_privilege('authenticated','public.conflict_checks','INSERT'),
  'authenticated clients cannot directly insert conflict checks'
);
select ok(
  not has_table_privilege('authenticated','public.enquiry_conversions','INSERT'),
  'authenticated clients cannot bypass conversion RPC'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'conflict_check_terms_same_firm_fk'
  ),
  'conflict terms are tenant-bound to their conflict check'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'enquiry_conversions_conflict_same_firm_fk'
  ),
  'enquiry conversion conflict evidence is tenant-bound'
);

select * from finish();
rollback;
