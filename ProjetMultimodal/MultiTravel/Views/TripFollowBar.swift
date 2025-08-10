import SwiftUI

struct TripFollowBar: View {
    let route: TripResponse.RouteOption
    let activeIndex: Int
    let onPrev: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(titleText)
                    .font(.headline)
                Spacer()
                Button(action: onExit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            
            HStack(spacing: 12) {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .disabled(activeIndex <= 0)
                .foregroundColor(activeIndex <= 0 ? .gray : .blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(stepTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(instruction)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .disabled(activeIndex >= route.segments.count - 1)
                .foregroundColor(activeIndex >= route.segments.count - 1 ? .gray : .blue)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
            
            // Progress indicators
            HStack(spacing: 6) {
                ForEach(0..<route.segments.count, id: \.self) { i in
                    Circle()
                        .fill(i == activeIndex ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trip segment controls")
    }
    
    private var titleText: String {
        "Follow trip: segment \(activeIndex + 1) of \(route.segments.count)"
    }
    
    private var stepTitle: String {
        guard let seg = safeSegment else { return "Segment" }
        let mode = seg.transportType.displayName
        return "\(mode) \u{2022} \(formatDistance(seg.distance)) \u{2022} \(formatTime(seg.duration))"
    }
    
    private var instruction: String {
        safeSegment?.instructions ?? "Proceed to next step"
    }
    
    private var safeSegment: TripResponse.RouteOption.RouteSegment? {
        guard route.segments.indices.contains(activeIndex) else { return nil }
        return route.segments[activeIndex]
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "– min" }
        let mins = max(0, Int(seconds / 60))
        return "\(mins) min"
    }
    
    private func formatDistance(_ meters: Double) -> String {
        guard meters.isFinite && !meters.isNaN else { return "– km" }
        return String(format: "%.1f km", meters / 1000.0)
    }
}
