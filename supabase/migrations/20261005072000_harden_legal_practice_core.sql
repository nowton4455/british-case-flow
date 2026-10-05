-- British Case Flow: harden legal-practice core tenant boundaries.

alter table public.conflict_checks
  add constraint conflict_checks_id_firm_unique unique (id, firm_id);

alter table public.conflict_check_terms
  add constraint conflict_check_terms_same_firm_fk
  foreign key (conflict_check_id, firm_id)
  references public.conflict_checks(id, firm_id)
  on delete cascade;

alter table public.conflict_check_hits
  add constraint conflict_check_hits_same_firm_fk
  foreign key (conflict_check_id, firm_id)
  references public.conflict_checks(id, firm_id)
  on delete cascade;

alter table public.enquiry_conversions
  add constraint enquiry_conversions_conflict_same_firm_fk
  foreign key (conflict_check_id, firm_id)
  references public.conflict_checks(id, firm_id)
  on delete restrict;

-- The nullable candidate links are evidence references. Do not cascade-delete them
-- or rewrite firm_id; preserve the conflict-check record and prevent destructive deletes.
alter table public.conflict_check_hits
  drop constraint if exists conflict_check_hits_matched_contact_id_firm_id_fkey,
  drop constraint if exists conflict_check_hits_matched_matter_id_firm_id_fkey;

alter table public.conflict_check_hits
  add constraint conflict_check_hits_contact_same_firm_fk
  foreign key (matched_contact_id, firm_id)
  references public.contacts(id, firm_id)
  on delete restrict;

alter table public.conflict_check_hits
  add constraint conflict_check_hits_matter_same_firm_fk
  foreign key (matched_matter_id, firm_id)
  references public.matters(id, firm_id)
  on delete restrict;
