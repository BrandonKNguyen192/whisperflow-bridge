import SwiftUI
import UIKit
import CoreMotion
import WhisperBridgeCore

/// Gyroscope-driven air mouse — mirrors the Android implementation:
/// rotation rates become smoothed pixel velocities, drained at ~30 Hz into
/// `/control` move deltas. Lives in an ObservableObject so it survives view
/// recomputes for the whole hold.
final class AirMouseEngine: ObservableObject {
    @Published private(set) var isActive = false

    private let manager = CMMotionManager()
    private var ticker: Timer?
    private var vx = 0.0
    private var vy = 0.0
    private var send: ((Int, Int) -> Void)?

    var isAvailable: Bool { manager.isGyroAvailable }

    func start(sensitivity: Int, invert: Bool, send: @escaping (Int, Int) -> Void) {
        guard !isActive, manager.isGyroAvailable else { return }
        self.send = send
        vx = 0
        vy = 0
        let sens = Double(sensitivity) / 5.0
        let pxPerRad = 1100.0 * sens * (invert ? -1.0 : 1.0)
        let dead = 0.04

        manager.gyroUpdateInterval = 1.0 / 60.0
        manager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let wx = data.rotationRate.x
            let wy = data.rotationRate.y
            let rawX = abs(wx) > dead ? wx : 0
            let rawY = abs(wy) > dead ? wy : 0
            let targetVx = -rawY * pxPerRad
            let targetVy = -rawX * pxPerRad
            let alpha = 0.12
            vx += (targetVx - vx) * alpha
            vy += (targetVy - vy) * alpha
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let dx = Int((vx / 30.0).rounded())
            let dy = Int((vy / 30.0).rounded())
            if dx != 0 || dy != 0 {
                self.send?(dx, dy)
            }
        }
        isActive = true
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        manager.stopGyroUpdates()
        send = nil
        vx = 0
        vy = 0
        isActive = false
    }
}

struct TrackpadView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var theme: ThemeStore

    @AppStorage("trackpad_speed") private var speed = 5
    @AppStorage("tap_to_click") private var tapToClick = false
    @AppStorage("natural_scroll") private var naturalScroll = false
    @AppStorage("air_sens") private var airSens = 5
    @AppStorage("air_invert") private var airInvert = false

    @StateObject private var airMouse = AirMouseEngine()

    let onStatus: (String, Bool) -> Void

    @State private var lastMoveSend = Date.distantPast
    @State private var lastTranslation = CGSize.zero
    @State private var dragStartTime: Date?
    @State private var dragHeld = false
    @State private var touchPoint: CGPoint?
    @State private var pressedButton: String?

    private var palette: AppPalette { AppPalette.palette(for: theme.mode) }
    private var accent: Color { Color(hex: theme.accentHex) }
    private var moveScale: CGFloat { CGFloat(speed) / 5.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TRACKPAD")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Drag to move · hold to drag · tap to click")
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
            }

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .overlay(
                    ZStack {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(accent.opacity(0.45))
                            .opacity(touchPoint == nil ? 1 : 0)
                        if let touchPoint {
                            Circle()
                                .fill(accent.opacity(0.35))
                                .frame(width: 64, height: 64)
                                .blur(radius: 14)
                                .position(touchPoint)
                            Circle()
                                .fill(accent.opacity(0.7))
                                .frame(width: 14, height: 14)
                                .position(touchPoint)
                        }
                    }
                )
                .frame(height: 220)
                .contentShape(Rectangle())
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .gesture(padGesture)
                .animation(.easeOut(duration: 0.25), value: touchPoint == nil)

            HStack(spacing: 8) {
                mouseButton("Click", icon: "hand.tap", action: "click", button: "left")
                mouseButton("Right", icon: "cursorarrow.click", action: "click", button: "right")
                mouseButton("Double", icon: "cursorarrow.click.2", action: "double_click", button: "left")
                mouseButton("Up", icon: "arrow.up", action: "scroll", dy: naturalScroll ? -90 : 90)
                mouseButton("Down", icon: "arrow.down", action: "scroll", dy: naturalScroll ? 90 : -90)
            }

            airMouseButton
        }
        .padding(20)
        .glassCard()
        .onDisappear { airMouse.stop() }
    }

    private var airMouseButton: some View {
        HStack(spacing: 8) {
            Image(systemName: airMouse.isActive ? "gyroscope" : "cursorarrow.motionlines")
                .symbolEffect(.pulse, options: .repeating, value: airMouse.isActive)
            Text(airMouse.isActive ? "Air mouse active — tilt to move" : "Hold for air mouse")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassEffect(
            (airMouse.isActive ? Glass.regular.tint(accent.opacity(0.35)) : .regular).interactive(),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onLongPressGesture(
            minimumDuration: 0.05,
            maximumDistance: 60,
            pressing: { pressing in
                if pressing {
                    startAirMouse()
                } else {
                    stopAirMouse()
                }
            },
            perform: {}
        )
    }

    private var padGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                touchPoint = value.location
                if dragStartTime == nil {
                    dragStartTime = Date()
                    lastTranslation = .zero
                }
                let dx = (value.translation.width - lastTranslation.width) / moveScale
                let dy = (value.translation.height - lastTranslation.height) / moveScale
                lastTranslation = value.translation
                sendControl(action: "move", dx: Int(dx.rounded()), dy: Int(dy.rounded()))
                if !dragHeld && Date().timeIntervalSince(dragStartTime ?? Date()) > 0.4 {
                    dragHeld = true
                    sendControl(action: "down")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { value in
                touchPoint = nil
                let duration = Date().timeIntervalSince(dragStartTime ?? Date())
                let moved = hypot(value.translation.width, value.translation.height)
                if dragHeld {
                    sendControl(action: "up")
                } else if moved < (tapToClick ? 14 : 8) && duration < 0.35 {
                    sendControl(action: "click")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                dragStartTime = nil
                lastTranslation = .zero
                dragHeld = false
            }
    }

    private func mouseButton(
        _ title: String,
        icon: String,
        action: String,
        button: String = "left",
        dy: Int = 0
    ) -> some View {
        Button {
            sendControl(action: action, dy: dy, button: button)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(Motion.pop) {
                pressedButton = title
            }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                if pressedButton == title { pressedButton = nil }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .symbolEffect(.bounce, value: pressedButton == title)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(pressedButton == title ? accent : palette.textPrimary)
    }

    private func startAirMouse() {
        airMouse.start(sensitivity: airSens, invert: airInvert) { dx, dy in
            self.sendControl(action: "move", dx: dx, dy: dy)
        }
        // No status flash here: it would recompute the parent and cancel the
        // hold gesture. The button's label + haptic are the feedback.
        if airMouse.isActive {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            onStatus("Gyro not available on this device", true)
        }
    }

    private func stopAirMouse() {
        guard airMouse.isActive else { return }
        airMouse.stop()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onStatus("Air mouse off", true)
    }

    private func sendControl(
        action: String,
        dx: Int = 0,
        dy: Int = 0,
        button: String = "left"
    ) {
        guard let profile = profiles.active, !profile.host.isEmpty else {
            onStatus("Configure a host first", true)
            return
        }
        if action == "move" {
            let now = Date()
            guard now.timeIntervalSince(lastMoveSend) >= 0.033 else { return }
            lastMoveSend = now
        }
        Task {
            let result = await BridgeClient.live.control(
                host: profile.host,
                port: profile.port,
                action: action,
                dx: dx,
                dy: dy,
                button: button,
                token: profile.token
            )
            if !result.ok {
                onStatus(result.message, true)
            }
        }
    }
}
