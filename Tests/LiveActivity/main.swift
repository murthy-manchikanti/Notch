import Foundation
import NotchCUPS

let processing = Int32(IPP_JSTATE_PROCESSING.rawValue)
let printing = PrintActivity.Job(state: processing, impressions: 8, impressionsCompleted: 2)
precondition(PrintActivity.summarize([]) == nil)
precondition(PrintActivity.summarize([printing]) == PrintActivity(jobCount: 1, progress: 0.25))
precondition(PrintActivity.summarize([printing, printing]) == PrintActivity(jobCount: 2, progress: nil))
precondition(PrintActivity.Job(state: processing, sheets: 2, sheetsCompleted: 1).progress == 0.5)
precondition(PrintActivity.Job(state: processing, impressions: 8).progress == nil)
precondition(PrintActivity.Job(impressions: 8, impressionsCompleted: 2).progress == nil)

let left = PrintIndicatorSide.left.frame(centerX: 500, rowTop: 100, notchWidth: 120, rowHeight: 24)
let right = PrintIndicatorSide.right.frame(centerX: 500, rowTop: 100, notchWidth: 120, rowHeight: 24)
precondition(left.maxX == 432 && right.minX == 568)
precondition(left.minY == 104 && right.maxY == 120)
precondition(MenuSpacePolicy.dotOverlapsMenu([MenuEntry(title: "Window", frame: left)], dot: left))

precondition(ReleaseUpdate.isNewer("v1.0.1", than: "1.0") == true)
precondition(ReleaseUpdate.isNewer("v1.10", than: "1.2") == true)
precondition(ReleaseUpdate.isNewer("v1.0.0", than: "1.0") == false)
precondition(ReleaseUpdate.isNewer("v1.0", than: "2.0") == false)
precondition(ReleaseUpdate.isNewer("invalid", than: "2.0") == nil)
print("Passed print progress, menu geometry, and update version checks")
