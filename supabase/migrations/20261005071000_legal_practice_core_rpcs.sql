-- British Case Flow: legal practice core RPCs
-- Candidate conflict matching is automated; clearance is always an explicit staff decision.

create extension if not exists pg_trgm;

create or replace function private.current_staff_membership(p_firm_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select sm.id
  from public.staff_memberships sm
  where sm.firm_id = p_firm_id
    and sm.auth_user_id = auth.uid()
    and sm.status = 'active'::public.membership_status
  limit 1;
$$;

grant execute on function private.current_staff_membership(uuid) to authenticated;

create or replace function public.start_enquiry_conflict_check(
  p_enquiry_reference text,
  p_terms text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_enquiry public.enquiries%rowtype;
  v_staff_id uuid;
  v_check_id uuid;
  v_term text;
begin
  if not private.has_aal2() then
    raise exception 'MFA_REQUIRED' using errcode = '42501';
  end if;

  select *
  into v_enquiry
  from public.enquiries e
  where e.public_reference = p_enquiry_reference
  limit 1;

  if v_enquiry.id is null or not private.has_firm_access(v_enquiry.firm_id) then
    raise exception 'ENQUIRY_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_staff_id := private.current_staff_membership(v_enquiry.firm_id);
  if v_staff_id is null then
    raise exception 'STAFF_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  insert into public.conflict_checks (
    firm_id,
    enquiry_id,
    performed_by_staff_membership_id,
    outcome
  ) values (
    v_enquiry.firm_id,
    v_enquiry.id,
    v_staff_id,
    'PENDING'::public.conflict_review_outcome
  )
  returning id into v_check_id;

  -- Always include the prospect name.
  insert into public.conflict_check_terms (firm_id, conflict_check_id, term, term_type)
  values (v_enquiry.firm_id, v_check_id, trim(v_enquiry.full_name), 'NAME');

  -- Add caller-supplied structured terms, removing blanks and duplicates.
  if p_terms is not null then
    foreach v_term in array p_terms loop
      v_term := trim(v_term);
      if char_length(v_term) > 0 and char_length(v_term) <= 240 then
        insert into public.conflict_check_terms (firm_id, conflict_check_id, term, term_type)
        select v_enquiry.firm_id, v_check_id, v_term, 'NAME'
        where not exists (
          select 1
          from public.conflict_check_terms cct
          where cct.conflict_check_id = v_check_id
            and lower(cct.term) = lower(v_term)
        );
      end if;
    end loop;
  end if;

  -- Candidate matches only. A hit never clears or confirms a conflict automatically.
  insert into public.conflict_check_hits (
    firm_id,
    conflict_check_id,
    matched_contact_id,
    matched_value,
    match_basis,
    similarity_score
  )
  select
    v_enquiry.firm_id,
    v_check_id,
    c.id,
    c.display_name,
    'CONTACT_DISPLAY_NAME',
    greatest(similarity(lower(c.display_name), lower(t.term)), 0)::numeric(5,4)
  from public.conflict_check_terms t
  join public.contacts c
    on c.firm_id = v_enquiry.firm_id
   and similarity(lower(c.display_name), lower(t.term)) >= 0.45
  where t.conflict_check_id = v_check_id;

  insert into public.conflict_check_hits (
    firm_id,
    conflict_check_id,
    matched_contact_id,
    matched_value,
    match_basis,
    similarity_score
  )
  select
    v_enquiry.firm_id,
    v_check_id,
    ca.contact_id,
    ca.alias,
    'CONTACT_ALIAS',
    greatest(similarity(lower(ca.alias), lower(t.term)), 0)::numeric(5,4)
  from public.conflict_check_terms t
  join public.contact_aliases ca
    on ca.firm_id = v_enquiry.firm_id
   and similarity(lower(ca.alias), lower(t.term)) >= 0.45
  where t.conflict_check_id = v_check_id;

  insert into public.audit_events (
    firm_id,
    enquiry_id,
    event_type,
    actor_auth_user_id,
    metadata
  ) values (
    v_enquiry.firm_id,
    v_enquiry.id,
    'CONFLICT_CHECK_STARTED',
    auth.uid(),
    jsonb_build_object('conflict_check_id', v_check_id)
  );

  return v_check_id;
end;
$$;

revoke all on function public.start_enquiry_conflict_check(text, text[]) from public, anon;
grant execute on function public.start_enquiry_conflict_check(text, text[]) to authenticated;

create or replace function public.resolve_conflict_check(
  p_conflict_check_id uuid,
  p_outcome public.conflict_review_outcome,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_check public.conflict_checks%rowtype;
  v_staff_id uuid;
begin
  if not private.has_aal2() then
    raise exception 'MFA_REQUIRED' using errcode = '42501';
  end if;

  select * into v_check
  from public.conflict_checks cc
  where cc.id = p_conflict_check_id
  limit 1;

  if v_check.id is null or not private.has_firm_access(v_check.firm_id) then
    raise exception 'CONFLICT_CHECK_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not private.has_firm_role(
    v_check.firm_id,
    array['senior','manager','admin']::public.staff_role[]
  ) then
    raise exception 'INSUFFICIENT_ROLE' using errcode = '42501';
  end if;

  if p_outcome not in (
    'CLEAR'::public.conflict_review_outcome,
    'POTENTIAL_CONFLICT'::public.conflict_review_outcome,
    'ESCALATED'::public.conflict_review_outcome,
    'RESOLVED_CLEAR'::public.conflict_review_outcome,
    'RESOLVED_DECLINE'::public.conflict_review_outcome
  ) then
    raise exception 'INVALID_OUTCOME' using errcode = '22023';
  end if;

  if char_length(trim(coalesce(p_reason,''))) < 10 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  v_staff_id := private.current_staff_membership(v_check.firm_id);

  update public.conflict_checks
  set outcome = p_outcome,
      outcome_reason = trim(p_reason),
      reviewed_by_staff_membership_id = v_staff_id,
      resolved_at = now()
  where id = p_conflict_check_id;

  if v_check.enquiry_id is not null then
    update public.enquiries
    set conflict_check_state = case
      when p_outcome in ('CLEAR','RESOLVED_CLEAR')
        then 'CONFLICT_CHECK_COMPLETED_BY_FIRM'::public.conflict_check_state
      else 'CONFLICT_CHECK_ESCALATED'::public.conflict_check_state
    end,
    updated_at = now()
    where id = v_check.enquiry_id
      and firm_id = v_check.firm_id;

    insert into public.audit_events (
      firm_id,
      enquiry_id,
      event_type,
      actor_auth_user_id,
      metadata
    ) values (
      v_check.firm_id,
      v_check.enquiry_id,
      'CONFLICT_CHECK_RESOLVED',
      auth.uid(),
      jsonb_build_object(
        'conflict_check_id', p_conflict_check_id,
        'outcome', p_outcome,
        'reason', trim(p_reason)
      )
    );
  end if;
end;
$$;

revoke all on function public.resolve_conflict_check(uuid, public.conflict_review_outcome, text) from public, anon;
grant execute on function public.resolve_conflict_check(uuid, public.conflict_review_outcome, text) to authenticated;

create or replace function public.convert_enquiry_to_matter(
  p_enquiry_reference text,
  p_conflict_check_id uuid,
  p_matter_title text default null,
  p_conversion_note text default null
)
returns table (matter_id uuid, matter_reference text, contact_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_enquiry public.enquiries%rowtype;
  v_check public.conflict_checks%rowtype;
  v_staff_id uuid;
  v_contact_id uuid;
  v_matter_id uuid;
  v_matter_ref text;
  v_existing public.enquiry_conversions%rowtype;
begin
  if not private.has_aal2() then
    raise exception 'MFA_REQUIRED' using errcode = '42501';
  end if;

  select * into v_enquiry
  from public.enquiries e
  where e.public_reference = p_enquiry_reference
  limit 1;

  if v_enquiry.id is null or not private.has_firm_access(v_enquiry.firm_id) then
    raise exception 'ENQUIRY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not private.has_firm_role(
    v_enquiry.firm_id,
    array['senior','manager','admin']::public.staff_role[]
  ) then
    raise exception 'INSUFFICIENT_ROLE' using errcode = '42501';
  end if;

  select * into v_existing
  from public.enquiry_conversions ec
  where ec.enquiry_id = v_enquiry.id
  limit 1;

  if v_existing.id is not null then
    return query
    select v_existing.matter_id, m.matter_reference, v_existing.contact_id
    from public.matters m
    where m.id = v_existing.matter_id;
    return;
  end if;

  select * into v_check
  from public.conflict_checks cc
  where cc.id = p_conflict_check_id
    and cc.enquiry_id = v_enquiry.id
    and cc.firm_id = v_enquiry.firm_id
  limit 1;

  if v_check.id is null then
    raise exception 'CONFLICT_CHECK_REQUIRED' using errcode = '22023';
  end if;

  if v_check.outcome not in (
    'CLEAR'::public.conflict_review_outcome,
    'RESOLVED_CLEAR'::public.conflict_review_outcome
  ) then
    raise exception 'CONFLICT_NOT_CLEARED' using errcode = '22023';
  end if;

  v_staff_id := private.current_staff_membership(v_enquiry.firm_id);

  insert into public.contacts (
    firm_id,
    kind,
    display_name,
    email,
    phone,
    created_by_auth_user_id
  ) values (
    v_enquiry.firm_id,
    'PERSON'::public.contact_kind,
    trim(v_enquiry.full_name),
    v_enquiry.email,
    v_enquiry.phone,
    auth.uid()
  )
  returning id into v_contact_id;

  v_matter_ref := 'BCF-' || to_char(now() at time zone 'Europe/London', 'YYYY') || '-' ||
                  upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.matters (
    firm_id,
    matter_reference,
    title,
    practice_area,
    category,
    status,
    engagement_state,
    source_enquiry_id,
    responsible_staff_membership_id,
    opened_at,
    created_by_auth_user_id
  ) values (
    v_enquiry.firm_id,
    v_matter_ref,
    coalesce(nullif(trim(p_matter_title), ''), trim(v_enquiry.full_name) || ' — ' || v_enquiry.category),
    'IMMIGRATION',
    v_enquiry.category,
    'OPEN'::public.matter_status,
    'NOT_SENT'::public.engagement_state,
    v_enquiry.id,
    v_staff_id,
    now(),
    auth.uid()
  )
  returning id into v_matter_id;

  insert into public.matter_contacts (
    firm_id,
    matter_id,
    contact_id,
    role,
    is_primary
  ) values (
    v_enquiry.firm_id,
    v_matter_id,
    v_contact_id,
    'CLIENT'::public.matter_contact_role,
    true
  );

  insert into public.enquiry_conversions (
    firm_id,
    enquiry_id,
    contact_id,
    matter_id,
    converted_by_staff_membership_id,
    conflict_check_id,
    conversion_note
  ) values (
    v_enquiry.firm_id,
    v_enquiry.id,
    v_contact_id,
    v_matter_id,
    v_staff_id,
    p_conflict_check_id,
    nullif(trim(coalesce(p_conversion_note,'')), '')
  );

  update public.enquiries
  set status = 'CLOSED'::public.enquiry_status,
      staff_action_at = coalesce(staff_action_at, now()),
      updated_at = now()
  where id = v_enquiry.id
    and firm_id = v_enquiry.firm_id;

  insert into public.audit_events (
    firm_id,
    enquiry_id,
    event_type,
    actor_auth_user_id,
    staff_action_at,
    metadata
  ) values (
    v_enquiry.firm_id,
    v_enquiry.id,
    'ENQUIRY_CONVERTED_TO_MATTER',
    auth.uid(),
    now(),
    jsonb_build_object(
      'matter_id', v_matter_id,
      'matter_reference', v_matter_ref,
      'contact_id', v_contact_id,
      'conflict_check_id', p_conflict_check_id
    )
  );

  return query select v_matter_id, v_matter_ref, v_contact_id;
end;
$$;

revoke all on function public.convert_enquiry_to_matter(text, uuid, text, text) from public, anon;
grant execute on function public.convert_enquiry_to_matter(text, uuid, text, text) to authenticated;
