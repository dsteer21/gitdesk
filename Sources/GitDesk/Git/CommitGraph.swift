import Foundation

/// A line segment in one half of a graph row, from lane `from` to lane `to`.
struct GraphLine: Hashable {
    let from: Int
    let to: Int
}

struct GraphRow {
    /// Lane holding this commit's node.
    let lane: Int
    /// Segments from the top edge of the row to its centre.
    let top: [GraphLine]
    /// Segments from the centre of the row to its bottom edge.
    let bottom: [GraphLine]
}

/// Assigns commits to lanes for drawing a GitKraken-style graph.
///
/// Each lane holds the hash of the commit it is "waiting for". Walking the
/// commits newest first, a commit takes the lane that is waiting for it (or a
/// free one), then hands that lane to its first parent and opens new lanes for
/// any further (merge) parents.
enum CommitGraph {
    static func build(_ commits: [Commit]) -> (rows: [GraphRow], maxLanes: Int) {
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)
        var maxLanes = 1

        for commit in commits {
            let before = lanes

            // Find (or open) this commit's lane.
            let node: Int
            if let waiting = lanes.firstIndex(of: commit.id) {
                node = waiting
            } else if let free = lanes.firstIndex(of: nil) {
                node = free
            } else {
                node = lanes.count
                lanes.append(nil)
            }

            // Top half: lanes waiting for this commit converge on the node; others pass through.
            var top: [GraphLine] = []
            for (i, hash) in before.enumerated() {
                guard let hash else { continue }
                top.append(GraphLine(from: i, to: hash == commit.id ? node : i))
            }

            // Every lane that was waiting for this commit is now satisfied.
            for i in lanes.indices where lanes[i] == commit.id { lanes[i] = nil }

            // Hand lanes on to the parents.
            for (index, parent) in commit.parents.enumerated() {
                if lanes.contains(parent) { continue }
                if index == 0 {
                    lanes[node] = parent
                } else if let free = lanes.firstIndex(of: nil) {
                    lanes[free] = parent
                } else {
                    lanes.append(parent)
                }
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }

            // Bottom half: node to each parent's lane, plus lanes passing straight through.
            var bottom: [GraphLine] = []
            for parent in commit.parents {
                if let j = lanes.firstIndex(of: parent) { bottom.append(GraphLine(from: node, to: j)) }
            }
            for (i, hash) in lanes.enumerated() {
                guard let hash, i < before.count, before[i] == hash, hash != commit.id else { continue }
                bottom.append(GraphLine(from: i, to: i))
            }

            maxLanes = max(maxLanes, before.count, lanes.count, node + 1)
            rows.append(GraphRow(lane: node, top: top, bottom: bottom))
        }
        return (rows, maxLanes)
    }
}
