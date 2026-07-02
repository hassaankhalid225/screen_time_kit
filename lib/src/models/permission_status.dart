/// The authorization state for screen-time / usage-access features.
///
/// This is a *unified* enum: it maps Android's usage-access app-op state and
/// iOS `FamilyControls` `AuthorizationStatus` onto one set of values so host
/// apps can write a single branch of permission-handling code.
enum PermissionStatus {
  /// The user has granted access. Usage stats and (on iOS) app limits work.
  granted,

  /// The user actively denied access, or usage access is toggled off.
  denied,

  /// The user has not yet been asked / has not made a choice.
  ///
  /// On iOS this is `AuthorizationStatus.notDetermined`. On Android there is no
  /// true "not determined" state for usage access, so the platform reports
  /// [denied] instead — treat [notDetermined] as an iOS-first value.
  notDetermined,

  /// Access is blocked by a policy outside the user's control — for example an
  /// MDM profile or Screen Time restrictions on iOS.
  restricted;

  /// Parses the string sent across the platform channel into a value.
  ///
  /// Falls back to [PermissionStatus.denied] for any unrecognised input so a
  /// misbehaving platform can never crash the Dart side.
  static PermissionStatus fromName(String? name) {
    switch (name) {
      case 'granted':
        return PermissionStatus.granted;
      case 'notDetermined':
        return PermissionStatus.notDetermined;
      case 'restricted':
        return PermissionStatus.restricted;
      case 'denied':
      default:
        return PermissionStatus.denied;
    }
  }

  /// Whether this status allows reading usage data / applying limits.
  bool get isGranted => this == PermissionStatus.granted;
}
