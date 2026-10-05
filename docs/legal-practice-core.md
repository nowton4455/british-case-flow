# British Case Flow — Legal Practice Core

This document defines the production direction for British Case Flow after reviewing the strongest patterns in Coil, rhorba/LawFirm, LexNebulis, Canary CMS and OpenLawFirm.

## Product boundary

British Case Flow is legal intake and matter-opening workflow software for regulated UK immigration firms. It is not an immigration adviser, a legal deadline calculator, or a substitute for solicitor review.

The system may:
- collect structured enquiry facts;
- apply firm-configured operational triage rules;
- flag urgency for staff attention;
- support conflict checking;
- record client/matter-opening decisions;
- create tasks and audit events.

The system must not:
- tell a prospect what their legal deadline is;
- determine immigration eligibility;
- automatically clear a conflict;
- create a solicitor-client relationship merely because an enquiry is submitted;
- convert an enquiry into an open matter without an authorised staff action.

## Architecture principles borrowed as patterns

No source code from AGPL or commercially restricted repositories is copied here.

- Coil: intake -> review -> conflict preview -> contact/matter conversion.
- rhorba/LawFirm: granular role separation, explicit conflict-check clearance and audit history.
- LexNebulis: immutable-style audit mindset, strong tenant/security boundaries.
- Canary CMS: matter-centric operational UX and separation of contacts, matters, tasks and documents.
- OpenLawFirm: modular domain boundaries around matters, conflicts and future portal integrations.

## Canonical workflow

1. Prospect submits a public enquiry.
2. Server persists the immutable intake snapshot and authoritative routing result.
3. Staff review the enquiry under MFA.
4. Staff performs a conflict check using names/entities supplied in the enquiry plus any manually added search terms.
5. Conflict check is explicitly marked:
   - pending;
   - clear;
   - potential conflict;
   - escalated;
   - resolved with recorded reason.
6. Only authorised staff may convert the enquiry.
7. Conversion creates/reuses:
   - a contact;
   - a matter;
   - matter-contact/party links;
   - an enquiry-to-matter conversion record.
8. The matter then becomes the operational record for tasks, notes, documents, communications and later billing/portal features.
9. Every material action is audit logged.

## UK legal-practice safeguards

- "Conflict clear" is always a human decision.
- The intake acknowledgement and matter-opening screens must continue to state that submission does not mean the firm has agreed to act.
- A matter should have a separate engagement state. Opening an internal matter record does not itself prove retainer/engagement.
- Critical dates entered by prospects are facts supplied by the prospect. They are not system-calculated legal deadlines.
- Any future deadline engine must be a distinct reviewed feature with jurisdiction/rule versioning and explicit lawyer confirmation.
- Sensitive free text should be minimised before conflicts are checked.
- Access remains tenant scoped and MFA gated.
- Staff role changes, conflict decisions, matter opening, priority overrides and record access should remain auditable.

## Core entities introduced

### contacts
People or organisations known to the firm.

### contact_aliases
Previous names, trading names and other aliases used for conflict searching.

### matters
Internal legal matters. A matter can originate from an enquiry but can also be created independently later.

### matter_contacts
Typed relationship between a matter and a contact, e.g. client, spouse/partner, sponsor/employer, opposing party, other related party.

### conflict_checks
A recorded human-controlled conflict-search event.

### conflict_check_terms
Exact search terms used for the check.

### conflict_check_hits
Candidate matches found/reviewed. A hit is not automatically a conflict.

### enquiry_conversions
Immutable bridge recording who converted an enquiry into a contact/matter and when.

### matter_tasks
Operational tasks with due dates and ownership. Due dates here are workflow dates unless explicitly confirmed as legal deadlines by an authorised user.

### matter_notes
Internal factual notes, with future support for privilege/confidentiality classification.

## Role model

Existing roles remain:
- staff
- senior
- manager
- admin

Recommended permissions:
- staff: review enquiries, run conflict searches, add factual notes/tasks.
- senior: staff permissions plus priority decreases and potential-conflict resolution.
- manager: senior permissions plus matter opening/closure policy and staff oversight.
- admin: system/tenant administration and staff access.

The database should enforce sensitive transitions through RPCs rather than trusting client-side role checks.

## Matter lifecycle

Suggested statuses:
- PROSPECT_REVIEW
- CONFLICT_REVIEW
- READY_TO_OPEN
- OPEN
- ON_HOLD
- CLOSING
- CLOSED
- DECLINED

Suggested engagement states:
- NOT_SENT
- SENT
- SIGNED
- DECLINED
- NOT_REQUIRED

Matter lifecycle and engagement state are deliberately separate.

## Next implementation sequence

1. Apply legal-practice-core migration.
2. Add conflict-check server functions and UI.
3. Add explicit "Convert to matter" RPC with idempotency.
4. Add matter list/detail routes.
5. Add tasks and notes.
6. Add engagement state and document storage.
7. Add client portal only after authorisation model and document permissions are complete.
8. Add billing only after matter/accounting boundaries are separately reviewed.

## Licence rule

Treat AGPL and commercially restricted projects as product/workflow references only. Direct reusable implementation should come from our own code or permissively licensed sources (MIT/Apache-2.0) after reviewing attribution requirements.
