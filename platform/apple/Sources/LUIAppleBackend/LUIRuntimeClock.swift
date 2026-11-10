import Darwin
import Foundation

/// Drives the OCaml application clock (`Lui_ui.after` / `Lui_ui.every`) for
/// a native host. Call `reschedule()` on the runtime's thread after starting
/// the runtime and after every call into it, because any call may schedule,
/// cancel, pause or fire timers. A single main-queue wakeup is armed for the
/// next deadline; it ticks the clock with monotonic milliseconds and
/// rearms itself.
@MainActor
public final class LUIRuntimeClock {
  public typealias Tick = (Double) -> Int32
  public typealias NextDelay = () -> Double

  private let tick: Tick?
  private let nextDelay: NextDelay?
  private var wakeup: DispatchWorkItem?

  /// Libraries built before the application clock pass `nil` for both
  /// functions; the driver then never schedules anything.
  public init(tick: Tick?, nextDelay: NextDelay?) {
    if let tick, let nextDelay {
      self.tick = tick
      self.nextDelay = nextDelay
    } else {
      self.tick = nil
      self.nextDelay = nil
    }
  }

  /// Resolves `lui_ocaml_clock_tick` and `lui_ocaml_clock_next_delay` from a
  /// `dlopen` handle.
  public convenience init(library handle: UnsafeMutableRawPointer) {
    typealias TickFunction = @convention(c) (Double) -> Int32
    typealias DelayFunction = @convention(c) () -> Double
    let tick = dlsym(handle, "lui_ocaml_clock_tick").map {
      unsafeBitCast($0, to: TickFunction.self)
    }
    let delay = dlsym(handle, "lui_ocaml_clock_next_delay").map {
      unsafeBitCast($0, to: DelayFunction.self)
    }
    self.init(
      tick: tick.map { function in { function($0) } },
      nextDelay: delay.map { function in { function() } })
  }

  /// Checks each tick's result, so a timer action that raises is reported
  /// and resynced like a refused event.
  public var recovery: LUINativeRefusalRecovery?

  public var isAvailable: Bool { tick != nil }

  /// Milliseconds on the monotonic clock the wakeups use.
  public static var now: Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
  }

  public func reschedule() {
    cancel()
    guard let nextDelay else { return }
    let delay = nextDelay()
    guard delay >= 0 else { return }
    let wakeup = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.fire() }
    }
    self.wakeup = wakeup
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .microseconds(Int((delay * 1000).rounded(.up))), execute: wakeup)
  }

  /// Stops driving the clock, e.g. before stopping the runtime.
  public func cancel() {
    wakeup?.cancel()
    wakeup = nil
  }

  private func fire() {
    wakeup = nil
    let accepted = tick?(Self.now)
    recovery?.check(accepted)
    reschedule()
  }
}
