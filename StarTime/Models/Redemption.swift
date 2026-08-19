import Foundation

/// Where a redemption sits between "the points were spent" and "the reward
/// was actually handed over". Mirrors the `status` values in
/// backend/cdk/lambda/rewards/redemptions.ts.
enum RedemptionStatus: String, Codable {
    case pending
    case fulfilled
    case cancelled
}

struct Redemption: Identifiable, Codable {
    var id: String?
    var rewardId: String
    var rewardName: String
    var pointsSpent: Int
    var redeemedByUID: String
    var redeemedByName: String
    var redeemedAt: Date?
    /// Non-optional on purpose: the server fills this in for redemptions
    /// recorded before fulfillment tracking existed (see `DEFAULT_STATUS`
    /// server-side), so the client never has to know that older rows are
    /// shaped differently and no call site can forget to default it.
    var status: RedemptionStatus
    var fulfilledAt: Date?
    var fulfilledByName: String?
    var cancelledAt: Date?
    /// Set by the most recent cancel or un-fulfil, whichever happened last;
    /// cleared when the redemption is fulfilled again. Never carries a note
    /// from a reversal that's since been superseded.
    var reversalNote: String?
    /// Stamped fresh on every un-fulfil, unlike `cancelledAt` which is set
    /// once since cancelled is terminal. Exists so the reversal notifier can
    /// tell one un-fulfil event from the next on the same redemption.
    var unfulfilledAt: Date?
}
