import SwiftUI
import UIKit

// A custom-sized back button hides UIKit's default item. Keep its interactive
// pop transition enabled, and restore the delegate when this screen disappears.
struct InteractiveBackGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restoreGesture()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var navigation: UINavigationController?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var previouslyEnabled = false

        override func loadView() {
            view = UIView(); view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigation = navigationController,
                  let gesture = navigation.interactivePopGestureRecognizer,
                  navigation.viewControllers.count > 1 else { return }
            if gesture.delegate !== self {
                self.navigation = navigation; previousDelegate = gesture.delegate
                previouslyEnabled = gesture.isEnabled; gesture.delegate = self
            }
            gesture.isEnabled = true
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation else { return false }
            return navigation.viewControllers.count > 1
                && navigation.transitionCoordinator == nil
                && navigation.presentedViewController == nil
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated); restoreGesture()
        }
        func restoreGesture() {
            guard let gesture = navigation?.interactivePopGestureRecognizer,
                  gesture.delegate === self else { return }
            gesture.delegate = previousDelegate; gesture.isEnabled = previouslyEnabled
            navigation = nil; previousDelegate = nil
        }
    }
}
