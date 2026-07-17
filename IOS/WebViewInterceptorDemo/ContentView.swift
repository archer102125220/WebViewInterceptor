import SwiftUI

struct ContentView: View {
    var body: some View {
        ViewControllerWrapper()
            .edgesIgnoringSafeArea(.all)
    }
}

// 這個 Wrapper 讓我們可以在 SwiftUI 中直接顯示 UIKit 的 ViewController
struct ViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        // 不需要更新
    }
}

#Preview {
    ContentView()
}

