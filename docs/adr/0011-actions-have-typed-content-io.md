# Actions declare typed input/output content (composability from day one)

Quickie will eventually grow a native **Workflow** system (user-composed Action chains). We are not building it in v1, but we make one architectural commitment now so it stays possible: **every Action declares its input content type(s) and its output content type.** An Action consumes content of known types and produces content of a known type (Fallbacks consume text; a file result produces a file; the calculator produces a number/text).

Making this uniform from the start is what lets a future Workflow chain Actions — one Action's output becomes eligible, type-validated input for the next. We build the *types* now; the *chaining UI* comes later. It also powers the present-day behavior: content type drives which Actions are eligible and how they rank, and which secondary actions a result exposes.

**v1 scripting stance:** no native scripting language. "Custom/advanced actions" are served by **Shortcut Actions** (x-callback with input/output — the interim escape hatch) and **Quicklink templates** (parameterized URLs). The eventual native Workflow is aimed at **visual step-chaining** (mirroring the breadcrumb multi-step UI), not a text DSL, with Shortcuts remaining the power-user escape hatch.
