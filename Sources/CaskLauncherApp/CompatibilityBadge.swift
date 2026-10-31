import SwiftUI
import AppKit
import CaskLauncherCore

struct CompatibilityBadge: View {
    let compat: GameCompatibility
    
    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s1) {
            HStack(spacing: VermutSpace.s1) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                
                Text(statusText)
                    .font(VermutType.bodyEmphasis)
                    .foregroundStyle(Color.Vermut.foreground)
                
                Text("· \(compat.totalReports) reports")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            }
            
            if let recommendation = compat.effectiveRecommended,
               recommendation != "dxmt",
               compat.totalReports >= 3 {
                Text("Try \(graphicsName(recommendation))")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.amber)
            } else if !compat.effectiveKnownNotWorking.isEmpty {
                Text("Known not working with \(knownNotWorkingSummary)")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var knownNotWorkingSummary: String {
        let labels = compat.effectiveKnownNotWorking.map(\.displayLabel)
        if labels.count <= 2 { return labels.joined(separator: ", ") }
        return labels.prefix(2).joined(separator: ", ") + "…"
    }
    
    private var statusColor: Color {
        let perfectRatio = Double(compat.workingReports) / Double(compat.totalReports)
        let brokenRatio = Double(compat.brokenReports) / Double(compat.totalReports)
        
        if brokenRatio > 0.5 {
            return Color.Vermut.destructive
        } else if perfectRatio > 0.6 {
            return Color.Vermut.green
        } else {
            return Color.Vermut.amber
        }
    }
    
    private var statusText: String {
        let perfectRatio = Double(compat.workingReports) / Double(compat.totalReports)
        let brokenRatio = Double(compat.brokenReports) / Double(compat.totalReports)
        
        if brokenRatio > 0.5 {
            return "Issues"
        } else if perfectRatio > 0.6 {
            return "Works"
        } else {
            return "Mixed"
        }
    }
    
    private func graphicsName(_ identifier: String) -> String {
        switch identifier {
        case "dxmt": return "DXMT"
        case "dxvk": return "DXVK"
        case "d3dmetal": return "D3DMetal"
        case "wined3d": return "WineD3D"
        default: return identifier.uppercased()
        }
    }
}
