# Customer Response Desk — fictional team trial
Date prepared: 17 October 2026 (Pacific/Auckland)

Public demo: https://adiai.si/customer-response-desk.html
Approved private pilot: https://adiai.si/customer-response-pilot
Walkthrough: https://adiai.si/customer-response-guide.html
Source: https://github.com/adityaspawade/customer-response-desk

## Aim and participants
Use two testers to check whether an enquiry can become a complaint, retain its history and reach a clear outcome. Tester A owns the case; tester B reviews the handover. Start in the public demo. For shared saving, use the private pilot with separately approved accounts. The owner creates each person's Auth account through Supabase and grants access through Team access. Each tester chooses their own password. Do not share an account password or send credentials in feedback.

Use fictional customers, messages and orders only. No real email sending is needed. This trial is prepared; it has not been run with an independent team.

## Suggested fictional record
Customer: Trial Customer
Contact: trial@example.invalid
Reference: TRIAL-001 (use another unique reference for another run)
Category: Enquiry
Subject: Delivery update
Summary: Customer asks when a fictional order will arrive.
Owner: Tester A
State: Needs action
Next action: Check the fictional courier update
Next due: choose tomorrow at 10:00 in the displayed local timezone

## Scenarios and expected outcomes
Record Pass / Fail / Not run and a short observation for each row.

| # | Action | Expected outcome | Result / observation |
|---|---|---|---|
| 1 | Add the suggested case. | Owner, next action and deadline are visible. | |
| 2 | Change Category to Complaint, remedy to Replacement, then Save changes. | Same case ID; initial enquiry and change remain in history. | |
| 3 | Add a Customer update note that the fictional item arrived damaged. | Note appears with its type in history. | |
| 4 | Save a reply draft. | Draft is retained; no email is sent. | |
| 5 | Set Waiting for team and enter a waiting reason; retain owner/action/deadline. | Waiting case has an explicit next check-in. | |
| 6 | Export Team handover for the case owner. | Workbook opens; Cases, Handover and History sheets match the selected open cases. | |
| 7 | In the private pilot, tester B signs in, refreshes and adds a handover note. Tester A refreshes. | Both see the saved note; earlier history remains. | |
| 8 | In the private pilot, both load the same case. A saves a note; B tries to save from the older version. | B sees a conflict; A's change remains. B refreshes before retrying. | |
| 9 | Resolve with a fictional outcome and completion confirmation. Include resolved cases in Today. | Case is resolved, history retained, no longer counted as open. | |
| 10 | Reopen with reason, owner, new action and future deadline. | Case returns to Needs action and preserves its resolution history. | |
| 11 | Import the sample workbook, then review it a second time. | First valid rows import; repeated nonblank references are skipped. | |
| 12 | On a phone, open the case, add a note and use navigation. | Text, fields and controls are usable; note saves in the pilot. | |

The public demo uses page memory and resets on reload. Cross-session saving and edit conflicts must be checked in the private pilot. Handover exports include open cases; select Include resolved cases in Today to find a resolved record.

## Feedback
- Device / browser / timezone:
- Scenario number:
- Expected behavior:
- What happened:
- Error text or screenshot (fictional data only):
- Severity: Blocked / Difficult / Cosmetic
- Was the owner and next action clear?:
- Was any information repeated unnecessarily?:
- What would stop your team using this?:

## Trial measurements
Measure these during the trial; do not present them as achieved benefits.
- Handover task: start/end time and whether tester B identified the next action correctly.
- Follow-up task: whether the tester found the deliberately overdue or unassigned case.
- Closure task: whether the outcome and customer communication were recorded.
- Compare against a similar fictional task in the team's current process if available.

## Exit criteria
All saving/access/history/conflict scenarios pass; no blocking issue remains; both testers can explain the next action from the handover. Record device/export findings separately. Before operational data, the owner agrees responsibilities, access approvals, retention, backups and incident handling.

## Scope
One team, 2,500 cases; manual refresh; Excel/CSV intake and Excel handovers. No automatic emails, scheduled reminders, attachments or self-signup. No operational impact claim is made from this fictional trial.
