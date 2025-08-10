import SwiftUI

struct WelcomeView: View {
    @AppStorage("profile.sex") private var sexe: String = ""
    @AppStorage("profile.weight") private var weight: Double = 0
    @AppStorage("profile.height") private var height: Double = 0
    @State private var showMainApp = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Hi! Welcome to Healthy Ways")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 20) {
                TextField("Sex (M/F/Other)", text: $sexe)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.default)
                    .autocapitalization(.allCharacters)
                HStack {
                    TextField("Weight", value: $weight, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                    Text("kg").foregroundColor(.secondary)
                }
                HStack {
                    TextField("Height", value: $height, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                    Text("cm").foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            Button(action: {
                showMainApp = true
            }) {
                Text("Open")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 40)
            .fullScreenCover(isPresented: $showMainApp) {
                ContentView()
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

#Preview {
    WelcomeView()
}
