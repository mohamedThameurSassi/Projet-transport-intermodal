import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.sex") private var sex: String = ""
    @AppStorage("profile.weight") private var weight: Double = 0
    @AppStorage("profile.height") private var height: Double = 0
    @AppStorage("walkingObjective") private var walkingObjective: Int = 30
    @AppStorage("activity.weeklyMinutes") private var weeklyMinutes: Int = 0

    private var weeklyGoal: Int { max(1, walkingObjective * 7) }

    var body: some View {
        NavigationView {
            List {
                Section("Weekly Activity") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("This week")
                            Spacer()
                            Text("\(weeklyMinutes) / \(weeklyGoal) min")
                                .foregroundColor(.secondary)
                        }
                        GradientProgress(value: Double(weeklyMinutes), total: Double(weeklyGoal))
                        HStack(spacing: 12) {
                            Button("Reset Week") { weeklyMinutes = 0 }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Measurements") {
                    Picker("Sex", selection: $sex) {
                        Text("Not set").tag("")
                        Text("Male").tag("M")
                        Text("Female").tag("F")
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("kg")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", value: $height, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("cm")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Walking Objective") {
                    Stepper("\(walkingObjective) min/day", value: $walkingObjective, in: 5...180, step: 5)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ProfileView()
}
