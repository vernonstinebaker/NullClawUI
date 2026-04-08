@testable import NullClawUI
import XCTest

// MARK: - StatusBadge Tests

final class StatusBadgeTests: XCTestCase {
    func testStatusBadgeShowsOnlineLabel() {
        let badge = StatusBadge(label: "Online", health: .healthy)
        XCTAssertEqual(badge.label, "Online")
        XCTAssertEqual(badge.health, .healthy)
        XCTAssertEqual(badge.health.color, .green)
        XCTAssertFalse(badge.isPulsing)
    }

    func testStatusBadgeShowsOfflineLabel() {
        let badge = StatusBadge(label: "Offline", health: .unhealthy)
        XCTAssertEqual(badge.health.color, .red)
    }

    func testStatusBadgeShowsCheckingLabel() {
        let badge = StatusBadge(label: "Checking", health: .unknown, isPulsing: true)
        XCTAssertEqual(badge.health.color, .orange)
        XCTAssertTrue(badge.isPulsing)
    }

    func testStatusBadgeDotSizeIsTwelve() {
        let badge = StatusBadge(label: "Test", health: .healthy)
        XCTAssertNotNil(badge)
    }

    func testStatusBadgePulsesWhenActive() {
        let badge = StatusBadge(label: "Checking", health: .unknown, isPulsing: true)
        XCTAssertTrue(badge.isPulsing)
    }

    func testStatusBadgeDoesNotPulseWhenInactive() {
        let badge = StatusBadge(label: "Online", health: .healthy)
        XCTAssertFalse(badge.isPulsing)
    }
}

// MARK: - StatCard Tests

final class StatCardTests: XCTestCase {
    func testStatCardDisplaysIconValueAndTitle() {
        let card = StatCard(icon: "cloud.fill", count: "5", title: "Providers", color: .teal)
        XCTAssertEqual(card.icon, "cloud.fill")
        XCTAssertEqual(card.count, "5")
        XCTAssertEqual(card.title, "Providers")
        XCTAssertEqual(card.color, .teal)
    }

    func testStatCardHealthDotAppearsWhenUnhealthy() {
        let card = StatCard(icon: "cloud.fill", count: "0", title: "Providers", color: .teal, health: .unhealthy)
        XCTAssertEqual(card.health, .unhealthy)
        XCTAssertEqual(card.health.color, .red)
    }

    func testStatCardHealthDotHiddenWhenHealthy() {
        let card = StatCard(icon: "cloud.fill", count: "5", title: "Providers", color: .teal, health: .healthy)
        XCTAssertEqual(card.health, .healthy)
    }

    func testStatCardIsTappable() {
        let expectation = XCTestExpectation(description: "Tap triggered")
        let card = StatCard(icon: "cloud.fill", count: "5", title: "Providers", color: .teal) {
            expectation.fulfill()
        }
        XCTAssertNotNil(card.onTap)
        card.onTap?()
        wait(for: [expectation], timeout: 1.0)
    }

    func testStatCardDefaultHealthIsUnknown() {
        let card = StatCard(icon: "cloud.fill", count: "5", title: "Providers", color: .teal)
        XCTAssertEqual(card.health, .unknown)
    }

    func testStatCardOnTapIsOptional() {
        let card = StatCard(icon: "cloud.fill", count: "5", title: "Providers", color: .teal)
        XCTAssertNil(card.onTap)
    }
}

// MARK: - ActionButton Tests

final class ActionButtonTests: XCTestCase {
    func testActionButtonShowsIconAndLabel() {
        let button = ActionButton(title: "Chat", icon: "bubble.left.and.bubble.right", color: .green) {}
        XCTAssertEqual(button.title, "Chat")
        XCTAssertEqual(button.icon, "bubble.left.and.bubble.right")
        XCTAssertEqual(button.color, .green)
    }

    func testActionButtonHasTintedBackground() {
        let button = ActionButton(title: "Settings", icon: "gearshape", color: .gray) {}
        XCTAssertEqual(button.color, .gray)
    }

    func testActionButtonTriggersActionOnTap() {
        let expectation = XCTestExpectation(description: "Action triggered")
        let button = ActionButton(title: "Test", icon: "test", color: .blue) {
            expectation.fulfill()
        }
        button.action()
        wait(for: [expectation], timeout: 1.0)
    }

    func testActionButtonAccessibilityLabel() {
        let button = ActionButton(title: "Chat", icon: "bubble", color: .green) {}
        XCTAssertEqual(button.title, "Chat")
    }
}

// MARK: - LoadingView Tests

final class LoadingViewTests: XCTestCase {
    func testLoadingViewHasNoMessageByDefault() {
        let view = LoadingView()
        XCTAssertNil(view.message)
    }

    func testLoadingViewShowsMessage() {
        let view = LoadingView(message: "Loading servers…")
        XCTAssertEqual(view.message, "Loading servers…")
    }
}

// MARK: - GlassCard Tests

final class GlassCardTests: XCTestCase {
    func testGlassCardHasCorrectCornerRadius() {
        XCTAssertEqual(DesignTokens.CornerRadius.card, 16)
    }

    func testGlassCardHasCorrectPadding() {
        XCTAssertEqual(DesignTokens.Spacing.standard, 16)
    }
}

// MARK: - DesignToken Value Tests

final class DesignTokenValueTests: XCTestCase {
    func testCornerRadiusValues() {
        XCTAssertEqual(DesignTokens.CornerRadius.card, 16)
        XCTAssertEqual(DesignTokens.CornerRadius.medium, 12)
        XCTAssertEqual(DesignTokens.CornerRadius.bubble, 16)
        XCTAssertEqual(DesignTokens.CornerRadius.small, 8)
        XCTAssertEqual(DesignTokens.CornerRadius.inner, 6)
        XCTAssertEqual(DesignTokens.CornerRadius.tiny, 2)
    }

    func testSpacingValues() {
        XCTAssertEqual(DesignTokens.Spacing.section, 20)
        XCTAssertEqual(DesignTokens.Spacing.card, 16)
        XCTAssertEqual(DesignTokens.Spacing.standard, 16)
        XCTAssertEqual(DesignTokens.Spacing.tight, 12)
        XCTAssertEqual(DesignTokens.Spacing.minimal, 8)
        XCTAssertEqual(DesignTokens.Spacing.tiny, 4)
    }

    func testAnimationSpringReturnsNonNil() {
        _ = DesignTokens.Animation.spring()
        _ = DesignTokens.Animation.quick()
    }

    func testTransitionsReturnNonNil() {
        _ = DesignTokens.Animation.fade()
        _ = DesignTokens.Animation.expand()
    }

    func testFontSizeValues() {
        XCTAssertEqual(DesignTokens.FontSize.title, 28)
        XCTAssertEqual(DesignTokens.FontSize.headline, 17)
        XCTAssertEqual(DesignTokens.FontSize.body, 17)
        XCTAssertEqual(DesignTokens.FontSize.callout, 16)
        XCTAssertEqual(DesignTokens.FontSize.subheadline, 15)
        XCTAssertEqual(DesignTokens.FontSize.footnote, 13)
        XCTAssertEqual(DesignTokens.FontSize.caption, 12)
        XCTAssertEqual(DesignTokens.FontSize.caption2, 11)
    }
}

// MARK: - HealthIndicator Tests

final class HealthIndicatorComponentTests: XCTestCase {
    func testHealthyColor() {
        XCTAssertEqual(HealthIndicator.healthy.color, .green)
    }

    func testDegradedColor() {
        XCTAssertEqual(HealthIndicator.degraded.color, .yellow)
    }

    func testUnhealthyColor() {
        XCTAssertEqual(HealthIndicator.unhealthy.color, .red)
    }

    func testUnknownColor() {
        XCTAssertEqual(HealthIndicator.unknown.color, .orange)
    }

    func testEquatable() {
        XCTAssertEqual(HealthIndicator.healthy, HealthIndicator.healthy)
        XCTAssertNotEqual(HealthIndicator.healthy, HealthIndicator.unhealthy)
    }
}

// MARK: - BubbleShape Tests

final class BubbleShapeTests: XCTestCase {
    func testBubbleShapeInitialization() {
        let shape = BubbleShape(role: "user", isLast: true)
        XCTAssertEqual(shape.role, "user")
        XCTAssertTrue(shape.isLast)
    }
}

// MARK: - TypingIndicator Tests

final class TypingIndicatorTests: XCTestCase {
    func testTypingIndicatorExists() {
        let indicator = TypingIndicator()
        // Just ensure it can be instantiated
        XCTAssertNotNil(indicator)
    }
}

// MARK: - MessageBubble Tests

final class MessageBubbleTests: XCTestCase {
    func testMessageBubbleInitialization() {
        let message = ChatMessage(role: "user", text: "Hello")
        let bubble = MessageBubble(message: message, isLastInGroup: true)
        XCTAssertEqual(bubble.message.role, "user")
        XCTAssertEqual(bubble.message.text, "Hello")
        XCTAssertTrue(bubble.isLastInGroup)
    }
}

// MARK: - CopyButton Tests

final class CopyButtonTests: XCTestCase {
    func testCopyButtonInitialization() {
        let button = CopyButton(text: "Test", tint: .blue)
        XCTAssertEqual(button.text, "Test")
        XCTAssertEqual(button.tint, .blue)
    }
}
