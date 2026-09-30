// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#import "ObjCExceptionGuard.h"

NSException *_Nullable CardCoreCatchException(void (NS_NOESCAPE ^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return exception;
  }
  return nil;
}

#if TARGET_OS_OSX
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
OSStatus CardCoreDeleteKeychainItemRef(CFDictionaryRef query) {
  NSMutableDictionary *refQuery = [(__bridge NSDictionary *)query mutableCopy];
  refQuery[(__bridge NSString *)kSecReturnRef] = @YES;
  CFTypeRef refOutput = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)refQuery, &refOutput);
  if (status != errSecSuccess || !refOutput) {
    return errSecItemNotFound;
  }
  if (CFGetTypeID(refOutput) != SecKeychainItemGetTypeID()) {
    CFRelease(refOutput);
    return errSecItemNotFound;
  }
  OSStatus deleteStatus = SecKeychainItemDelete((SecKeychainItemRef)refOutput);
  CFRelease(refOutput);
  return deleteStatus;
}
#pragma clang diagnostic pop
#endif
