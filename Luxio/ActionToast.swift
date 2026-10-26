import SwiftUI

struct ActionToast: ViewModifier {
    @Binding var failure: ActionFailure?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let failure {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.title).font(.subheadline.weight(.semibold))
                        Text(failure.message).font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { self.failure = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                    }.buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                }
                .padding(16).foregroundStyle(.white)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)) }
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .padding(.horizontal, 16).padding(.bottom, 12)
                .frame(maxWidth: 560)
                .accessibilityElement(children: .contain).accessibilityIdentifier("action-toast")
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.2), value: failure?.id)
        .task(id: failure?.id) {
            guard let current = failure else { return }
            UIAccessibility.post(notification: .announcement, argument: "\(current.title). \(current.message)")
            do { try await Task.sleep(for: .seconds(max(0, 6 + current.createdAt.timeIntervalSinceNow))) } catch { return }
            if failure?.id == current.id { failure = nil }
        }
    }
}
