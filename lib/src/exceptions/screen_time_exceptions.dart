import 'package:flutter/services.dart';

/// Base class for every error surfaced by `screen_time_kit`.
///
/// All native failures are mapped onto one of the typed subclasses below so
/// host apps can `catch` a specific case instead of parsing raw
/// [PlatformException] codes.
sealed class ScreenTimeException implements Exception {
  /// Creates a [ScreenTimeException].
  const ScreenTimeException(this.message, [this.details]);

  /// Human-readable description of what went wrong.
  final String message;

  /// Optional platform-provided detail payload.
  final Object? details;

  @override
  String toString() => '$runtimeType: $message';

  /// Maps a raw [PlatformException] to the matching typed exception.
  ///
  /// The native side signals intent through the exception `code`. Anything
  /// unrecognised becomes an [UnknownScreenTimeException] so callers still get a
  /// typed error.
  static ScreenTimeException fromPlatform(PlatformException e) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return PermissionDeniedException(
          e.message ?? 'Usage-access permission has not been granted.',
          e.details,
        );
      case 'UNSUPPORTED':
      case 'PLATFORM_NOT_SUPPORTED':
        return PlatformNotSupportedException(
          e.message ?? 'This feature is not supported on the current platform.',
          e.details,
        );
      case 'ENTITLEMENT_MISSING':
        return EntitlementMissingException(
          e.message ?? 'The required Family Controls entitlement is missing.',
          e.details,
        );
      default:
        return UnknownScreenTimeException(
          e.message ?? 'An unknown screen-time error occurred (${e.code}).',
          e.details,
        );
    }
  }
}

/// Thrown when a call needs usage access / Family Controls authorization that
/// the user has not granted.
final class PermissionDeniedException extends ScreenTimeException {
  /// Creates a [PermissionDeniedException].
  const PermissionDeniedException(super.message, [super.details]);
}

/// Thrown when a feature is unavailable on the current platform or OS version
/// (for example calling an iOS-only shield API on Android).
final class PlatformNotSupportedException extends ScreenTimeException {
  /// Creates a [PlatformNotSupportedException].
  const PlatformNotSupportedException(super.message, [super.details]);
}

/// iOS-specific. Thrown when the Family Controls capability/entitlement is not
/// present in the running build — for example a release build submitted to the
/// App Store without Apple's Family Controls Distribution Entitlement.
final class EntitlementMissingException extends ScreenTimeException {
  /// Creates an [EntitlementMissingException].
  const EntitlementMissingException(super.message, [super.details]);
}

/// Fallback for any native error without a recognised code.
final class UnknownScreenTimeException extends ScreenTimeException {
  /// Creates an [UnknownScreenTimeException].
  const UnknownScreenTimeException(super.message, [super.details]);
}
