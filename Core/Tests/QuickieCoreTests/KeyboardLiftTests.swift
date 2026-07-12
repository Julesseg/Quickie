import Foundation
import Testing
@testable import QuickieCore

// The bottom bar's **held** keyboard lift (issues #58 × #64): the App disables
// SwiftUI's automatic keyboard avoidance and drives the bar itself, so the bar
// must *follow the keyboard exactly* — rising in lockstep with the keyboard's
// own animation on appear, glued to the keyboard's top edge frame-by-frame
// during an interactive swipe-dismiss, and *holding* when a context menu
// transiently resigns first responder. `KeyboardLiftPolicy` is the pure
// decision; the App feeds it keyboard events and maps the returned motion to a
// concrete animation at the edge.
struct KeyboardLiftTests {

    @Test("a real keyboard's will-change lifts the bar to sit on the keyboard")
    func willChangeLiftsAboveKeyboard() {
        // A software keyboard overlapping 336pt of the screen, over a 34pt
        // home-indicator inset the bar already clears: the bar lifts by the
        // difference, so its bottom edge lands exactly on the keyboard's top.
        let policy = KeyboardLiftPolicy()
        let lift = policy.lift(
            forOverlap: 336,
            currentInset: 0,
            bottomSafeAreaInset: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        #expect(lift == KeyboardLift(inset: 302, motion: .keyboardSpring))
    }

    @Test("the keyboard spring is UIKit's own keyboard animation spring")
    func keyboardSpringMatchesUIKit() {
        // UIKit animates the software keyboard with a CASpringAnimation of
        // mass 3, stiffness 1000, damping 500 (the parameters behind the
        // notifications' private curve 7). The bar can only move in lockstep by
        // animating with exactly these values, so they are pinned here as the
        // single source the App edge maps `.keyboardSpring` from.
        #expect(KeyboardSpring.mass == 3)
        #expect(KeyboardSpring.stiffness == 1000)
        #expect(KeyboardSpring.damping == 500)
    }

    @Test("a hide while the list is still holds the lift (context menu)")
    func hideWhileStillHolds() {
        // A row's long-press context menu resigns first responder and drops the
        // keyboard — a system behaviour with no public override. The list isn't
        // being dragged, so this is *not* the intentional swipe-dismiss: hold
        // the inset (nil = no movement) so the layout stays frozen instead of
        // jerking the reversed result list downward (issue #58).
        let policy = KeyboardLiftPolicy()
        let lift = policy.lift(
            forOverlap: 0,
            currentInset: 302,
            bottomSafeAreaInset: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        #expect(lift == nil)
    }

    @Test("a hide while the list is dragging releases with the keyboard")
    func hideWhileScrollingReleases() {
        // A dismissal *while* scrolling is the intentional swipe (issue #64):
        // the finger has let go and the keyboard animates the rest of the way
        // off-screen, so the bar drops with it — on the keyboard's own spring,
        // not a mismatched curve that lands after the keyboard has settled.
        let policy = KeyboardLiftPolicy()
        let lift = policy.lift(
            forOverlap: 0,
            currentInset: 302,
            bottomSafeAreaInset: 34,
            isListScrolling: true,
            usesKeyboardlessControl: false
        )
        #expect(lift == KeyboardLift(inset: 0, motion: .keyboardSpring))
    }

    @Test("a hide that finds the bar already part-way down still releases")
    func hideAfterPartialTrackingReleases() {
        // The end of a swipe-dismiss is a race: the finger lifts, the scroll
        // phase can go idle, and only then does the settle will-change fire.
        // The bar sitting *below* the lift threshold is proof an interactive
        // dismiss was already tracking it down (a context-menu hold never
        // lowers it), so this hide must finish the release — freezing here
        // would strand the bar mid-air above a dead band.
        let policy = KeyboardLiftPolicy()
        let lift = policy.lift(
            forOverlap: 0,
            currentInset: 80,
            bottomSafeAreaInset: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        #expect(lift == KeyboardLift(inset: 0, motion: .keyboardSpring))
    }

    @Test("a drag sample glues the bar to the keyboard's live top edge")
    func dragSampleTracksDirectly() {
        // The heart of the fix: during an interactive swipe-dismiss the
        // keyboard's frame follows the finger, and no will-change notification
        // fires until the gesture ends — so the bar must follow the sampled
        // frame per-frame, applied *directly* (the finger is the animation; any
        // curve here would trail it). Half-dismissed at 180pt of overlap, the
        // bar sits exactly on the keyboard's top edge.
        let policy = KeyboardLiftPolicy()
        let lift = policy.tracking(
            forOverlap: 180,
            currentInset: 302,
            bottomSafeAreaInset: 34,
            isListScrolling: true,
            usesKeyboardlessControl: false
        )
        #expect(lift == KeyboardLift(inset: 146, motion: .direct))
    }

    @Test("a low sample while the list is still holds, like a will-change hide")
    func lowSampleWhileStillHolds() {
        // The tracker's layout passes also fire when the keyboard leaves for a
        // context menu's resign. A sample that reads "keyboard gone" while the
        // list is still must obey the same hold rule as a will-change hide
        // (issue #58) — otherwise the tracking path would un-freeze the layout
        // the hold exists to protect.
        let policy = KeyboardLiftPolicy()
        let lift = policy.tracking(
            forOverlap: 0,
            currentInset: 302,
            bottomSafeAreaInset: 34,
            isListScrolling: false,
            usesKeyboardlessControl: false
        )
        #expect(lift == nil)
    }

    @Test("a hide during a keyboard-less capture step releases the lift")
    func hideDuringKeyboardlessControlReleases() {
        // A capture step with no text field (the date picker + commit button,
        // the primer/denial affordances) removes the keyboard structurally, so
        // the control takes the keyboard's space rather than floating above a
        // dead band — released on the keyboard's spring, in step with it.
        let policy = KeyboardLiftPolicy()
        let lift = policy.lift(
            forOverlap: 0,
            currentInset: 302,
            bottomSafeAreaInset: 34,
            isListScrolling: false,
            usesKeyboardlessControl: true
        )
        #expect(lift == KeyboardLift(inset: 0, motion: .keyboardSpring))
    }
}
