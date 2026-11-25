// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Machine-readable Web eID error codes understood by `web-eid.js`.
public enum WebEidErrorCode: String, Codable, Equatable, Sendable {
  case actionPending = "ERR_WEBEID_ACTION_PENDING"
  case actionTimeout = "ERR_WEBEID_ACTION_TIMEOUT"
  case contextInsecure = "ERR_WEBEID_CONTEXT_INSECURE"
  case missingParameter = "ERR_WEBEID_MISSING_PARAMETER"
  case nativeFatal = "ERR_WEBEID_NATIVE_FATAL"
  case nativeInvalidArgument = "ERR_WEBEID_NATIVE_INVALID_ARGUMENT"
  case nativeUnavailable = "ERR_WEBEID_NATIVE_UNAVAILABLE"
  case unknownError = "ERR_WEBEID_UNKNOWN_ERROR"
  case userCancelled = "ERR_WEBEID_USER_CANCELLED"
  case userTimeout = "ERR_WEBEID_USER_TIMEOUT"
}
