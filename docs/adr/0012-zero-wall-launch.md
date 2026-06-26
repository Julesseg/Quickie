# Zero-wall launch and just-in-time permissions

Quickie's core promise is instant, focused input the moment the app opens. To protect it, **nothing blocks the input field** — not onboarding, not permission prompts.

- **First launch opens straight to the focused input**, keyboard up. No mandatory onboarding carousel, no upfront permission requests.
- **Permissions are requested just-in-time**, at the first moment each is needed (EventKit when first creating a reminder; the document picker when first adding an Indexed Folder), each preceded by a **one-line custom primer** so the system dialog isn't wasted on an uninformed denial.
- **Graceful degradation, never nag.** A denied permission turns the affected Action into an inline "Enable in Settings" affordance; everything else keeps working.
- **iCloud is optional** — no iCloud / sync off means a fully functional local app; sync resumes silently when available and is never surfaced as an error.
- **Onboarding, if any, is a dismissible tip layer** (e.g. a Home tips card), never a gate.

Recorded as a standing principle because the obvious instinct — add a welcome flow, request permissions up front "to be safe" — directly violates the product's reason to exist.
