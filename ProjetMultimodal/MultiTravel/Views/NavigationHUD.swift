import SwiftUI

struct NavigationHUD: View {
    let segment: TripResponse.RouteOption.RouteSegment
    let index: Int
    let total: Int
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: segment.transportType.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(segment.transportType.color))

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryInstruction)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            Button(action: onEnd) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Capsule().fill(Color.red.opacity(0.9)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.7))
        )
        .padding(.horizontal, 16)
    }

    private var primaryInstruction: String {
        segment.instructions.isEmpty ? defaultInstruction : segment.instructions
    }

    private var defaultInstruction: String {
        switch segment.transportType {
        case .driving: return "Drive to next step"
        case .walking: return "Walk to next step"
        case .biking: return "Bike to next step"
        case .transit: return "Use transit to next stop"
        }
    }

    private var subtitle: String {
        "Step \(index + 1) of \(total)"
    }
}
