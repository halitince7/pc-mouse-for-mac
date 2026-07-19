import Cocoa
import CoreVideo

/// Turns a notched mouse wheel's chunky, line-by-line jumps into an animated,
/// pixel-based glide — much closer to a trackpad's smoothness.
///
/// Fluidity comes from five things:
///   1. A CVDisplayLink drives updates in sync with the display refresh (VSync),
///      so there's no timer jitter.
///   2. A time-constant ease-out (framerate-independent) gives a natural glide.
///   3. Sub-pixel carry keeps slow, tail-end motion perfectly smooth.
///   4. Acceleration: spinning faster travels disproportionately farther.
///   5. Momentum: after a genuine spin, the scroll coasts and settles under a
///      drag curve, the way a trackpad does after a flick.
///
/// Slow, deliberate scrolling stays 1:1 and never coasts, and any new notch (or
/// a flick the other way) cancels the glide immediately, so control is never
/// taken away from the user.
final class SmoothScroller {
    // Tag posted events so our own tap skips them (prevents infinite recursion).
    static let syntheticTag: Int64 = 0x5343524C // "SCRL"

    private let source = CGEventSource(stateID: .hidSystemState)
    private var link: CVDisplayLink?
    private let lock = NSLock()

    private var remainingY = 0.0     // distance left to travel (points)
    private var remainingX = 0.0
    private var carryY = 0.0         // sub-pixel remainder not yet emitted
    private var carryX = 0.0
    private var lastTime = 0.0
    private var lastTickTime = 0.0   // when the previous wheel notch arrived
    private var consecutiveFastTicks = 0

    // Momentum state (the trackpad-like coast after a flick).
    private var momentumActive = false
    private var velocityY = 0.0      // points per second
    private var velocityX = 0.0

    // Tuning.
    private let pixelsPerLine = 58.0 // base travel distance per wheel notch
    private let tau = 0.085          // smoothing time constant — bigger = longer, silkier glide

    // Acceleration: spinning the wheel faster travels disproportionately
    // farther, so long pages don't need endless flicking.
    private let maxAcceleration = 3.0 // multiplier at full speed
    private let fastTick = 0.03       // s between notches considered "fast"
    private let slowTick = 0.20       // s between notches considered "deliberate"

    // Momentum: after a genuine spin, keep coasting and decay under drag.
    // Gated so a notch or two never sends the page flying.
    //
    // Drag model: v'(t) = -a * v(t)^b   (a = coefficient, b = exponent)
    // With b < 1 the speed reaches zero in *finite* time, which settles far more
    // definitely than plain exponential decay (b = 1, which never truly stops
    // and has to be cut off at a threshold). b = 0.7 is what gives the
    // trackpad-like "lands and stays" feel.
    private let dragExponent = 0.7               // b — below 1 = finite, settled stop
    private let dragCoefficient = 55.0           // a — higher = shorter coast
    private let momentumTriggerVelocity = 1200.0 // pt/s needed to start coasting
    private let momentumStopVelocity = 40.0      // pt/s at which coasting ends
    private let momentumMaxVelocity = 5000.0     // safety cap
    private let momentumHandoffDelay = 0.05      // s of no notches before coasting
    private let momentumMinFastTicks = 3         // consecutive fast notches required

    init() {
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, inNow, _, _, _, ctx) -> CVReturn in
            Unmanaged<SmoothScroller>.fromOpaque(ctx!).takeUnretainedValue().frame(inNow.pointee)
            return kCVReturnSuccess
        }, ctx)
    }

    deinit {
        if let link = link { CVDisplayLinkStop(link) }
    }

    /// True if the event was synthesized by us (should pass through untouched).
    func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag
    }

    /// Queue a wheel notch. Line deltas are already sign-corrected for the
    /// desired final direction.
    func enqueue(lineDeltaY: Double, lineDeltaX: Double) {
        let now = CACurrentMediaTime()
        let gap = lastTickTime == 0 ? Double.infinity : now - lastTickTime
        lastTickTime = now

        lock.lock()

        // A new notch always takes over from a coast.
        momentumActive = false

        // Reversing direction: drop whatever is still queued the other way, so
        // flicking back feels immediate instead of fighting the old glide.
        var reversed = false
        if lineDeltaY != 0, (remainingY != 0 || velocityY != 0), (lineDeltaY > 0) != (remainingY + velocityY > 0) {
            remainingY = 0; carryY = 0; velocityY = 0; reversed = true
        }
        if lineDeltaX != 0, (remainingX != 0 || velocityX != 0), (lineDeltaX > 0) != (remainingX + velocityX > 0) {
            remainingX = 0; carryX = 0; velocityX = 0; reversed = true
        }

        // Count consecutive fast notches — momentum only earns its keep after a
        // real spin, not one stray flick.
        if reversed || !gap.isFinite || gap >= slowTick {
            consecutiveFastTicks = 1
        } else {
            consecutiveFastTicks += 1
        }

        // A reversal starts a new gesture, so don't carry speed into it.
        let distance = pixelsPerLine * (reversed ? 1 : accelerationMultiplier(gap: gap))
        remainingY += lineDeltaY * distance
        remainingX += lineDeltaX * distance

        lock.unlock()

        if let link = link, !CVDisplayLinkIsRunning(link) {
            lastTime = 0
            CVDisplayLinkStart(link)
        }
    }

    /// Maps the gap between notches to a distance multiplier. Squared so the
    /// boost only really kicks in when genuinely spinning, leaving slow,
    /// deliberate scrolling at 1:1.
    private func accelerationMultiplier(gap: Double) -> Double {
        guard gap.isFinite else { return 1 }
        let clamped = min(max(gap, fastTick), slowTick)
        let t = (slowTick - clamped) / (slowTick - fastTick) // 0 = slow, 1 = fast
        return 1 + (maxAcceleration - 1) * t * t
    }

    private func frame(_ now: CVTimeStamp) {
        let t = Double(now.videoTime) / Double(now.videoTimeScale)
        let wallClock = CACurrentMediaTime()

        lock.lock()
        // Framerate-independent step size via an exponential time constant.
        let dt = lastTime == 0 ? 1.0 / 60.0 : max(1.0 / 240.0, min(0.05, t - lastTime))
        lastTime = t

        var moveY = 0.0
        var moveX = 0.0

        if momentumActive {
            // Coasting: decay the speed under drag, keeping direction intact.
            let speed = (velocityY * velocityY + velocityX * velocityX).squareRoot()
            if speed > 0 {
                let k = 1 - dragExponent
                let newSpeed: Double
                if k > 0.0001 {
                    // Analytic solution — hits exactly zero at a finite time.
                    let base = pow(speed, k) - dragCoefficient * k * dt
                    newSpeed = base > 0 ? pow(base, 1 / k) : 0
                } else {
                    newSpeed = speed * exp(-dragCoefficient * dt) // b == 1 case
                }
                let scale = newSpeed / speed
                velocityY *= scale
                velocityX *= scale
            }
            moveY = velocityY * dt
            moveX = velocityX * dt
            if (velocityY * velocityY + velocityX * velocityX).squareRoot() < momentumStopVelocity {
                momentumActive = false
                velocityY = 0; velocityX = 0
            }
        } else {
            // Tracking: ease toward the distance the wheel has asked for.
            let factor = 1 - exp(-dt / tau)
            moveY = remainingY * factor
            moveX = remainingX * factor
            remainingY -= moveY
            remainingX -= moveX
            if abs(remainingY) < 0.1 { remainingY = 0 }
            if abs(remainingX) < 0.1 { remainingX = 0 }

            // Keep a smoothed estimate of how fast we're actually moving, so a
            // flick can hand off to momentum with the right speed.
            velocityY = velocityY * 0.7 + (moveY / dt) * 0.3
            velocityX = velocityX * 0.7 + (moveX / dt) * 0.3

            // Hand off to momentum once the wheel stops — but only after a real
            // spin, so slow, deliberate scrolling never coasts away.
            if wallClock - lastTickTime > momentumHandoffDelay,
               consecutiveFastTicks >= momentumMinFastTicks,
               abs(velocityY) > momentumTriggerVelocity || abs(velocityX) > momentumTriggerVelocity {
                momentumActive = true
                velocityY = min(max(velocityY, -momentumMaxVelocity), momentumMaxVelocity)
                velocityX = min(max(velocityX, -momentumMaxVelocity), momentumMaxVelocity)
                remainingY = 0; remainingX = 0
            }
        }

        // Sub-pixel carry: emit whole pixels, keep the fraction for next frame.
        let totalY = moveY + carryY
        let totalX = moveX + carryX
        let pxY = Int32(totalY.rounded(.towardZero))
        let pxX = Int32(totalX.rounded(.towardZero))
        carryY = totalY - Double(pxY)
        carryX = totalX - Double(pxX)

        let idle = !momentumActive && remainingY == 0 && remainingX == 0
        lock.unlock()

        if pxY != 0 || pxX != 0 {
            if let event = CGEvent(scrollWheelEvent2Source: source,
                                   units: .pixel, wheelCount: 2,
                                   wheel1: pxY, wheel2: pxX, wheel3: 0) {
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
                event.post(tap: .cgSessionEventTap)
            }
        }

        if idle { stopWhenIdle() }
    }

    /// Stop the display link once there's nothing left to animate. Done off the
    /// callback thread, and re-checked so a fresh notch doesn't get cut off.
    private func stopWhenIdle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let link = self.link else { return }
            self.lock.lock()
            let stillIdle = !self.momentumActive && self.remainingY == 0 && self.remainingX == 0
            self.lock.unlock()
            if stillIdle && CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStop(link)
                self.carryY = 0; self.carryX = 0
                self.velocityY = 0; self.velocityX = 0
            }
        }
    }
}
