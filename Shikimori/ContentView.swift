import SwiftUI

// Тестовый экран этапа 2: проверяем, что сборка, подпись и установка работают,
// а эффект Liquid Glass (iOS 26+) отображается.
struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                Text("Shikimori")
                    .font(.largeTitle.bold())
                Text("Тестовая сборка 0.0.1")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}

#Preview {
    ContentView()
}
