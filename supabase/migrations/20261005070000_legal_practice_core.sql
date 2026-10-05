-- British Case Flow: legal practice core
-- Adds matter-opening, contacts, parties, conflict checks, tasks and notes.
-- Human legal decisions remain explicit; no automatic conflict clearance or legal deadline calculation.

do $$ begin
  create type public.contact_kind as enum ('PERSON', 'ORGANISATION');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.matter_status as enum (
    'PROSPECT_REVIEW',
    'CONFLICT_REVIEW',
    'READY_TO_OPEN',
    'OPEN',
    'ON_HOLD',
    'CLOSING',
    'CLOSED',
    'DECLINED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.engagement_state as enum (
    'NOT_SENT',
    'SENT',
    'SIGNED',
    'DECLINED',
    'NOT_REQUIRED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.matter_contact_role as enum (
    'CLIENT',
    'PROSPECT',
    'SPOUSE_PARTNER',
    'SPONSOR_EMPLOYER',
    'OPPOSING_PARTY',
    'OPPOSING_COUNSEL',
    'WITNESS',
    'RELATED_ENTITY',
    'OTHER'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.conflict_review_outcome as enum (
    'PENDING',
    'CLEAR',
    'POTENTIAL_CONFLICT',
    'ESCALATED',
    'RESOLVED_CLEAR',
    'RESOLVED_DECLINE'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.task_status as enum ('TODO', 'IN_PROGRESS', 'DONE', 'CANCELLED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.task_priority as enum ('LOW', 'NORMAL', 'HIGH', 'URGENT');
exception when duplicate_object then null; end $$;

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  kind public.contact_kind not null,
  display_name text not null check (char_length(trim(display_name)) between 1 and 200),
  first_name text,
  last_name text,
  organisation_name text,
  email text,
  phone text,
  date_of_birth date,
  metadata jsonb not null default '{}'::jsonb,
  created_by_auth_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, firm_id)
);

create table if not exists public.contact_aliases (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  contact_id uuid not null,
  alias text not null check (char_length(trim(alias)) between 1 and 200),
  alias_type text not null default 'OTHER' check (alias_type in ('PREVIOUS_NAME','TRADING_NAME','OTHER')),
  created_at timestamptz not null default now(),
  foreign key (contact_id, firm_id) references public.contacts(id, firm_id) on delete cascade
);

create table if not exists public.matters (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  matter_reference text not null,
  title text not null check (char_length(trim(title)) between 1 and 240),
  practice_area text not null default 'IMMIGRATION',
  category text,
  status public.matter_status not null default 'PROSPECT_REVIEW',
  engagement_state public.engagement_state not null default 'NOT_SENT',
  source_enquiry_id uuid,
  responsible_staff_membership_id uuid,
  supervising_staff_membership_id uuid,
  opened_at timestamptz,
  closed_at timestamptz,
  created_by_auth_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (firm_id, matter_reference),
  unique (id, firm_id),
  foreign key (source_enquiry_id, firm_id) references public.enquiries(id, firm_id) on delete restrict,
  foreign key (responsible_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict,
  foreign key (supervising_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict
);

create table if not exists public.matter_contacts (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  matter_id uuid not null,
  contact_id uuid not null,
  role public.matter_contact_role not null,
  is_primary boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique (matter_id, contact_id, role),
  foreign key (matter_id, firm_id) references public.matters(id, firm_id) on delete cascade,
  foreign key (contact_id, firm_id) references public.contacts(id, firm_id) on delete restrict
);

create table if not exists public.conflict_checks (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  enquiry_id uuid,
  matter_id uuid,
  performed_by_staff_membership_id uuid not null,
  outcome public.conflict_review_outcome not null default 'PENDING',
  outcome_reason text,
  reviewed_by_staff_membership_id uuid,
  performed_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    enquiry_id is not null or matter_id is not null
  ),
  foreign key (enquiry_id, firm_id) references public.enquiries(id, firm_id) on delete cascade,
  foreign key (matter_id, firm_id) references public.matters(id, firm_id) on delete cascade,
  foreign key (performed_by_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict,
  foreign key (reviewed_by_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict
);

create table if not exists public.conflict_check_terms (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  conflict_check_id uuid not null,
  term text not null check (char_length(trim(term)) between 1 and 240),
  term_type text not null default 'NAME' check (term_type in ('NAME','ORGANISATION','EMAIL','OTHER')),
  created_at timestamptz not null default now(),
  foreign key (conflict_check_id) references public.conflict_checks(id) on delete cascade
);

create table if not exists public.conflict_check_hits (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  conflict_check_id uuid not null,
  matched_contact_id uuid,
  matched_matter_id uuid,
  matched_value text not null check (char_length(trim(matched_value)) between 1 and 500),
  match_basis text not null,
  similarity_score numeric(5,4) check (similarity_score is null or (similarity_score >= 0 and similarity_score <= 1)),
  staff_disposition text not null default 'UNREVIEWED'
    check (staff_disposition in ('UNREVIEWED','NOT_RELEVANT','POTENTIAL_CONFLICT','CONFIRMED_CONFLICT')),
  disposition_note text,
  reviewed_by_staff_membership_id uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (conflict_check_id) references public.conflict_checks(id) on delete cascade,
  foreign key (matched_contact_id, firm_id) references public.contacts(id, firm_id) on delete set null,
  foreign key (matched_matter_id, firm_id) references public.matters(id, firm_id) on delete set null,
  foreign key (reviewed_by_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict
);

create table if not exists public.enquiry_conversions (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  enquiry_id uuid not null,
  contact_id uuid not null,
  matter_id uuid not null,
  converted_by_staff_membership_id uuid not null,
  conflict_check_id uuid,
  conversion_note text,
  converted_at timestamptz not null default now(),
  unique (enquiry_id),
  foreign key (enquiry_id, firm_id) references public.enquiries(id, firm_id) on delete restrict,
  foreign key (contact_id, firm_id) references public.contacts(id, firm_id) on delete restrict,
  foreign key (matter_id, firm_id) references public.matters(id, firm_id) on delete restrict,
  foreign key (converted_by_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict,
  foreign key (conflict_check_id) references public.conflict_checks(id) on delete restrict
);

create table if not exists public.matter_tasks (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  matter_id uuid not null,
  title text not null check (char_length(trim(title)) between 1 and 240),
  description text,
  status public.task_status not null default 'TODO',
  priority public.task_priority not null default 'NORMAL',
  due_at timestamptz,
  due_date_source text not null default 'WORKFLOW'
    check (due_date_source in ('WORKFLOW','CLIENT_SUPPLIED','LAWYER_CONFIRMED_LEGAL_DEADLINE')),
  assigned_staff_membership_id uuid,
  created_by_staff_membership_id uuid not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (matter_id, firm_id) references public.matters(id, firm_id) on delete cascade,
  foreign key (assigned_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict,
  foreign key (created_by_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict
);

create table if not exists public.matter_notes (
  id uuid primary key default gen_random_uuid(),
  firm_id uuid not null references public.firms(id) on delete cascade,
  matter_id uuid not null,
  body text not null check (char_length(trim(body)) between 1 and 10000),
  note_type text not null default 'INTERNAL' check (note_type in ('INTERNAL','CALL_NOTE','ATTENDANCE_NOTE','OTHER')),
  created_by_staff_membership_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (matter_id, firm_id) references public.matters(id, firm_id) on delete cascade,
  foreign key (created_by_staff_membership_id, firm_id) references public.staff_memberships(id, firm_id) on delete restrict
);

create index if not exists contacts_firm_name_idx on public.contacts(firm_id, lower(display_name));
create index if not exists contact_aliases_firm_alias_idx on public.contact_aliases(firm_id, lower(alias));
create index if not exists matters_firm_status_idx on public.matters(firm_id, status, updated_at desc);
create index if not exists matters_source_enquiry_idx on public.matters(firm_id, source_enquiry_id);
create index if not exists matter_contacts_matter_idx on public.matter_contacts(firm_id, matter_id, role);
create index if not exists conflict_checks_enquiry_idx on public.conflict_checks(firm_id, enquiry_id, performed_at desc);
create index if not exists conflict_checks_matter_idx on public.conflict_checks(firm_id, matter_id, performed_at desc);
create index if not exists conflict_terms_check_idx on public.conflict_check_terms(conflict_check_id);
create index if not exists conflict_hits_check_idx on public.conflict_check_hits(conflict_check_id, staff_disposition);
create index if not exists matter_tasks_due_idx on public.matter_tasks(firm_id, status, due_at);
create index if not exists matter_notes_matter_idx on public.matter_notes(firm_id, matter_id, created_at desc);

alter table public.contacts enable row level security;
alter table public.contact_aliases enable row level security;
alter table public.matters enable row level security;
alter table public.matter_contacts enable row level security;
alter table public.conflict_checks enable row level security;
alter table public.conflict_check_terms enable row level security;
alter table public.conflict_check_hits enable row level security;
alter table public.enquiry_conversions enable row level security;
alter table public.matter_tasks enable row level security;
alter table public.matter_notes enable row level security;

revoke all on table public.contacts from anon, authenticated;
revoke all on table public.contact_aliases from anon, authenticated;
revoke all on table public.matters from anon, authenticated;
revoke all on table public.matter_contacts from anon, authenticated;
revoke all on table public.conflict_checks from anon, authenticated;
revoke all on table public.conflict_check_terms from anon, authenticated;
revoke all on table public.conflict_check_hits from anon, authenticated;
revoke all on table public.enquiry_conversions from anon, authenticated;
revoke all on table public.matter_tasks from anon, authenticated;
revoke all on table public.matter_notes from anon, authenticated;

grant select on table public.contacts to authenticated;
grant select on table public.contact_aliases to authenticated;
grant select on table public.matters to authenticated;
grant select on table public.matter_contacts to authenticated;
grant select on table public.conflict_checks to authenticated;
grant select on table public.conflict_check_terms to authenticated;
grant select on table public.conflict_check_hits to authenticated;
grant select on table public.enquiry_conversions to authenticated;
grant select on table public.matter_tasks to authenticated;
grant select on table public.matter_notes to authenticated;

create policy contacts_staff_select on public.contacts
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy contact_aliases_staff_select on public.contact_aliases
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy matters_staff_select on public.matters
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy matter_contacts_staff_select on public.matter_contacts
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy conflict_checks_staff_select on public.conflict_checks
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy conflict_terms_staff_select on public.conflict_check_terms
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy conflict_hits_staff_select on public.conflict_check_hits
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy enquiry_conversions_staff_select on public.enquiry_conversions
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy matter_tasks_staff_select on public.matter_tasks
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

create policy matter_notes_staff_select on public.matter_notes
for select to authenticated
using ((select private.has_aal2()) and (select private.has_firm_access(firm_id)));

-- Writes are intentionally not granted directly to authenticated users.
-- Sensitive writes should be exposed through reviewed, role-aware RPCs/server functions.
