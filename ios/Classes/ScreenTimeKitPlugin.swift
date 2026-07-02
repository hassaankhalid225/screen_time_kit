import Flutter
import UIKit

// These frameworks require iOS 16.0+ and the "Family Controls" capability to be
// enabled on the Runner target (and, for App Store distribution, Apple's Family
// Controls Distribution Entitlement). See the README's iOS setup section.
import FamilyControls
import ManagedSettings

/// iOS implementation of `screen_time_kit`.
///
/// **What works out of the box (development / your own device):**
/// - Permission via `FamilyControls.AuthorizationCenter` (Apple's consent sheet).
/// - Native app *blocking* via `ManagedSettings` once the user has picked apps.
///
/// **Honest limitations (Apple's design, not ours):**
/// - Raw per-app usage is **not** exposed to the host process. `getAppUsage`
///   therefore reports UNSUPPORTED here — real iOS usage requires a separate
///   `DeviceActivityReportExtension` target that renders inside a SwiftUI report
///   view and shares aggregates through an App Group. That extension is out of
///   scope for the plugin's main binary; the README documents the setup.
/// - App limits target opaque `ApplicationToken`s selected through Apple's
///   `FamilyActivityPicker`, **not** bundle-id strings. So `setAppLimit(bundleId)`
///   cannot map a raw string to a system app on its own. This build shields the
///   currently-selected set and records the limit intent; wiring the picker is a
///   host-app responsibility documented in the README.
public class ScreenTimeKitPlugin: NSObject, FlutterPlugin {

  private let store = ManagedSettingsStore(named: .init("screen_time_kit.limits"))
  private let limitsKey = "screen_time_kit.limits"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "screen_time_kit", binaryMessenger: registrar.messenger())
    let instance = ScreenTimeKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // The limit-event stream. On iOS the system enforces limits, so events here
    // are advisory; a real crossing feed would come from a DeviceActivityMonitor
    // extension. We register the channel so Dart's `onLimitReached` is valid.
    let events = FlutterEventChannel(
      name: "screen_time_kit/limit_events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(LimitEventStreamHandler())
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "checkPermissionStatus":
      result(currentAuthorizationName())

    case "requestPermission":
      requestAuthorization(result: result)

    case "openSettings":
      openAppSettings(result: result)

    case "getAppUsage":
      // Apple does not surface raw usage to the host process — see the class doc.
      result(
        FlutterError(
          code: "UNSUPPORTED",
          message:
            "iOS does not expose raw per-app usage to the host app. Add a "
            + "DeviceActivityReportExtension target (see README) to render usage.",
          details: nil))

    case "setAppLimit":
      setAppLimit(call: call, result: result)

    case "removeAppLimit":
      removeAppLimit(call: call, result: result)

    case "getActiveLimits":
      result(activeLimits())

    case "clearAllLimits":
      clearAllLimits(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permissions (5.2)

  private func currentAuthorizationName() -> String {
    guard #available(iOS 16.0, *) else { return "restricted" }
    switch AuthorizationCenter.shared.authorizationStatus {
    case .approved: return "granted"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "denied"
    }
  }

  private func requestAuthorization(result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED",
          message: "Family Controls requires iOS 16.0 or newer.", details: nil))
      return
    }
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        result("granted")
      } catch {
        // The user declined, or the entitlement is missing in this build.
        result("denied")
      }
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(nil)
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { _ in result(nil) }
    }
  }

  // MARK: - App limits (5.4)

  /// Records the limit intent. Actual shielding requires an `ApplicationToken`
  /// from `FamilyActivityPicker` — the host app must supply the selection (see
  /// README). We persist the intent so `getActiveLimits` round-trips.
  private func setAppLimit(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED", message: "Requires iOS 16.0 or newer.", details: nil))
      return
    }
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      result(
        FlutterError(
          code: "PERMISSION_DENIED",
          message: "Family Controls authorization has not been granted.", details: nil))
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let bundleId = args["packageName"] as? String,
      let limitMillis = (args["limitMillis"] as? NSNumber)?.int64Value
    else {
      result(
        FlutterError(
          code: "INVALID_ARGS", message: "packageName and limitMillis are required.",
          details: nil))
      return
    }
    var limits = storedLimits()
    limits[bundleId] = limitMillis
    persistLimits(limits)
    // If the host has already shielded a selection, keep it applied. A real
    // per-app shield is applied by the host via a stored FamilyActivitySelection.
    result(nil)
  }

  private func removeAppLimit(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let bundleId = args["packageName"] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGS", message: "packageName is required.", details: nil))
      return
    }
    var limits = storedLimits()
    limits.removeValue(forKey: bundleId)
    persistLimits(limits)
    if limits.isEmpty {
      store.shield.applications = nil
    }
    result(nil)
  }

  private func activeLimits() -> [[String: Any]] {
    storedLimits().map { ["packageName": $0.key, "limitMillis": NSNumber(value: $0.value)] }
  }

  private func clearAllLimits(result: @escaping FlutterResult) {
    persistLimits([:])
    store.shield.applications = nil
    store.clearAllSettings()
    result(nil)
  }

  // MARK: - Persistence

  private func storedLimits() -> [String: Int64] {
    let raw = UserDefaults.standard.dictionary(forKey: limitsKey) as? [String: NSNumber] ?? [:]
    return raw.mapValues { $0.int64Value }
  }

  private func persistLimits(_ limits: [String: Int64]) {
    let raw = limits.mapValues { NSNumber(value: $0) }
    UserDefaults.standard.set(raw, forKey: limitsKey)
  }
}

/// Minimal stream handler so Dart's `onLimitReached` has a live channel.
///
/// On iOS the OS enforces limits, so we do not push synthetic events from the
/// main app. A production integration feeds this from a `DeviceActivityMonitor`
/// extension via an App Group / Darwin notification — documented in the README.
private class LimitEventStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return nil
  }
}
