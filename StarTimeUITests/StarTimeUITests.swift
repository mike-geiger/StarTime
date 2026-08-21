//
//  StarTimeUITests.swift
//  StarTimeUITests
//
//  Created by Michael Geiger on 7/9/26.
//

import XCTest

final class StarTimeUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // A previous test in the suite (e.g. the default launch tests) can
        // leave the simulator in landscape orientation, which makes SwiftUI's
        // lazy List render fewer rows into the accessibility tree — force
        // portrait so our element queries see everything they expect.
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testStage1SignUpAndCreateHousehold() throws {
        let app = XCUIApplication()
        app.launch()

        resetToSignedOutState(app: app)

        let uniqueEmail = "test-\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "TestPassword123!"

        add(XCTAttachment(screenshot: app.screenshot()))

        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10), "Sign-in screen should appear on launch")
        signUp(app: app, email: uniqueEmail, password: password)

        let createHouseholdButton = app.buttons["Create a household"]
        XCTAssertTrue(createHouseholdButton.waitForExistence(timeout: 15), "Should reach household setup after sign-up")
        add(XCTAttachment(screenshot: app.screenshot()))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        createHouseholdButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Dad")

        let householdNameField = app.textFields["Household name (e.g. \"The Geigers\")"]
        householdNameField.tap()
        householdNameField.typeText("The Geigers")

        app.buttons["Create"].tap()

        let choresTab = app.tabBars.buttons["Chores"]
        XCTAssertTrue(choresTab.waitForExistence(timeout: 15), "Should land on the main tab view after creating a household")

        tapTab(app, "Settings")

        let householdTitle = app.staticTexts["The Geigers"]
        XCTAssertTrue(householdTitle.waitForExistence(timeout: 10), "Settings should show household name")
        add(XCTAttachment(screenshot: app.screenshot()))

        XCTAssertTrue(app.staticTexts["Dad (You)"].exists, "Member list should show the creator")
        XCTAssertTrue(app.buttons["Invite a parent"].exists)
        XCTAssertTrue(app.buttons["Invite a child"].exists)

        // Clean up: Dad is the household's only member, so this cascades
        // into deleting the whole test household along with the account.
        deleteCurrentAccount(app: app)
    }

    @MainActor
    func testStage2InviteChildAndAssignChore() throws {
        let app = XCUIApplication()
        app.launch()

        resetToSignedOutState(app: app)

        let runId = Int(Date().timeIntervalSince1970)
        let parentEmail = "parent-\(runId)@example.com"
        let childEmail = "child-\(runId)@example.com"
        let password = "TestPassword123!"

        // --- Sign up as the parent and create a household ---
        signUp(app: app, email: parentEmail, password: password)

        let createHouseholdButton = app.buttons["Create a household"]
        XCTAssertTrue(createHouseholdButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        createHouseholdButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5), "Should reach the create-household form")
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Dad")
        app.textFields["Household name (e.g. \"The Geigers\")"].tap()
        app.textFields["Household name (e.g. \"The Geigers\")"].typeText("The Geigers")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")

        // --- Generate a child invite code ---
        app.buttons["Invite a child"].tap()
        let codeText = app.staticTexts.matching(identifier: "generatedInviteCode").firstMatch
        XCTAssertTrue(codeText.waitForExistence(timeout: 10), "Invite code should appear")
        let inviteCode = codeText.label
        XCTAssertEqual(inviteCode.count, 6, "Invite code should be 6 characters")

        app.buttons["Sign Out"].tap()

        // --- Sign up as the child and join with the code ---
        signUp(app: app, email: childEmail, password: password)

        let joinButton = app.buttons["Join with an invite code"]
        XCTAssertTrue(joinButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        joinButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5), "Should reach the join-household form")
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Kiddo")
        app.textFields["Invite code"].tap()
        app.textFields["Invite code"].typeText(inviteCode)
        app.buttons["Join"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15), "Child should land on the main tab view after joining")
        tapTab(app, "Settings")
        XCTAssertTrue(app.staticTexts["Kiddo (You)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Child"].exists, "Kiddo should show up with the Child role")

        app.buttons["Sign Out"].tap()

        // --- Sign back in as the parent to create and assign a chore ---
        signIn(app: app, email: parentEmail, password: password)

        tapTab(app, "Chores")

        tapAddButton(app: app)
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
        app.textFields["Title"].tap()
        app.textFields["Title"].typeText("Make bed")
        app.buttons["Save"].tap()

        let choreRow = app.staticTexts["Make bed"]
        XCTAssertTrue(choreRow.waitForExistence(timeout: 10), "New chore should appear in the parent's chores list")
        add(XCTAttachment(screenshot: app.screenshot()))

        // Complete it, then confirm the Progress tab reflects the streak and chart.
        let completeButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'completeChoreButton-'")).firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        tapTab(app, "Progress")
        XCTAssertTrue(app.staticTexts["Make bed"].waitForExistence(timeout: 10), "Progress tab should list the assigned chore")
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 5), "Streak should show 1 after today's completion")
        let progressScreenshot = XCTAttachment(screenshot: app.screenshot())
        progressScreenshot.lifetime = .keepAlways
        add(progressScreenshot)

        // Clean up both accounts. Deleting Dad first just removes him from
        // the household (Kiddo is still a member); deleting Kiddo second —
        // now the last member — cascades into deleting the whole household.
        deleteCurrentAccount(app: app)
        signIn(app: app, email: childEmail, password: password)
        deleteCurrentAccount(app: app)
    }

    @MainActor
    func testStage3EarnAndRedeemReward() throws {
        let app = XCUIApplication()
        app.launch()

        resetToSignedOutState(app: app)

        let runId = Int(Date().timeIntervalSince1970)
        let parentEmail = "parent3-\(runId)@example.com"
        let childEmail = "child3-\(runId)@example.com"
        let password = "TestPassword123!"

        // --- Parent creates a household and invites a child ---
        signUp(app: app, email: parentEmail, password: password)

        let createHouseholdButton = app.buttons["Create a household"]
        XCTAssertTrue(createHouseholdButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        createHouseholdButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Dad")
        app.textFields["Household name (e.g. \"The Geigers\")"].tap()
        app.textFields["Household name (e.g. \"The Geigers\")"].typeText("The Geigers")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")

        app.buttons["Invite a child"].tap()
        let codeText = app.staticTexts.matching(identifier: "generatedInviteCode").firstMatch
        XCTAssertTrue(codeText.waitForExistence(timeout: 10))
        let inviteCode = codeText.label

        app.buttons["Sign Out"].tap()

        // --- Child signs up and joins ---
        signUp(app: app, email: childEmail, password: password)

        let joinButton = app.buttons["Join with an invite code"]
        XCTAssertTrue(joinButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        joinButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Kiddo")
        app.textFields["Invite code"].tap()
        app.textFields["Invite code"].typeText(inviteCode)
        app.buttons["Join"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        resetToSignedOutState(app: app)

        // --- Parent signs back in, adds a chore (5 pts by default) and completes it for Kiddo ---
        signIn(app: app, email: parentEmail, password: password)

        tapTab(app, "Chores")

        tapAddButton(app: app)
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
        app.textFields["Title"].tap()
        app.textFields["Title"].typeText("Make bed")
        app.buttons["Save"].tap()

        let choreRow = app.staticTexts["Make bed"]
        XCTAssertTrue(choreRow.waitForExistence(timeout: 10))

        // Tap the completion toggle next to the chore to award points.
        let completeButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'completeChoreButton-'")).firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        // --- Add a reward costing exactly 5 points (default chore award) ---
        tapTab(app, "Rewards")
        tapAddButton(app: app)

        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("Ice cream")

        let decrementButton = app.steppers.firstMatch.buttons["Decrement"]
        XCTAssertTrue(decrementButton.waitForExistence(timeout: 5))
        for _ in 0..<3 { decrementButton.tap() } // 20 -> 5 in steps of 5

        app.buttons["Save"].tap()

        // --- Redeem it on Kiddo's behalf from the parent's Rewards view ---
        let redeemButton = app.buttons["Redeem"].firstMatch
        XCTAssertTrue(redeemButton.waitForExistence(timeout: 10), "Reward should appear under Kiddo with an enabled Redeem button")
        XCTAssertTrue(redeemButton.isEnabled, "Kiddo should be able to afford the reward after completing the chore")
        redeemButton.tap()

        // Wait for the write to actually land — confirmed by the parent's own
        // view recomputing the balance and disabling the now-unaffordable
        // button — before tearing down this session. Signing out too soon
        // after a write risks racing the local mutation queue.
        let becameDisabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: redeemButton)
        XCTAssertEqual(XCTWaiter().wait(for: [becameDisabled], timeout: 10), .completed, "Redeem button should disable once the parent's own view reflects the spent balance")

        // --- Confirm from Kiddo's own account: balance is spent, redemption shows in history ---
        resetToSignedOutState(app: app)
        signIn(app: app, email: childEmail, password: password)

        tapTab(app, "Rewards")

        XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 10), "Kiddo's balance should be 0 after redeeming a 5-point reward with a 5-point balance")
        XCTAssertTrue(app.staticTexts["Ice cream"].exists, "Redeemed reward should show in Kiddo's history")
        add(XCTAttachment(screenshot: app.screenshot()))

        // Clean up both accounts, same reasoning as testStage2: deleting
        // Kiddo first just leaves Dad in the household; deleting Dad second —
        // now the last member — cascades into deleting the whole household.
        deleteCurrentAccount(app: app)
        signIn(app: app, email: parentEmail, password: password)
        deleteCurrentAccount(app: app)
    }

    /// Regression test for a real bug: account deletion used to sign the
    /// Auth account out successfully while silently leaving the household's
    /// Firestore data behind (a `list` query the cascade depended on was
    /// denied by the security rules, throwing partway through — but the
    /// caller deleted the Auth account regardless of whether cleanup
    /// succeeded). The other delete-account tests only ever checked "did we
    /// land back on the sign-in screen," which that bug didn't affect, so it
    /// slipped through — this test instead checks that the household data
    /// itself is actually gone, by confirming a stale invite code no longer
    /// resolves to a household after the sole member deletes their account.
    @MainActor
    func testStage5AccountDeletionActuallyDeletesHouseholdData() throws {
        let app = XCUIApplication()
        app.launch()

        resetToSignedOutState(app: app)

        let runId = Int(Date().timeIntervalSince1970)
        let parentEmail = "parent5-\(runId)@example.com"
        let strandedEmail = "stranded5-\(runId)@example.com"
        let password = "TestPassword123!"

        signUp(app: app, email: parentEmail, password: password)

        let createHouseholdButton = app.buttons["Create a household"]
        XCTAssertTrue(createHouseholdButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        createHouseholdButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Dad")
        app.textFields["Household name (e.g. \"The Geigers\")"].tap()
        app.textFields["Household name (e.g. \"The Geigers\")"].typeText("The Geigers")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")

        // Generate a code but never use it to add a member — Dad stays the
        // household's only member, so deleting his account should cascade
        // into deleting the household outright.
        app.buttons["Invite a child"].tap()
        let codeText = app.staticTexts.matching(identifier: "generatedInviteCode").firstMatch
        XCTAssertTrue(codeText.waitForExistence(timeout: 10))
        let staleInviteCode = codeText.label

        deleteCurrentAccount(app: app)

        // A fresh account trying to join with that now-stale code should
        // fail — if it instead succeeds, the household was never deleted.
        signUp(app: app, email: strandedEmail, password: password)

        let joinButton = app.buttons["Join with an invite code"]
        XCTAssertTrue(joinButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        joinButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Stranded")
        app.textFields["Invite code"].tap()
        app.textFields["Invite code"].typeText(staleInviteCode)
        app.buttons["Join"].tap()

        // Give it a real chance to (wrongly) succeed before concluding it didn't.
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertFalse(app.tabBars.buttons["Chores"].exists, "Joining with a code from a deleted household must not succeed — the household data should be gone")
        XCTAssertTrue(app.buttons["Join with an invite code"].exists || app.textFields["Your name"].exists, "Should still be stuck on the join screen, not signed into a resurrected household")

        // This account never joined a household — Delete Account is also
        // reachable straight from the pre-household chooser screen now.
        app.buttons["Back"].tap()
        deleteCurrentAccount(app: app)
    }

    /// A redemption now waits on a parent to hand the reward over, so the
    /// parent's Rewards screen leads with a queue of what's outstanding.
    @MainActor
    func testStage6ParentFulfillsAQueuedRedemption() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpParentWithPendingRedemption(app: app, prefix: "fulfil6")

        // --- The request is waiting on the parent, and says so from the tab bar ---
        let pendingRow = queuedRequest(app)
        XCTAssertTrue(pendingRow.waitForExistence(timeout: 15), "Redeeming should leave a request waiting on the parent, naming who asked for what")
        XCTAssertTrue(app.staticTexts["Waiting on you"].exists, "The queue should lead the parent's screen")

        // The Rewards tab badge is deliberately NOT asserted here. XCUITest
        // does not surface a SwiftUI tab badge at all: the tab element dumps
        // as `identifier: 'star.fill', label: 'Rewards'` with no badge in
        // either the label or the value, so any assertion on it can only
        // ever fail. What the badge counts -- `RewardStore.pendingCount` --
        // is the same `pendingRedemptions` that drives the queue section
        // below, and that is covered here and in the cancel test.
        add(XCTAttachment(screenshot: app.screenshot()))

        // --- Handing it over clears it from the queue ---
        let fulfillButton = app.buttons["Fulfilled"].firstMatch
        XCTAssertTrue(fulfillButton.waitForExistence(timeout: 5))
        fulfillButton.tap()

        let leftTheQueue = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pendingRow)
        XCTAssertEqual(
            XCTWaiter().wait(for: [leftTheQueue], timeout: 15), .completed,
            "A fulfilled request should leave the parent's queue"
        )
        XCTAssertTrue(app.staticTexts["Received"].waitForExistence(timeout: 10), "It should show as received in history")

        // Fulfilling moves no points -- they were spent when it was redeemed.
        XCTAssertFalse(app.buttons["Redeem"].firstMatch.isEnabled, "Fulfilling must not give the points back")

        // Un-fulfil is the way back from a mistaken tap, and the only route
        // to cancelling something already marked fulfilled. It now confirms
        // first (with an optional note), the same as cancel already does.
        let historyRow = app.staticTexts["Kiddo — Ice cream"].firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        historyRow.swipeLeft()
        let unfulfillButton = app.buttons["Un-fulfill"].firstMatch
        XCTAssertTrue(unfulfillButton.waitForExistence(timeout: 5), "A fulfilled request should offer Un-fulfill")
        unfulfillButton.tap()

        let confirmUnfulfill = app.buttons["Un-fulfill and return to queue"]
        XCTAssertTrue(confirmUnfulfill.waitForExistence(timeout: 5), "Un-fulfilling should confirm first")
        confirmUnfulfill.tap()

        XCTAssertTrue(queuedRequest(app).waitForExistence(timeout: 15), "Un-fulfilling should put it back in the queue")
        XCTAssertFalse(app.buttons["Redeem"].firstMatch.isEnabled, "Un-fulfilling must not move points either")

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// Cancelling is the only path that returns points, so this checks the
    /// refund actually lands rather than just that the row disappeared.
    @MainActor
    func testStage6ParentCancelsAQueuedRedemptionAndPointsComeBack() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpParentWithPendingRedemption(app: app, prefix: "cancel6")

        let pendingRow = queuedRequest(app)
        XCTAssertTrue(pendingRow.waitForExistence(timeout: 15), "Redeeming should leave a request waiting on the parent")

        // Spending the 5 points left Kiddo unable to afford the 5-point
        // reward -- which is what makes the refund visible below.
        let redeemButton = app.buttons["Redeem"].firstMatch
        XCTAssertTrue(redeemButton.waitForExistence(timeout: 10))
        XCTAssertFalse(redeemButton.isEnabled, "Kiddo should be broke after redeeming")

        pendingRow.swipeLeft()
        let cancelButton = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Swiping a queued request should reveal Cancel")
        cancelButton.tap()

        // Returning points asks first.
        let confirm = app.buttons["Cancel and return 5 points"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Cancelling should confirm before returning points")
        confirm.tap()

        let leftTheQueue = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pendingRow)
        XCTAssertEqual(
            XCTWaiter().wait(for: [leftTheQueue], timeout: 15), .completed,
            "A cancelled request should leave the parent's queue"
        )

        // The refund, seen on screen: Kiddo can afford the reward again.
        let affordableAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: redeemButton)
        XCTAssertEqual(
            XCTWaiter().wait(for: [affordableAgain], timeout: 15), .completed,
            "Cancelling should return the points, re-enabling Redeem"
        )
        XCTAssertTrue(app.staticTexts["Cancelled — points returned"].exists, "The cancelled entry should stay in history, labelled")
        XCTAssertFalse(app.staticTexts["Waiting on you"].exists, "With nothing pending, the queue should not be shown at all")
        add(XCTAttachment(screenshot: app.screenshot()))

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// The note is optional and durable: it rides along with the cancel and
    /// shows up on the resulting history entry, not just in a notification
    /// that could be missed.
    @MainActor
    func testStage6ParentCancelsWithANoteAndItShowsInHistory() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpParentWithPendingRedemption(app: app, prefix: "cancelnote6")

        let pendingRow = queuedRequest(app)
        XCTAssertTrue(pendingRow.waitForExistence(timeout: 15))

        pendingRow.swipeLeft()
        let cancelButton = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        let noteField = app.textFields["Note (optional)"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 5), "Cancelling should offer an optional note")
        noteField.tap()
        noteField.typeText("out of stock")

        let confirm = app.buttons["Cancel and return 5 points"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let leftTheQueue = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pendingRow)
        XCTAssertEqual(
            XCTWaiter().wait(for: [leftTheQueue], timeout: 15), .completed,
            "A cancelled request should leave the parent's queue"
        )

        XCTAssertTrue(app.staticTexts["Cancelled — points returned"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["out of stock"].waitForExistence(timeout: 5),
            "The note should show alongside the cancelled entry"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// Un-fulfilling had no confirmation at all before this change; this
    /// checks the new one actually offers a note and that the note travels
    /// with the redemption back into the pending queue.
    @MainActor
    func testStage6ParentUnfulfillsWithANoteAndItShowsInTheQueue() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpParentWithPendingRedemption(app: app, prefix: "unfulfilnote6")

        let pendingRow = queuedRequest(app)
        XCTAssertTrue(pendingRow.waitForExistence(timeout: 15))

        let fulfillButton = app.buttons["Fulfilled"].firstMatch
        XCTAssertTrue(fulfillButton.waitForExistence(timeout: 5))
        fulfillButton.tap()

        let leftTheQueue = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pendingRow)
        XCTAssertEqual(XCTWaiter().wait(for: [leftTheQueue], timeout: 15), .completed)

        let historyRow = app.staticTexts["Kiddo — Ice cream"].firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        historyRow.swipeLeft()
        let unfulfillButton = app.buttons["Un-fulfill"].firstMatch
        XCTAssertTrue(unfulfillButton.waitForExistence(timeout: 5))
        unfulfillButton.tap()

        let noteField = app.textFields["Note (optional)"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 5), "Un-fulfilling should offer an optional note")
        noteField.tap()
        noteField.typeText("wrong reward, sorry")

        let confirm = app.buttons["Un-fulfill and return to queue"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(queuedRequest(app).waitForExistence(timeout: 15), "Un-fulfilling should put it back in the queue")
        XCTAssertTrue(
            app.staticTexts["wrong reward, sorry"].waitForExistence(timeout: 5),
            "The note should show alongside the requeued row"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// Checking every item completes a checklist chore and credits its
    /// points exactly once -- not per item.
    @MainActor
    func testStage7CheckingEveryChecklistItemCompletesAndCreditsOnce() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpChildWithChecklistChore(app: app, prefix: "checklist7a")

        let checkboxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemCheckbox-'"))
        XCTAssertEqual(checkboxes.count, 3, "Should render one checkbox per checklist item")

        checkboxes.element(boundBy: 0).tap()
        checkboxes.element(boundBy: 1).tap()
        checkboxes.element(boundBy: 2).tap()

        XCTAssertTrue(app.staticTexts["3/3"].waitForExistence(timeout: 10), "Progress should read 3/3 once every item is checked")

        tapTab(app, "Rewards")
        XCTAssertTrue(
            app.staticTexts["10"].waitForExistence(timeout: 10),
            "Completing the checklist should credit its 10 points exactly once"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// No points until the last item closes the set -- a partially-checked
    /// checklist earns nothing.
    @MainActor
    func testStage7PartialChecklistDoesNotCreditUntilTheLastItem() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpChildWithChecklistChore(app: app, prefix: "checklist7b")

        let checkboxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemCheckbox-'"))
        checkboxes.element(boundBy: 0).tap()
        checkboxes.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["2/3"].waitForExistence(timeout: 10))

        tapTab(app, "Rewards")
        XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 10), "No points yet with one item still unchecked")

        tapTab(app, "Chores")
        checkboxes.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["3/3"].waitForExistence(timeout: 10))

        tapTab(app, "Rewards")
        XCTAssertTrue(
            app.staticTexts["10"].waitForExistence(timeout: 10),
            "Checking the last item should credit the full 10 points"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// Unchecking an item after the checklist already completed reverses it
    /// -- confirmed first, since it takes points back -- and the checklist
    /// can be completed again afterward.
    @MainActor
    func testStage7UncheckingAfterCompletionReversesAndCanBeRedone() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpChildWithChecklistChore(app: app, prefix: "checklist7c")

        let checkboxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemCheckbox-'"))
        checkboxes.element(boundBy: 0).tap()
        checkboxes.element(boundBy: 1).tap()
        checkboxes.element(boundBy: 2).tap()

        tapTab(app, "Rewards")
        XCTAssertTrue(app.staticTexts["10"].waitForExistence(timeout: 10))

        tapTab(app, "Chores")
        checkboxes.element(boundBy: 0).tap() // unchecking a completed item is a reversal

        let confirm = app.buttons["Undo and take back 10 points"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Unchecking a completed checklist item should confirm before taking points back")
        confirm.tap()

        tapTab(app, "Rewards")
        XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 10), "Reversal should take the points back")

        tapTab(app, "Chores")
        checkboxes.element(boundBy: 0).tap() // re-check it

        tapTab(app, "Rewards")
        XCTAssertTrue(
            app.staticTexts["10"].waitForExistence(timeout: 10),
            "Re-checking every item should complete and credit again"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// The reversal's optional note is durable: it shows on the history
    /// entry, not just in a notification that could be missed. Reversing
    /// here is done by the parent, since any household member may do it.
    @MainActor
    func testStage7ParentReversesWithANoteAndItShowsInHistory() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpParentWithChecklistChore(app: app, prefix: "checklist7d")

        let checkboxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemCheckbox-'"))
        checkboxes.element(boundBy: 0).tap()
        checkboxes.element(boundBy: 1).tap()
        checkboxes.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["3/3"].waitForExistence(timeout: 10))

        checkboxes.element(boundBy: 0).tap() // parent reverses on Kiddo's behalf

        let noteField = app.textFields["Note (optional)"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 5), "Reversing a completed item should offer an optional note")
        noteField.tap()
        noteField.typeText("checked by mistake")

        let confirm = app.buttons["Undo and take back 10 points"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["Undone"].waitForExistence(timeout: 10),
            "The reversed completion should show in history, marked undone"
        )
        XCTAssertTrue(
            app.staticTexts["checked by mistake"].waitForExistence(timeout: 5),
            "The reversal note should show alongside the history entry"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// A reversal without a note still succeeds and still shows in history --
    /// the note is optional, not a requirement to undo. Done by Kiddo on
    /// their own completed chore (any household member may reverse,
    /// including the assignee themselves), which is also what
    /// `ChoreCompletionReversalNotifier` depends on to alert the right
    /// person: this checks the durable data that notifier reads
    /// (`completedByUID` == the reversing member, `reversedAt` set, no
    /// note) reaches history correctly. The notification banner itself
    /// isn't asserted here -- no test in this suite inspects actual
    /// delivered notification content, for either reversal notifier.
    @MainActor
    func testStage7SelfReversalWithoutANoteStillShowsUndone() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpChildWithChecklistChore(app: app, prefix: "checklist7f")

        let checkboxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemCheckbox-'"))
        checkboxes.element(boundBy: 0).tap()
        checkboxes.element(boundBy: 1).tap()
        checkboxes.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["3/3"].waitForExistence(timeout: 10))

        checkboxes.element(boundBy: 0).tap() // Kiddo undoes their own completed item

        let confirm = app.buttons["Undo and take back 10 points"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Reversing should offer to confirm even without typing a note")
        confirm.tap() // no note entered

        XCTAssertTrue(
            app.staticTexts["Undone"].waitForExistence(timeout: 10),
            "A note-less self-reversal should still show in history, marked undone"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// Editing a checklist's items never auto-completes it; the explicit
    /// "Mark Complete" action is what's needed once an edit leaves the
    /// checked items already covering what's left required.
    @MainActor
    func testStage7EditingItemsDoesNotAutoCompleteMarkCompleteDoes() throws {
        let app = makeApp()
        app.launch()

        let accounts = setUpParentWithChecklistChore(app: app, prefix: "checklist7e")

        let checkboxes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemCheckbox-'"))
        checkboxes.element(boundBy: 0).tap()
        checkboxes.element(boundBy: 1).tap()
        // The 3rd item ("Practice piano") is deliberately left unchecked.
        XCTAssertTrue(app.staticTexts["2/3"].waitForExistence(timeout: 10))

        // Edit the chore, removing the still-unchecked 3rd item -- the
        // checked set (items 0, 1) now covers everything left required.
        let choreTitle = app.staticTexts["Morning Chores"].firstMatch
        XCTAssertTrue(choreTitle.waitForExistence(timeout: 5))
        choreTitle.tap()

        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5), "Tapping the chore as a parent should open the editor")
        // Also bump points in the same edit -- narrows whether a save
        // failing to persist is specific to checklist items, or every
        // field of an existing-chore edit silently fails to round-trip.
        app.steppers.firstMatch.buttons["Increment"].tap()
        let deleteLastItemButton = app.buttons["checklistItemDeleteButton-2"]
        XCTAssertTrue(deleteLastItemButton.waitForExistence(timeout: 5))
        deleteLastItemButton.tap()
        app.buttons["Save"].tap()

        if app.staticTexts["Something went wrong"].waitForExistence(timeout: 3) {
            XCTFail("Save reported an error: \(app.alerts.staticTexts.element(boundBy: 1).label)")
        }
        XCTAssertTrue(app.staticTexts["Morning Chores"].waitForExistence(timeout: 10))

        // A single checklist chore shows its title exactly twice (once in
        // Active, once in Recurring) -- more than that means save() took
        // the create branch instead of update, leaving the original
        // untouched and adding a second, separate chore.
        let allTitles = app.staticTexts.matching(NSPredicate(format: "label == 'Morning Chores'"))
        XCTAssertEqual(allTitles.count, 2, "Expected exactly one chore (title shown twice: Active + Recurring), found \(allTitles.count) occurrences -- possible duplicate chore")

        // Reopen the editor and count fields directly -- isolates whether
        // the save itself round-tripped 2 items, independent of whatever
        // computes the "checked/total" progress text shown on the row.
        app.staticTexts["Morning Chores"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5), "Reopening the chore should open the editor")
        XCTAssertTrue(app.staticTexts["Points: 11"].waitForExistence(timeout: 5), "The points bump from the same edit should also have persisted")
        let fieldsAfterSave = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'checklistItemTitleField-'"))
        let valuesAfterSave = (0..<fieldsAfterSave.count).map { fieldsAfterSave.element(boundBy: $0).value as? String ?? "?" }
        XCTAssertEqual(fieldsAfterSave.count, 2, "The saved chore should have 2 items, not 3, when reopened -- actual field contents: \(valuesAfterSave)")
        app.buttons["Cancel"].tap()

        // Confirms editing alone did not auto-complete it -- a weaker
        // "not 3/3" check can't tell a genuinely-deleted item apart from a
        // delete that silently failed to persist, since 2/3 also isn't "3/3".
        XCTAssertTrue(app.staticTexts["2/2"].waitForExistence(timeout: 10), "Should show 2/2 after removing the 3rd item, confirming the delete landed")

        let markComplete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'markChecklistCompleteButton-'")).firstMatch
        XCTAssertTrue(markComplete.waitForExistence(timeout: 10), "Mark Complete should appear once editing leaves the checklist already satisfied")
        markComplete.tap()

        tapTab(app, "Rewards")
        XCTAssertTrue(
            app.staticTexts["11"].waitForExistence(timeout: 10),
            "The explicit Mark Complete action should credit the chore's points (11, after the points bump earlier in this edit)"
        )

        tearDownAccounts(app: app, accounts: accounts)
    }

    /// The queued request, found by the text it renders rather than by the
    /// row's accessibility identifier.
    ///
    /// `pendingRedemptionRow-<id>` is set on the row's HStack and is the
    /// right handle in principle, but SwiftUI doesn't reliably surface an
    /// identifier placed on a `List` row's container as a queryable element
    /// — `app.otherElements` found nothing, which is what failed the first
    /// run of these two tests. A plain `Text` is always exposed, and swiping
    /// it triggers the row's swipe actions just the same.
    private func queuedRequest(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["Kiddo wants Ice cream"].firstMatch
    }

    /// The notification permission alert is a SpringBoard alert that would
    /// appear the moment a parent's queue first fills, swallowing whatever
    /// tap came next. Suppressing just the prompt keeps the queue, the
    /// badges, and every assertion here intact.
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STARTIME_SUPPRESS_NOTIFICATION_PROMPT"] = "1"
        return app
    }

    /// Leaves the app signed in as a parent, on the Rewards tab, with exactly
    /// one pending redemption: Kiddo has earned 5 points from a chore and
    /// spent all of them on a 5-point reward.
    private func setUpParentWithPendingRedemption(
        app: XCUIApplication,
        prefix: String
    ) -> (parentEmail: String, childEmail: String, password: String) {
        resetToSignedOutState(app: app)

        let runId = Int(Date().timeIntervalSince1970)
        let parentEmail = "parent-\(prefix)-\(runId)@example.com"
        let childEmail = "child-\(prefix)-\(runId)@example.com"
        let password = "TestPassword123!"

        signUp(app: app, email: parentEmail, password: password)

        let createHouseholdButton = app.buttons["Create a household"]
        XCTAssertTrue(createHouseholdButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        createHouseholdButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Dad")
        app.textFields["Household name (e.g. \"The Geigers\")"].tap()
        app.textFields["Household name (e.g. \"The Geigers\")"].typeText("The Geigers")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")

        app.buttons["Invite a child"].tap()
        let codeText = app.staticTexts.matching(identifier: "generatedInviteCode").firstMatch
        XCTAssertTrue(codeText.waitForExistence(timeout: 10))
        let inviteCode = codeText.label

        app.buttons["Sign Out"].tap()

        signUp(app: app, email: childEmail, password: password)

        let joinButton = app.buttons["Join with an invite code"]
        XCTAssertTrue(joinButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        joinButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Kiddo")
        app.textFields["Invite code"].tap()
        app.textFields["Invite code"].typeText(inviteCode)
        app.buttons["Join"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        resetToSignedOutState(app: app)

        signIn(app: app, email: parentEmail, password: password)
        tapTab(app, "Chores")

        tapAddButton(app: app)
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
        app.textFields["Title"].tap()
        app.textFields["Title"].typeText("Make bed")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Make bed"].waitForExistence(timeout: 10))
        let completeButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'completeChoreButton-'"))
            .firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        tapTab(app, "Rewards")
        tapAddButton(app: app)

        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("Ice cream")
        let decrementButton = app.steppers.firstMatch.buttons["Decrement"]
        XCTAssertTrue(decrementButton.waitForExistence(timeout: 5))
        for _ in 0..<3 { decrementButton.tap() } // 20 -> 5 in steps of 5
        app.buttons["Save"].tap()

        let redeemButton = app.buttons["Redeem"].firstMatch
        XCTAssertTrue(redeemButton.waitForExistence(timeout: 10))
        XCTAssertTrue(redeemButton.isEnabled, "Kiddo should be able to afford the reward after the chore")
        redeemButton.tap()

        return (parentEmail, childEmail, password)
    }

    /// Same ordering as the other multi-account tests: the child first, which
    /// only drops them from the household, then the parent, who as the last
    /// member cascades the household away.
    private func tearDownAccounts(
        app: XCUIApplication,
        accounts: (parentEmail: String, childEmail: String, password: String)
    ) {
        resetToSignedOutState(app: app)
        signIn(app: app, email: accounts.childEmail, password: accounts.password)
        deleteCurrentAccount(app: app)
        signIn(app: app, email: accounts.parentEmail, password: accounts.password)
        deleteCurrentAccount(app: app)
    }

    /// Leaves the app signed in as the parent, on the Chores tab, with one
    /// checklist chore ("Morning Chores": Brush teeth, Eat breakfast,
    /// Practice piano — 10 points by default) assigned to Kiddo and not yet
    /// checked.
    private func setUpParentWithChecklistChore(
        app: XCUIApplication,
        prefix: String,
        itemTitles: [String] = ["Brush teeth", "Eat breakfast", "Practice piano"]
    ) -> (parentEmail: String, childEmail: String, password: String) {
        resetToSignedOutState(app: app)

        let runId = Int(Date().timeIntervalSince1970)
        let parentEmail = "parent-\(prefix)-\(runId)@example.com"
        let childEmail = "child-\(prefix)-\(runId)@example.com"
        let password = "TestPassword123!"

        signUp(app: app, email: parentEmail, password: password)

        let createHouseholdButton = app.buttons["Create a household"]
        XCTAssertTrue(createHouseholdButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        createHouseholdButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Dad")
        app.textFields["Household name (e.g. \"The Geigers\")"].tap()
        app.textFields["Household name (e.g. \"The Geigers\")"].typeText("The Geigers")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        tapTab(app, "Settings")

        app.buttons["Invite a child"].tap()
        let codeText = app.staticTexts.matching(identifier: "generatedInviteCode").firstMatch
        XCTAssertTrue(codeText.waitForExistence(timeout: 10))
        let inviteCode = codeText.label

        app.buttons["Sign Out"].tap()

        signUp(app: app, email: childEmail, password: password)

        let joinButton = app.buttons["Join with an invite code"]
        XCTAssertTrue(joinButton.waitForExistence(timeout: 15))
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        joinButton.tap()
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        app.textFields["Your name"].tap()
        app.textFields["Your name"].typeText("Kiddo")
        app.textFields["Invite code"].tap()
        app.textFields["Invite code"].typeText(inviteCode)
        app.buttons["Join"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chores"].waitForExistence(timeout: 15))
        resetToSignedOutState(app: app)

        // --- Parent creates the checklist chore ---
        signIn(app: app, email: parentEmail, password: password)
        tapTab(app, "Chores")
        // The Save Password prompt can appear with a delay after sign-in
        // (see dismissSavePasswordPromptIfPresent's own doc comment) --
        // late enough that it can still be covering the screen here, an
        // action or two after signIn's own dismiss attempt.
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)

        tapAddButton(app: app)
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
        app.textFields["Title"].tap()
        app.textFields["Title"].typeText("Morning Chores")
        dismissKeyboard(app)

        let incrementButton = app.steppers.firstMatch.buttons["Increment"]
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 5))
        for _ in 0..<5 { incrementButton.tap() } // 5 -> 10 pts

        let checklistToggle = app.switches["Use a checklist"]
        XCTAssertTrue(checklistToggle.waitForExistence(timeout: 5))
        // SwiftUI's Toggle in a Form row produces a *nested* accessibility
        // structure: an outer row-wide Switch (labeled "Use a checklist",
        // reported `isHittable == false`) wrapping a StaticText and a
        // second, unlabeled inner Switch positioned exactly on the visual
        // knob -- that inner one is the real native control that responds
        // to touches. `app.switches["Use a checklist"]` matches the outer
        // wrapper, which is why every tap technique on it silently did
        // nothing (confirmed directly via its own `.value` staying "0").
        checklistToggle.switches.firstMatch.tap()
        XCTAssertEqual(checklistToggle.value as? String, "1", "Toggle should be on after tapping its switch")

        let addItemButton = app.buttons["Add item"]
        for (index, title) in itemTitles.enumerated() {
            // Revealed by the toggle above (or, on later iterations, pushed
            // down the Form by the previous row) -- not present at the
            // moment of the tap that reveals/relocates it, so this needs an
            // explicit wait like every other conditionally-shown control in
            // this file, not a bare `.tap()`.
            XCTAssertTrue(addItemButton.waitForExistence(timeout: 5), "Add item button should appear")
            addItemButton.tap()
            let field = app.textFields["checklistItemTitleField-\(index)"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            dismissKeyboard(app) // else the next "Add item" tap can land on a still-open keyboard
        }

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Morning Chores"].waitForExistence(timeout: 10))

        return (parentEmail, childEmail, password)
    }

    /// Same setup as `setUpParentWithChecklistChore`, but leaves the app
    /// signed in as Kiddo instead, on the Chores tab.
    private func setUpChildWithChecklistChore(
        app: XCUIApplication,
        prefix: String,
        itemTitles: [String] = ["Brush teeth", "Eat breakfast", "Practice piano"]
    ) -> (parentEmail: String, childEmail: String, password: String) {
        let accounts = setUpParentWithChecklistChore(app: app, prefix: prefix, itemTitles: itemTitles)
        resetToSignedOutState(app: app)
        signIn(app: app, email: accounts.childEmail, password: accounts.password)
        tapTab(app, "Chores")
        // Same delayed-prompt reasoning as in setUpParentWithChecklistChore.
        dismissSavePasswordPromptIfPresent(app: app, timeout: 2)
        XCTAssertTrue(app.staticTexts["Morning Chores"].waitForExistence(timeout: 10))
        return accounts
    }

    /// Opens the add-chore/add-reward sheet, retrying the tap (same stale
    /// hit-point issue as tab bar taps) until the sheet's Cancel button
    /// actually appears, rather than trusting a single tap succeeded.
    private func tapAddButton(app: XCUIApplication) {
        let addByLabel = app.navigationBars.buttons["Add"]
        let addByIcon = app.buttons["plus"]
        let trigger: XCUIElement
        if addByLabel.waitForExistence(timeout: 3) {
            trigger = addByLabel
        } else {
            XCTAssertTrue(addByIcon.waitForExistence(timeout: 5), "Should find the toolbar add button")
            trigger = addByIcon
        }

        let cancelButton = app.buttons["Cancel"]
        for _ in 0..<5 {
            if cancelButton.exists { return }
            Thread.sleep(forTimeInterval: 0.4)
            trigger.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2), "Add sheet should open after repeated taps")
    }

    /// Taps the navigation bar (a safe, always-visible, non-interactive
    /// point regardless of scroll position) to resign a text field's first
    /// responder. `AddEditChoreView`'s Form is tall enough (Chore, Icon,
    /// Repeats, Checklist, Assigned to) that a keyboard left open from an
    /// earlier field can occlude a lower section's controls entirely —
    /// which is exactly what "Failed to tap 'Add item' Button: No matches
    /// found" turned out to mean the first time this ran: the query wasn't
    /// wrong, the keyboard was still covering it.
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.element.exists {
            app.navigationBars.firstMatch.tap()
        }
    }

    /// Tab bar taps immediately after a screen transition (sign-in, sign-up,
    /// household creation) can compute a stale hit point mid-animation and
    /// silently miss, same as the system-dialog dismissal race — a fixed
    /// settle delay before a single tap isn't reliable, so instead verify
    /// success via the button's `isSelected` trait and retry the tap if it
    /// didn't take.
    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Tab bar button '\(label)' should exist")
        for _ in 0..<5 {
            if button.isSelected { break }
            Thread.sleep(forTimeInterval: 0.4)
            button.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(button.isSelected, "Tab bar button '\(label)' never became selected after repeated taps")
        // Give the newly selected tab's content a moment to finish laying
        // out before the caller's next action fires.
        Thread.sleep(forTimeInterval: 0.4)
    }

    /// Deletes the currently signed-in account (and its household data via
    /// the app's own cascading cleanup) so test runs don't accumulate
    /// throwaway accounts/households in the backend. Leaves the app signed out.
    private func deleteCurrentAccount(app: XCUIApplication) {
        if !app.buttons["deleteAccountRowButton"].waitForExistence(timeout: 3) {
            tapTab(app, "Settings")
        }
        let rowButton = app.buttons["deleteAccountRowButton"]
        XCTAssertTrue(rowButton.waitForExistence(timeout: 10), "Delete Account row should exist in Settings")
        rowButton.tap()

        // Scoped to the action sheet specifically — the Settings row shares
        // the same "Delete Account" label, so an unscoped app.buttons[...]
        // query matches both and is ambiguous.
        let confirmButton = app.sheets.buttons["Delete Account"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Delete confirmation dialog should appear")
        confirmButton.tap()

        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 15), "Should return to sign-in after deleting account")
    }

    private func signUp(app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText(email)

        app.buttons["New here? Create an account"].tap()

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["Create Account"].tap()
        dismissSavePasswordPromptIfPresent(app: app)
    }

    /// A prior run's session may still be active on this simulator (Cognito
    /// tokens persist across launches via the Keychain) — reset to a clean signed-out state
    /// regardless of whether that leaves us on the auth-gate chooser screen
    /// or deep inside the main tab view.
    private func resetToSignedOutState(app: XCUIApplication) {
        if app.buttons["Sign Out"].waitForExistence(timeout: 5) {
            app.buttons["Sign Out"].tap()
        } else if app.tabBars.buttons["Settings"].waitForExistence(timeout: 5) {
            tapTab(app, "Settings")
            XCTAssertTrue(app.buttons["Sign Out"].waitForExistence(timeout: 5))
            app.buttons["Sign Out"].tap()
        } else {
            return // already signed out
        }
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10), "Should reach the sign-in screen after signing out")
    }

    private func signIn(app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["Sign In"].tap()
        dismissSavePasswordPromptIfPresent(app: app)
    }

    /// The system's "Save Password?" prompt can appear with a delay after
    /// sign-up/sign-in (worse under load with multiple simulators booted),
    /// so callers should call this again immediately before any subsequent
    /// tap it might otherwise swallow.
    private func dismissSavePasswordPromptIfPresent(app: XCUIApplication, timeout: TimeInterval = 5) {
        let notNowButton = app.buttons["Not Now"]
        if notNowButton.waitForExistence(timeout: timeout) {
            notNowButton.tap()
            // Let the sheet's dismiss animation finish before the next tap —
            // tapping too soon computes a stale hit point and silently misses.
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
