import Foundation
import Testing
@testable import QuickieCore

// A Custom Action is a user-authored URL template whose `{name}` slots become the
// breadcrumb's ordered, typed Arguments; the final commit percent-encodes each
// value into its slot(s) and opens the URL (CONTEXT.md → Custom Action; ADR 0021).
// The `fallbackQuery` kind is absorbed wholesale into this concept. These tests
// pin the new definition type's token detection and the Action it factories,
// exercised at the existing `Action` → `MultiStepAction.commit(...)` → `ActionOutcome`
// seam so a text-only template runs end to end.
struct CustomActionTests {

    // MARK: - Token detection (the new seam)

    @Test("tokens are detected in URL-appearance order")
    func tokensInAppearanceOrder() {
        let def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        )
        #expect(def.tokenNames == ["title", "notes"])
    }

    @Test("the same token name twice collapses to one slot")
    func duplicateNameCollapses() {
        // One Argument fills every occurrence of a repeated name (ADR 0021).
        let def = CustomActionDefinition(
            name: "Echo",
            template: "https://x.com/{q}?also={q}"
        )
        #expect(def.tokenNames == ["q"])
    }

    @Test("numeric token names like {1} are accepted")
    func numericNamesAccepted() {
        let def = CustomActionDefinition(
            name: "Numbered",
            template: "https://x.com/{1}/{2}"
        )
        #expect(def.tokenNames == ["1", "2"])
    }

    @Test("an empty brace pair is not a token")
    func emptyBraceIsNotAToken() {
        let def = CustomActionDefinition(name: "Empty", template: "https://x.com/{}")
        #expect(def.tokenNames.isEmpty)
    }

    // MARK: - The factory (a standard Action driving MultiStepAction)

    @Test("the factory builds one text Argument per slot, in URL-appearance order")
    func factoryBuildsTextArguments() {
        let def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        )
        let action = def.makeAction(id: "things")
        #expect(action != nil)
        #expect(action?.kind == .customAction)
        #expect(action?.title == "Add to Things")
        #expect(action?.inputTypes == [.text])
        #expect(action?.outputType == .url)
        #expect(action?.arguments.map(\.label) == ["title", "notes"])
        #expect(action?.arguments.allSatisfy { $0.contentType == .text } == true)
    }

    @Test("a slot-less template factories a static (link) Custom Action, not a breadcrumb (ADR 0030)")
    func noSlotMakesStaticLink() {
        let def = CustomActionDefinition(name: "Static", template: "https://x.com")
        let action = def.makeAction(id: "x")
        // A static (slot-less) Custom Action: opens directly, wears the link glyph,
        // carries no Arguments, and is not fallback-eligible.
        #expect(action?.kind == .quicklink)
        #expect(action?.arguments.isEmpty == true)
        #expect(action?.inputTypes.isEmpty == true)
        #expect(action?.isFallbackEligible == false)
        #expect(action?.content == .quicklink(id: "x"))
        #expect(action?.run() == .openURL(URL(string: "https://x.com")!))
    }

    // MARK: - Slot filling through the breadcrumb (Action → MultiStepAction → outcome)

    /// A one-slot Custom Action, the shape web search seeds as.
    private func oneSlot(_ template: String = "https://x.com/search?q={q}") -> Action {
        CustomActionDefinition(name: "Search", template: template).makeAction(id: "one")!
    }

    @Test("the App Store search seed template opens the itms-apps MZSearch results")
    func appStoreSearchTemplateOpensResults() {
        // App Store Search is a default-seeded Custom Action (issue #144), not a
        // System built-in: its slotted `itms-apps` URL runs through the same fill
        // path as web search. Verify the non-web scheme survives and the term lands
        // percent-encoded — the whole reason it fits the Custom Action model.
        let template = "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term={query}"
        let action = CustomActionDefinition(name: "Search the App Store", template: template).makeAction(id: "seed.app-store-search")!
        #expect(action.isFallbackEligible)

        var run = MultiStepAction(action: action)
        #expect(run.commit(.text("threes 3"))
                == .completed(.openURL(URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=threes%203")!)))
    }

    @Test("filling percent-encodes the value, escaping structural query delimiters")
    func fillPercentEncodes() {
        // Spaces and unicode are percent-encoded. The **structural** query delimiters
        // are escaped per-value so a value can't break out of its slot into a
        // multi-slot template: `&` → `%26` (else it would start a new parameter). `$`
        // and other query-legal characters stay unescaped, so "$5 menu" keeps its
        // "$5" (a regex replacement would have read it as a capture ref).
        var space = MultiStepAction(action: oneSlot())
        #expect(space.commit(.text("swift testing"))
                == .completed(.openURL(URL(string: "https://x.com/search?q=swift%20testing")!)))

        var amp = MultiStepAction(action: oneSlot())
        #expect(amp.commit(.text("cats & dogs"))
                == .completed(.openURL(URL(string: "https://x.com/search?q=cats%20%26%20dogs")!)))

        var unicode = MultiStepAction(action: oneSlot())
        #expect(unicode.commit(.text("café"))
                == .completed(.openURL(URL(string: "https://x.com/search?q=caf%C3%A9")!)))

        var dollar = MultiStepAction(action: oneSlot())
        #expect(dollar.commit(.text("$5 menu"))
                == .completed(.openURL(URL(string: "https://x.com/search?q=$5%20menu")!)))
    }

    @Test("an ampersand in one slot can't leak into the next slot")
    func ampersandStaysInItsSlot() {
        // The multi-slot regression the escaping guards against (PR #99 review): a
        // title of "Milk & eggs" must not have its `&` read as a parameter separator
        // that truncates the title and injects a bogus param ahead of notes.
        let action = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        ).makeAction(id: "things")!
        var session = MultiStepAction(action: action)
        _ = session.commit(.text("Milk & eggs"))
        #expect(session.commit(.text("for the week"))
                == .completed(.openURL(URL(string: "things:///add?title=Milk%20%26%20eggs&notes=for%20the%20week")!)))
    }

    @Test("a duplicated token fans one Argument out to every occurrence")
    func duplicateTokenFansOut() {
        let action = CustomActionDefinition(
            name: "Echo",
            template: "https://x.com/{q}?also={q}"
        ).makeAction(id: "echo")!
        #expect(action.arguments.count == 1)
        var session = MultiStepAction(action: action)
        #expect(session.commit(.text("hi there"))
                == .completed(.openURL(URL(string: "https://x.com/hi%20there?also=hi%20there")!)))
    }

    @Test("seed-and-commit: a one-Argument fallback completes immediately")
    func seedAndCommitSingleArgumentCompletes() {
        // Selecting a fallback commits the typed query as Argument 1 (CONTEXT.md →
        // Fallback Action); a single-Argument fallback finishes in one tap.
        let action = CustomActionDefinition(
            name: "Search the web",
            template: "https://duckduckgo.com/?q={query}"
        ).makeAction(id: "web")!
        var session = MultiStepAction(action: action)
        #expect(session.commit(.text("swift"))
                == .completed(.openURL(URL(string: "https://duckduckgo.com/?q=swift")!)))
    }

    @Test("seed-and-commit: a multi-Argument fallback continues at step 2, pill 1 sealed")
    func seedAndCommitMultiArgumentContinues() {
        let action = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        ).makeAction(id: "things")!
        var session = MultiStepAction(action: action)

        // The seed commit seals the first pill and moves to step 2 rather than
        // finishing (multi-Argument).
        #expect(session.commit(.text("buy milk")) == .collecting)
        #expect(session.pills == [.text("buy milk")])
        #expect(session.current == action.arguments[1]) // now collecting "notes"

        // The second commit completes with the fully-formed URL.
        #expect(session.commit(.text("2%"))
                == .completed(.openURL(URL(string: "things:///add?title=buy%20milk&notes=2%25")!)))
    }

    @Test("the fallback-seeded first pill is re-editable mid-capture")
    func fallbackSeededFirstPillReeditable() {
        let action = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        ).makeAction(id: "things")!
        var session = MultiStepAction(action: action)
        _ = session.commit(.text("buy milk")) // seed pill 1, now on "notes"

        // Tap the seeded first pill and fix it — the later cursor returns to the
        // first unfilled step, the fix applied.
        session.editPill(at: 0)
        #expect(session.current == action.arguments[0])
        #expect(session.commit(.text("buy oat milk")) == .collecting)
        #expect(session.pills == [.text("buy oat milk")])
        #expect(session.current == action.arguments[1])

        #expect(session.commit(.text("for the week"))
                == .completed(.openURL(URL(string: "things:///add?title=buy%20oat%20milk&notes=for%20the%20week")!)))
    }

    @Test("a text-first (fallback-eligible) Custom Action reads as .search regardless of slot count")
    func eligibleReturnKeyIsSearch() {
        // Eligibility is derived from shape now (issue #114): a text-first Custom
        // Action whose commit opens a URL reads `.search` (web search's behaviour) —
        // for the one-slot web-search case *and* a multi-slot one, since the label
        // comes from free-text-first eligibility + openURL fill, not the slot count or
        // any activation state.
        let oneSlot = CustomActionDefinition(
            name: "Search the web", template: "https://x.com/?q={q}"
        ).makeAction(id: "one")!
        #expect(oneSlot.returnKeyLabel == .search)

        let multiSlot = CustomActionDefinition(
            name: "Add to Things", template: "things:///add?title={title}&notes={notes}"
        ).makeAction(id: "multi")!
        #expect(multiSlot.returnKeyLabel == .search)

        // A Custom Action whose first slot isn't free text is not eligible, so it
        // begins its breadcrumb on Enter and reads `.go`, not `.search`.
        let dateFirst = CustomActionDefinition(
            name: "Log at", template: "app://log?when={when}&note={note}",
            argumentSpecs: ["when": ArgumentSpec(type: .date)]
        ).makeAction(id: "verb")!
        #expect(dateFirst.returnKeyLabel == .go)
    }

    @Test("the breadcrumb asks in fill order while each value fills its own URL slot")
    func fillOrderDrivesAskingOrderNotURLOrder() {
        // The flagship case (ADR 0021): the URL puts title before notes, but the user
        // dragged notes to ask first. The breadcrumb asks notes then title, yet each
        // value still fills its own token's URL position — asking order and URL
        // position are decoupled.
        var def = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        )
        def.moveArguments(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let action = def.makeAction(id: "things")!
        #expect(action.arguments.map(\.label) == ["notes", "title"])

        var session = MultiStepAction(action: action)
        // First pill is notes (fill order), second is title.
        #expect(session.commit(.text("call the bank")) == .collecting)
        #expect(session.commit(.text("Errands"))
                == .completed(.openURL(URL(string: "things:///add?title=Errands&notes=call%20the%20bank")!)))
    }

    @Test("verb-first collects every Argument from an empty breadcrumb")
    func verbFirstCollectsEveryArgument() {
        // Verb-first entry starts the breadcrumb empty at Argument 1 (CONTEXT.md →
        // Custom Action), regardless of the fallback flag — here a non-fallback one.
        let action = CustomActionDefinition(
            name: "Add to Things",
            template: "things:///add?title={title}&notes={notes}"
        ).makeAction(id: "things")!
        var session = MultiStepAction(action: action)
        #expect(session.pills.isEmpty)
        #expect(session.current == action.arguments[0])

        #expect(session.commit(.text("Plan trip")) == .collecting)
        #expect(session.commit(.text("book flights"))
                == .completed(.openURL(URL(string: "things:///add?title=Plan%20trip&notes=book%20flights")!)))
    }
}
