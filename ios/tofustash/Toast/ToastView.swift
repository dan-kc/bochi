import SwiftUI

// A single toast notification bar with message, action button, countdown,
// and close button. Supports swipe-to-dismiss.
//
// In React terms, this is a controlled component — all state (message,
// remaining seconds) comes from props, and callbacks (onAction, onDismiss)
// bubble events up to the parent.
struct ToastView: View {
    let toast: ToastItem
    let remainingSeconds: Int
    let onAction: () -> Void
    let onDismiss: () -> Void

    // Tracks the horizontal drag offset for swipe-to-dismiss.
    // Like a useState for translateX in a React drag handler.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            // Action button (e.g. "Recover") — tapping this triggers recovery.
            Button(toast.actionLabel) {
                onAction()
            }
            .font(.subheadline.weight(.semibold))

            // Close button with countdown — shows remaining seconds inside.
            // Tapping dismisses the toast immediately.
            Button {
                onDismiss()
            } label: {
                Text("\(remainingSeconds)")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 24, height: 24)
                    .background(.secondary.opacity(0.3), in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        // Horizontal offset follows the user's drag gesture.
        .offset(x: dragOffset)
        .gesture(
            // DragGesture tracks the finger's movement — like onTouchMove in React.
            // .onChanged updates the offset in real-time (live dragging).
            // .onEnded checks if the user dragged far enough to dismiss.
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    // If the user dragged more than 100pt in either direction,
                    // dismiss the toast. Otherwise, snap back to center.
                    // Like checking if deltaX > threshold in a React swipe handler.
                    if abs(value.translation.width) > 100 {
                        // Animate the toast off-screen in the swipe direction,
                        // then dismiss it from the data model.
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = value.translation.width > 0 ? 400 : -400
                        }
                        // Delay dismissal so the exit animation plays first.
                        // Like setTimeout(() => onDismiss(), 200) in React.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        // Snap back to center with a spring animation.
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

// Overlay that renders a stack of toasts at the bottom of the screen.
// Each toast is independently swipeable and actionable.
//
// In React terms, this is like a <ToastContainer /> that maps over
// an array of toast items and renders each one.
struct ToastOverlay: View {
    let toastManager: ToastManager

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            // ForEach renders one ToastView per active toast.
            // Toasts stack vertically — newest at the bottom (append order).
            ForEach(toastManager.toasts) { toast in
                ToastView(
                    toast: toast,
                    remainingSeconds: toastManager.remainingSeconds[toast.id] ?? 0,
                    onAction: { toastManager.performAction(toast.id) },
                    onDismiss: { toastManager.dismiss(toast.id) }
                )
                // Slide in from the bottom when appearing, slide out when removed.
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        // Animate insertions and removals of toasts in the ForEach.
        .animation(.spring(duration: 0.3), value: toastManager.toasts.map(\.id))
    }
}
