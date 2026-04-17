import Foundation

// Mirrors DifficultyRanker, but the comparison question is framed around how
// harmful the reward is. Higher damage sits earlier in the ranked list.
enum DamageRanker {
    struct Session {
        let rewardName: String
        let rankedRewards: [Reward] // sorted most damaging -> least damaging
        var low: Int
        var high: Int
        var comparisonCount: Int = 0

        var isComplete: Bool { low >= high }
        var currentComparison: Reward? {
            isComplete ? nil : rankedRewards[mid]
        }
        var mid: Int { (low + high) / 2 }
        var estimatedComparisons: Int {
            rankedRewards.isEmpty ? 0 : Int(ceil(log2(Double(rankedRewards.count + 1))))
        }

        mutating func chooseMoreDamaging() {
            high = mid
            comparisonCount += 1
        }

        mutating func chooseLessDamaging() {
            low = mid + 1
            comparisonCount += 1
        }

        func generateRank() -> String {
            let moreDamagingRank = low > 0 ? rankedRewards[low - 1].damageRank : nil
            let lessDamagingRank = low < rankedRewards.count ? rankedRewards[low].damageRank : nil
            return FractionalIndex.generateKeyBetween(before: lessDamagingRank, after: moreDamagingRank) ?? "m"
        }
    }

    static func makeSession(rewardName: String, rankedRewards: [Reward]) -> Session {
        Session(
            rewardName: rewardName,
            rankedRewards: rankedRewards,
            low: 0,
            high: rankedRewards.count
        )
    }
}
