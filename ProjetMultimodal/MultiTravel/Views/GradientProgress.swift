import SwiftUI

struct GradientProgress: View {
    let value: Double
    let total: Double
    var height: CGFloat = 10

    private var clamped: Double { max(0, min(value, total)) }
    private var progress: CGFloat { total > 0 ? CGFloat(clamped / total) : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height/2)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: height/2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.35), value: value)
    }
}

#Preview {
    VStack(spacing: 16) {
        GradientProgress(value: 30, total: 210)
        GradientProgress(value: 120, total: 210)
        GradientProgress(value: 240, total: 210)
    }.padding()
}
