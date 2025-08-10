import SwiftUI

struct WelcomeView: View {
    @State private var sexe: String = ""
    @State private var weight: String = ""
    @State private var height: String = ""
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
                TextField("Sexe (M/F)", text: $sexe)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.default)
                    .autocapitalization(.allCharacters)
                TextField("Weight (kg)", text: $weight)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
                TextField("Height (cm)", text: $height)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
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
