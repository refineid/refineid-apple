// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Cryptoki.h -- minimal PKCS#11 v3.2 ABI subset for the RefineID bridge.
//
// Hand-written against the OASIS standard "PKCS #11 Specification
// Version 3.2" and the header material it normatively defines
// (pkcs11t.h types and constants, pkcs11f.h function prototypes,
// pkcs11.h function-list structures). Verified against the official
// include files at
// https://docs.oasis-open.org/pkcs11/pkcs11-spec/v3.2/os/include/pkcs11-v3.2/
// (and the v2.40 errata01/os includes for the legacy surface) -- every
// constant value, every structure member list, the function-list member
// orders, and all prototype signatures compare identical. Unix ABI:
// CK_ULONG is unsigned long and structures use default alignment (the
// 1-byte packing requirement applies to Windows only). Only what the
// bridge implements or must carry in the function lists is declared
// here.

#ifndef REFINEID_CRYPTOKI_H
#define REFINEID_CRYPTOKI_H

// The Cryptoki version this module implements, used in compile-time
// constant initializers (object-like macros, as in the OASIS headers,
// because C static initializers cannot reference const objects).
#define CRYPTOKI_VERSION_MAJOR 3
#define CRYPTOKI_VERSION_MINOR 2
#define CRYPTOKI_VERSION_AMENDMENT 0

// The version the legacy CK_FUNCTION_LIST must carry: spec section on
// C_GetFunctionList requires major 0x02, minor 0x28 (2.40) there, with
// the current list published through C_GetInterfaceList/C_GetInterface.
#define CRYPTOKI_LEGACY_VERSION_MAJOR 2
#define CRYPTOKI_LEGACY_VERSION_MINOR 40

// -- Basic types (pkcs11t.h) --

typedef unsigned char CK_BYTE;
typedef CK_BYTE CK_CHAR;
typedef CK_BYTE CK_UTF8CHAR;
typedef CK_BYTE CK_BBOOL;
typedef unsigned long CK_ULONG;
typedef CK_ULONG CK_RV;
typedef CK_ULONG CK_FLAGS;
typedef CK_ULONG CK_SLOT_ID;
typedef CK_ULONG CK_SESSION_HANDLE;
typedef CK_ULONG CK_OBJECT_HANDLE;
typedef CK_ULONG CK_USER_TYPE;
typedef CK_ULONG CK_STATE;
typedef CK_ULONG CK_NOTIFICATION;
typedef CK_ULONG CK_MECHANISM_TYPE;
typedef CK_ULONG CK_ATTRIBUTE_TYPE;
typedef CK_ULONG CK_SESSION_VALIDATION_FLAGS_TYPE;
typedef CK_ULONG CK_OBJECT_CLASS;
typedef CK_ULONG CK_CERTIFICATE_TYPE;
typedef CK_ULONG CK_KEY_TYPE;

typedef void *CK_VOID_PTR;
typedef CK_VOID_PTR *CK_VOID_PTR_PTR;
typedef CK_BYTE *CK_BYTE_PTR;
typedef CK_UTF8CHAR *CK_UTF8CHAR_PTR;
typedef CK_ULONG *CK_ULONG_PTR;
typedef CK_SLOT_ID *CK_SLOT_ID_PTR;
typedef CK_SESSION_HANDLE *CK_SESSION_HANDLE_PTR;
typedef CK_OBJECT_HANDLE *CK_OBJECT_HANDLE_PTR;
typedef CK_MECHANISM_TYPE *CK_MECHANISM_TYPE_PTR;
typedef CK_FLAGS *CK_FLAGS_PTR;

// -- Boolean values --

static const CK_BBOOL CK_FALSE = 0;
static const CK_BBOOL CK_TRUE = 1;

// -- Special values --

static const CK_ULONG CK_INVALID_HANDLE = 0;
static const CK_ULONG CK_EFFECTIVELY_INFINITE = 0;
static const CK_ULONG CK_UNAVAILABLE_INFORMATION = ~(CK_ULONG)0;

// -- Object classes, certificate types, key types --

static const CK_OBJECT_CLASS CKO_CERTIFICATE = 0x00000001;
static const CK_OBJECT_CLASS CKO_PUBLIC_KEY = 0x00000002;
static const CK_OBJECT_CLASS CKO_PRIVATE_KEY = 0x00000003;

static const CK_CERTIFICATE_TYPE CKC_X_509 = 0x00000000;

static const CK_KEY_TYPE CKK_RSA = 0x00000000;
static const CK_KEY_TYPE CKK_EC = 0x00000003;

// -- Attribute types used by the bridge (pkcs11t.h CKA_*) --

static const CK_ATTRIBUTE_TYPE CKA_CLASS = 0x00000000;
static const CK_ATTRIBUTE_TYPE CKA_TOKEN = 0x00000001;
static const CK_ATTRIBUTE_TYPE CKA_PRIVATE = 0x00000002;
static const CK_ATTRIBUTE_TYPE CKA_LABEL = 0x00000003;
static const CK_ATTRIBUTE_TYPE CKA_VALUE = 0x00000011;
static const CK_ATTRIBUTE_TYPE CKA_CERTIFICATE_TYPE = 0x00000080;
static const CK_ATTRIBUTE_TYPE CKA_ISSUER = 0x00000081;
static const CK_ATTRIBUTE_TYPE CKA_SERIAL_NUMBER = 0x00000082;
static const CK_ATTRIBUTE_TYPE CKA_KEY_TYPE = 0x00000100;
static const CK_ATTRIBUTE_TYPE CKA_SUBJECT = 0x00000101;
static const CK_ATTRIBUTE_TYPE CKA_ID = 0x00000102;
static const CK_ATTRIBUTE_TYPE CKA_SENSITIVE = 0x00000103;
static const CK_ATTRIBUTE_TYPE CKA_SIGN = 0x00000108;
static const CK_ATTRIBUTE_TYPE CKA_VERIFY = 0x0000010A;
static const CK_ATTRIBUTE_TYPE CKA_EXTRACTABLE = 0x00000162;
static const CK_ATTRIBUTE_TYPE CKA_LOCAL = 0x00000163;
static const CK_ATTRIBUTE_TYPE CKA_NEVER_EXTRACTABLE = 0x00000164;
static const CK_ATTRIBUTE_TYPE CKA_ALWAYS_SENSITIVE = 0x00000165;
static const CK_ATTRIBUTE_TYPE CKA_MODIFIABLE = 0x00000170;
static const CK_ATTRIBUTE_TYPE CKA_MODULUS = 0x00000120;
static const CK_ATTRIBUTE_TYPE CKA_MODULUS_BITS = 0x00000121;
static const CK_ATTRIBUTE_TYPE CKA_PUBLIC_EXPONENT = 0x00000122;
static const CK_ATTRIBUTE_TYPE CKA_EC_PARAMS = 0x00000180;
static const CK_ATTRIBUTE_TYPE CKA_EC_POINT = 0x00000181;
static const CK_ATTRIBUTE_TYPE CKA_ALWAYS_AUTHENTICATE = 0x00000202;

// -- Mechanisms and mechanism-info flags used by the bridge --

static const CK_MECHANISM_TYPE CKM_RSA_PKCS = 0x00000001;
static const CK_MECHANISM_TYPE CKM_ECDSA = 0x00001041;

static const CK_FLAGS CKF_HW = 0x00000001;
static const CK_FLAGS CKF_SIGN = 0x00000800;

// -- Session flags, states, and user types --

static const CK_FLAGS CKF_RW_SESSION = 0x00000002;
static const CK_FLAGS CKF_SERIAL_SESSION = 0x00000004;

static const CK_STATE CKS_RO_PUBLIC_SESSION = 0;
static const CK_STATE CKS_RO_USER_FUNCTIONS = 1;

static const CK_USER_TYPE CKU_SO = 0;
static const CK_USER_TYPE CKU_USER = 1;

// -- Return values used by the bridge (pkcs11t.h CKR_*) --

static const CK_RV CKR_OK = 0x00000000;
static const CK_RV CKR_SLOT_ID_INVALID = 0x00000003;
static const CK_RV CKR_GENERAL_ERROR = 0x00000005;
static const CK_RV CKR_FUNCTION_FAILED = 0x00000006;
static const CK_RV CKR_ARGUMENTS_BAD = 0x00000007;
static const CK_RV CKR_ATTRIBUTE_TYPE_INVALID = 0x00000012;
static const CK_RV CKR_DATA_INVALID = 0x00000020;
static const CK_RV CKR_DATA_LEN_RANGE = 0x00000021;
static const CK_RV CKR_DEVICE_ERROR = 0x00000030;
static const CK_RV CKR_FUNCTION_CANCELED = 0x00000050;
static const CK_RV CKR_FUNCTION_NOT_PARALLEL = 0x00000051;
static const CK_RV CKR_FUNCTION_NOT_SUPPORTED = 0x00000054;
static const CK_RV CKR_KEY_HANDLE_INVALID = 0x00000060;
static const CK_RV CKR_MECHANISM_INVALID = 0x00000070;
static const CK_RV CKR_OBJECT_HANDLE_INVALID = 0x00000082;
static const CK_RV CKR_OPERATION_ACTIVE = 0x00000090;
static const CK_RV CKR_OPERATION_NOT_INITIALIZED = 0x00000091;
static const CK_RV CKR_PIN_INCORRECT = 0x000000A0;
static const CK_RV CKR_SESSION_PARALLEL_NOT_SUPPORTED = 0x000000B4;
static const CK_RV CKR_SESSION_HANDLE_INVALID = 0x000000B3;
static const CK_RV CKR_TOKEN_NOT_PRESENT = 0x000000E0;
static const CK_RV CKR_USER_ALREADY_LOGGED_IN = 0x00000100;
static const CK_RV CKR_USER_NOT_LOGGED_IN = 0x00000101;
static const CK_RV CKR_USER_TYPE_INVALID = 0x00000103;
static const CK_RV CKR_BUFFER_TOO_SMALL = 0x00000150;
static const CK_RV CKR_CRYPTOKI_NOT_INITIALIZED = 0x00000190;
static const CK_RV CKR_CRYPTOKI_ALREADY_INITIALIZED = 0x00000191;

// -- Flags used by the bridge (pkcs11t.h CKF_*) --

// CK_C_INITIALIZE_ARGS.flags
static const CK_FLAGS CKF_LIBRARY_CANT_CREATE_OS_THREADS = 0x00000001;
static const CK_FLAGS CKF_OS_LOCKING_OK = 0x00000002;

// CK_SLOT_INFO.flags
static const CK_FLAGS CKF_TOKEN_PRESENT = 0x00000001;
static const CK_FLAGS CKF_REMOVABLE_DEVICE = 0x00000002;
static const CK_FLAGS CKF_HW_SLOT = 0x00000004;

// CK_INTERFACE.flags
static const CK_FLAGS CKF_INTERFACE_FORK_SAFE = 0x00000001;

// C_EncryptMessageNext/C_DecryptMessageNext flags
static const CK_FLAGS CKF_END_OF_MESSAGE = 0x00000001;

// C_GetSessionValidationFlags results
static const CK_FLAGS CKS_LAST_VALIDATION_OK = 0x00000001;

// CK_TOKEN_INFO.flags
static const CK_FLAGS CKF_WRITE_PROTECTED = 0x00000002;
static const CK_FLAGS CKF_LOGIN_REQUIRED = 0x00000004;
static const CK_FLAGS CKF_USER_PIN_INITIALIZED = 0x00000008;
static const CK_FLAGS CKF_PROTECTED_AUTHENTICATION_PATH = 0x00000100;
static const CK_FLAGS CKF_TOKEN_INITIALIZED = 0x00000400;

// -- Structures (pkcs11t.h) --

typedef struct CK_VERSION {
  CK_BYTE major;
  CK_BYTE minor;
} CK_VERSION;
typedef CK_VERSION *CK_VERSION_PTR;

typedef struct CK_INFO {
  CK_VERSION cryptokiVersion;
  CK_UTF8CHAR manufacturerID[32];
  CK_FLAGS flags;
  CK_UTF8CHAR libraryDescription[32];
  CK_VERSION libraryVersion;
} CK_INFO;
typedef CK_INFO *CK_INFO_PTR;

typedef struct CK_SLOT_INFO {
  CK_UTF8CHAR slotDescription[64];
  CK_UTF8CHAR manufacturerID[32];
  CK_FLAGS flags;
  CK_VERSION hardwareVersion;
  CK_VERSION firmwareVersion;
} CK_SLOT_INFO;
typedef CK_SLOT_INFO *CK_SLOT_INFO_PTR;

typedef struct CK_TOKEN_INFO {
  CK_UTF8CHAR label[32];
  CK_UTF8CHAR manufacturerID[32];
  CK_UTF8CHAR model[16];
  CK_CHAR serialNumber[16];
  CK_FLAGS flags;
  CK_ULONG ulMaxSessionCount;
  CK_ULONG ulSessionCount;
  CK_ULONG ulMaxRwSessionCount;
  CK_ULONG ulRwSessionCount;
  CK_ULONG ulMaxPinLen;
  CK_ULONG ulMinPinLen;
  CK_ULONG ulTotalPublicMemory;
  CK_ULONG ulFreePublicMemory;
  CK_ULONG ulTotalPrivateMemory;
  CK_ULONG ulFreePrivateMemory;
  CK_VERSION hardwareVersion;
  CK_VERSION firmwareVersion;
  CK_CHAR utcTime[16];
} CK_TOKEN_INFO;
typedef CK_TOKEN_INFO *CK_TOKEN_INFO_PTR;

typedef struct CK_SESSION_INFO {
  CK_SLOT_ID slotID;
  CK_STATE state;
  CK_FLAGS flags;
  CK_ULONG ulDeviceError;
} CK_SESSION_INFO;
typedef CK_SESSION_INFO *CK_SESSION_INFO_PTR;

typedef struct CK_ATTRIBUTE {
  CK_ATTRIBUTE_TYPE type;
  CK_VOID_PTR pValue;
  CK_ULONG ulValueLen;
} CK_ATTRIBUTE;
typedef CK_ATTRIBUTE *CK_ATTRIBUTE_PTR;

typedef struct CK_MECHANISM {
  CK_MECHANISM_TYPE mechanism;
  CK_VOID_PTR pParameter;
  CK_ULONG ulParameterLen;
} CK_MECHANISM;
typedef CK_MECHANISM *CK_MECHANISM_PTR;

typedef struct CK_MECHANISM_INFO {
  CK_ULONG ulMinKeySize;
  CK_ULONG ulMaxKeySize;
  CK_FLAGS flags;
} CK_MECHANISM_INFO;
typedef CK_MECHANISM_INFO *CK_MECHANISM_INFO_PTR;

typedef struct CK_ASYNC_DATA {
  CK_ULONG ulVersion;
  CK_BYTE_PTR pValue;
  CK_ULONG ulValue;
  CK_OBJECT_HANDLE hObject;
  CK_OBJECT_HANDLE hAdditionalObject;
} CK_ASYNC_DATA;
typedef CK_ASYNC_DATA *CK_ASYNC_DATA_PTR;

typedef struct CK_INTERFACE {
  CK_UTF8CHAR_PTR pInterfaceName;
  CK_VOID_PTR pFunctionList;
  CK_FLAGS flags;
} CK_INTERFACE;
typedef CK_INTERFACE *CK_INTERFACE_PTR;
typedef CK_INTERFACE_PTR *CK_INTERFACE_PTR_PTR;

typedef CK_RV (*CK_NOTIFY)(
  CK_SESSION_HANDLE hSession, CK_NOTIFICATION event, CK_VOID_PTR pApplication);

typedef CK_RV (*CK_CREATEMUTEX)(CK_VOID_PTR_PTR ppMutex);
typedef CK_RV (*CK_DESTROYMUTEX)(CK_VOID_PTR pMutex);
typedef CK_RV (*CK_LOCKMUTEX)(CK_VOID_PTR pMutex);
typedef CK_RV (*CK_UNLOCKMUTEX)(CK_VOID_PTR pMutex);

typedef struct CK_C_INITIALIZE_ARGS {
  CK_CREATEMUTEX CreateMutex;
  CK_DESTROYMUTEX DestroyMutex;
  CK_LOCKMUTEX LockMutex;
  CK_UNLOCKMUTEX UnlockMutex;
  CK_FLAGS flags;
  CK_VOID_PTR pReserved;
} CK_C_INITIALIZE_ARGS;
typedef CK_C_INITIALIZE_ARGS *CK_C_INITIALIZE_ARGS_PTR;

// -- Entry-point prototypes (pkcs11f.h order) --
//
// Implemented in Swift (PKCS11Bridge target): C_Initialize, C_Finalize,
// C_GetInfo, C_GetSlotList. Implemented in C (FunctionList.c):
// C_GetFunctionList, C_GetInterfaceList, C_GetInterface, and every
// remaining stub.

extern CK_RV C_Initialize(CK_VOID_PTR pInitArgs);
extern CK_RV C_Finalize(CK_VOID_PTR pReserved);
extern CK_RV C_GetInfo(CK_INFO_PTR pInfo);

struct CK_FUNCTION_LIST;
typedef struct CK_FUNCTION_LIST CK_FUNCTION_LIST;
typedef CK_FUNCTION_LIST *CK_FUNCTION_LIST_PTR;
typedef CK_FUNCTION_LIST_PTR *CK_FUNCTION_LIST_PTR_PTR;
extern CK_RV C_GetFunctionList(CK_FUNCTION_LIST_PTR_PTR ppFunctionList);

extern CK_RV C_GetSlotList(
  CK_BBOOL tokenPresent, CK_SLOT_ID_PTR pSlotList, CK_ULONG_PTR pulCount);
extern CK_RV C_GetSlotInfo(CK_SLOT_ID slotID, CK_SLOT_INFO_PTR pInfo);
extern CK_RV C_GetTokenInfo(CK_SLOT_ID slotID, CK_TOKEN_INFO_PTR pInfo);
extern CK_RV C_GetMechanismList(
  CK_SLOT_ID slotID, CK_MECHANISM_TYPE_PTR pMechanismList, CK_ULONG_PTR pulCount);
extern CK_RV C_GetMechanismInfo(
  CK_SLOT_ID slotID, CK_MECHANISM_TYPE type, CK_MECHANISM_INFO_PTR pInfo);
extern CK_RV C_InitToken(
  CK_SLOT_ID slotID, CK_UTF8CHAR_PTR pPin, CK_ULONG ulPinLen, CK_UTF8CHAR_PTR pLabel);
extern CK_RV C_InitPIN(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pPin, CK_ULONG ulPinLen);
extern CK_RV C_SetPIN(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pOldPin, CK_ULONG ulOldLen,
  CK_UTF8CHAR_PTR pNewPin, CK_ULONG ulNewLen);
extern CK_RV C_OpenSession(
  CK_SLOT_ID slotID, CK_FLAGS flags, CK_VOID_PTR pApplication, CK_NOTIFY Notify,
  CK_SESSION_HANDLE_PTR phSession);
extern CK_RV C_CloseSession(CK_SESSION_HANDLE hSession);
extern CK_RV C_CloseAllSessions(CK_SLOT_ID slotID);
extern CK_RV C_GetSessionInfo(CK_SESSION_HANDLE hSession, CK_SESSION_INFO_PTR pInfo);
extern CK_RV C_GetOperationState(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pOperationState,
  CK_ULONG_PTR pulOperationStateLen);
extern CK_RV C_SetOperationState(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pOperationState,
  CK_ULONG ulOperationStateLen, CK_OBJECT_HANDLE hEncryptionKey,
  CK_OBJECT_HANDLE hAuthenticationKey);
extern CK_RV C_Login(
  CK_SESSION_HANDLE hSession, CK_USER_TYPE userType, CK_UTF8CHAR_PTR pPin,
  CK_ULONG ulPinLen);
extern CK_RV C_Logout(CK_SESSION_HANDLE hSession);
extern CK_RV C_CreateObject(
  CK_SESSION_HANDLE hSession, CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulCount,
  CK_OBJECT_HANDLE_PTR phObject);
extern CK_RV C_CopyObject(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount, CK_OBJECT_HANDLE_PTR phNewObject);
extern CK_RV C_DestroyObject(CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject);
extern CK_RV C_GetObjectSize(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ULONG_PTR pulSize);
extern CK_RV C_GetAttributeValue(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount);
extern CK_RV C_SetAttributeValue(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount);
extern CK_RV C_FindObjectsInit(
  CK_SESSION_HANDLE hSession, CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulCount);
extern CK_RV C_FindObjects(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE_PTR phObject,
  CK_ULONG ulMaxObjectCount, CK_ULONG_PTR pulObjectCount);
extern CK_RV C_FindObjectsFinal(CK_SESSION_HANDLE hSession);
extern CK_RV C_EncryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Encrypt(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pEncryptedData, CK_ULONG_PTR pulEncryptedDataLen);
extern CK_RV C_EncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen);
extern CK_RV C_EncryptFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pLastEncryptedPart,
  CK_ULONG_PTR pulLastEncryptedPartLen);
extern CK_RV C_DecryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Decrypt(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedData, CK_ULONG ulEncryptedDataLen,
  CK_BYTE_PTR pData, CK_ULONG_PTR pulDataLen);
extern CK_RV C_DecryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen);
extern CK_RV C_DecryptFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pLastPart, CK_ULONG_PTR pulLastPartLen);
extern CK_RV C_DigestInit(CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism);
extern CK_RV C_Digest(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pDigest, CK_ULONG_PTR pulDigestLen);
extern CK_RV C_DigestUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_DigestKey(CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hKey);
extern CK_RV C_DigestFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pDigest, CK_ULONG_PTR pulDigestLen);
extern CK_RV C_SignInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Sign(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_SignUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_SignFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_SignRecoverInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_SignRecover(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_VerifyInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Verify(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen);
extern CK_RV C_VerifyUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_VerifyFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen);
extern CK_RV C_VerifyRecoverInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_VerifyRecover(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen,
  CK_BYTE_PTR pData, CK_ULONG_PTR pulDataLen);
extern CK_RV C_DigestEncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen);
extern CK_RV C_DecryptDigestUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen);
extern CK_RV C_SignEncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen);
extern CK_RV C_DecryptVerifyUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen);
extern CK_RV C_GenerateKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_GenerateKeyPair(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_ATTRIBUTE_PTR pPublicKeyTemplate, CK_ULONG ulPublicKeyAttributeCount,
  CK_ATTRIBUTE_PTR pPrivateKeyTemplate, CK_ULONG ulPrivateKeyAttributeCount,
  CK_OBJECT_HANDLE_PTR phPublicKey, CK_OBJECT_HANDLE_PTR phPrivateKey);
extern CK_RV C_WrapKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hWrappingKey, CK_OBJECT_HANDLE hKey, CK_BYTE_PTR pWrappedKey,
  CK_ULONG_PTR pulWrappedKeyLen);
extern CK_RV C_UnwrapKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hUnwrappingKey, CK_BYTE_PTR pWrappedKey, CK_ULONG ulWrappedKeyLen,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_DeriveKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hBaseKey,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_SeedRandom(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSeed, CK_ULONG ulSeedLen);
extern CK_RV C_GenerateRandom(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pRandomData, CK_ULONG ulRandomLen);
extern CK_RV C_GetFunctionStatus(CK_SESSION_HANDLE hSession);
extern CK_RV C_CancelFunction(CK_SESSION_HANDLE hSession);
extern CK_RV C_WaitForSlotEvent(
  CK_FLAGS flags, CK_SLOT_ID_PTR pSlot, CK_VOID_PTR pReserved);

// -- Entry points added in PKCS#11 3.0 (pkcs11f.h order) --

extern CK_RV C_GetInterfaceList(
  CK_INTERFACE_PTR pInterfacesList, CK_ULONG_PTR pulCount);
extern CK_RV C_GetInterface(
  CK_UTF8CHAR_PTR pInterfaceName, CK_VERSION_PTR pVersion,
  CK_INTERFACE_PTR_PTR ppInterface, CK_FLAGS flags);
extern CK_RV C_LoginUser(
  CK_SESSION_HANDLE hSession, CK_USER_TYPE userType, CK_UTF8CHAR_PTR pPin,
  CK_ULONG ulPinLen, CK_UTF8CHAR_PTR pUsername, CK_ULONG ulUsernameLen);
extern CK_RV C_SessionCancel(CK_SESSION_HANDLE hSession, CK_FLAGS flags);
extern CK_RV C_MessageEncryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_EncryptMessage(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pAssociatedData, CK_ULONG ulAssociatedDataLen, CK_BYTE_PTR pPlaintext,
  CK_ULONG ulPlaintextLen, CK_BYTE_PTR pCiphertext, CK_ULONG_PTR pulCiphertextLen);
extern CK_RV C_EncryptMessageBegin(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pAssociatedData, CK_ULONG ulAssociatedDataLen);
extern CK_RV C_EncryptMessageNext(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pPlaintextPart, CK_ULONG ulPlaintextPartLen, CK_BYTE_PTR pCiphertextPart,
  CK_ULONG_PTR pulCiphertextPartLen, CK_FLAGS flags);
extern CK_RV C_MessageEncryptFinal(CK_SESSION_HANDLE hSession);
extern CK_RV C_MessageDecryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_DecryptMessage(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pAssociatedData, CK_ULONG ulAssociatedDataLen, CK_BYTE_PTR pCiphertext,
  CK_ULONG ulCiphertextLen, CK_BYTE_PTR pPlaintext, CK_ULONG_PTR pulPlaintextLen);
extern CK_RV C_DecryptMessageBegin(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pAssociatedData, CK_ULONG ulAssociatedDataLen);
extern CK_RV C_DecryptMessageNext(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pCiphertextPart, CK_ULONG ulCiphertextPartLen, CK_BYTE_PTR pPlaintextPart,
  CK_ULONG_PTR pulPlaintextPartLen, CK_FLAGS flags);
extern CK_RV C_MessageDecryptFinal(CK_SESSION_HANDLE hSession);
extern CK_RV C_MessageSignInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_SignMessage(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pData, CK_ULONG ulDataLen, CK_BYTE_PTR pSignature,
  CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_SignMessageBegin(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen);
extern CK_RV C_SignMessageNext(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pData, CK_ULONG ulDataLen, CK_BYTE_PTR pSignature,
  CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_MessageSignFinal(CK_SESSION_HANDLE hSession);
extern CK_RV C_MessageVerifyInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_VerifyMessage(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pData, CK_ULONG ulDataLen, CK_BYTE_PTR pSignature,
  CK_ULONG ulSignatureLen);
extern CK_RV C_VerifyMessageBegin(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen);
extern CK_RV C_VerifyMessageNext(
  CK_SESSION_HANDLE hSession, CK_VOID_PTR pParameter, CK_ULONG ulParameterLen,
  CK_BYTE_PTR pData, CK_ULONG ulDataLen, CK_BYTE_PTR pSignature,
  CK_ULONG ulSignatureLen);
extern CK_RV C_MessageVerifyFinal(CK_SESSION_HANDLE hSession);

// -- Entry points added in PKCS#11 3.2 (pkcs11f.h order) --

extern CK_RV C_EncapsulateKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hPublicKey,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_BYTE_PTR pCiphertext,
  CK_ULONG_PTR pulCiphertextLen, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_DecapsulateKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hPrivateKey,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_BYTE_PTR pCiphertext,
  CK_ULONG ulCiphertextLen, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_VerifySignatureInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey,
  CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen);
extern CK_RV C_VerifySignature(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen);
extern CK_RV C_VerifySignatureUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_VerifySignatureFinal(CK_SESSION_HANDLE hSession);
extern CK_RV C_GetSessionValidationFlags(
  CK_SESSION_HANDLE hSession, CK_SESSION_VALIDATION_FLAGS_TYPE type,
  CK_FLAGS_PTR pFlags);
extern CK_RV C_AsyncComplete(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pFunctionName, CK_ASYNC_DATA_PTR pResult);
extern CK_RV C_AsyncGetID(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pFunctionName, CK_ULONG_PTR pulID);
extern CK_RV C_AsyncJoin(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pFunctionName, CK_ULONG ulID,
  CK_BYTE_PTR pData, CK_ULONG ulData);
extern CK_RV C_WrapKeyAuthenticated(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hWrappingKey, CK_OBJECT_HANDLE hKey, CK_BYTE_PTR pAssociatedData,
  CK_ULONG ulAssociatedDataLen, CK_BYTE_PTR pWrappedKey, CK_ULONG_PTR pulWrappedKeyLen);
extern CK_RV C_UnwrapKeyAuthenticated(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hUnwrappingKey, CK_BYTE_PTR pWrappedKey, CK_ULONG ulWrappedKeyLen,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_BYTE_PTR pAssociatedData,
  CK_ULONG ulAssociatedDataLen, CK_OBJECT_HANDLE_PTR phKey);

// -- Function-pointer types and the function lists (pkcs11f.h order) --

typedef CK_RV (*CK_C_Initialize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_Finalize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_GetInfo)(CK_INFO_PTR);
typedef CK_RV (*CK_C_GetFunctionList)(CK_FUNCTION_LIST_PTR_PTR);
typedef CK_RV (*CK_C_GetSlotList)(CK_BBOOL, CK_SLOT_ID_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetSlotInfo)(CK_SLOT_ID, CK_SLOT_INFO_PTR);
typedef CK_RV (*CK_C_GetTokenInfo)(CK_SLOT_ID, CK_TOKEN_INFO_PTR);
typedef CK_RV (*CK_C_GetMechanismList)(CK_SLOT_ID, CK_MECHANISM_TYPE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetMechanismInfo)(
  CK_SLOT_ID, CK_MECHANISM_TYPE, CK_MECHANISM_INFO_PTR);
typedef CK_RV (*CK_C_InitToken)(CK_SLOT_ID, CK_UTF8CHAR_PTR, CK_ULONG, CK_UTF8CHAR_PTR);
typedef CK_RV (*CK_C_InitPIN)(CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SetPIN)(
  CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ULONG, CK_UTF8CHAR_PTR, CK_ULONG);
typedef CK_RV (*CK_C_OpenSession)(
  CK_SLOT_ID, CK_FLAGS, CK_VOID_PTR, CK_NOTIFY, CK_SESSION_HANDLE_PTR);
typedef CK_RV (*CK_C_CloseSession)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_CloseAllSessions)(CK_SLOT_ID);
typedef CK_RV (*CK_C_GetSessionInfo)(CK_SESSION_HANDLE, CK_SESSION_INFO_PTR);
typedef CK_RV (*CK_C_GetOperationState)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SetOperationState)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_OBJECT_HANDLE, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Login)(CK_SESSION_HANDLE, CK_USER_TYPE, CK_UTF8CHAR_PTR, CK_ULONG);
typedef CK_RV (*CK_C_Logout)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_CreateObject)(
  CK_SESSION_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_CopyObject)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_DestroyObject)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_GetObjectSize)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetAttributeValue)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SetAttributeValue)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_FindObjectsInit)(CK_SESSION_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_FindObjects)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE_PTR, CK_ULONG, CK_ULONG_PTR);
typedef CK_RV (*CK_C_FindObjectsFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_EncryptInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Encrypt)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_EncryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_EncryptFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Decrypt)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DigestInit)(CK_SESSION_HANDLE, CK_MECHANISM_PTR);
typedef CK_RV (*CK_C_Digest)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DigestUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_DigestKey)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_DigestFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignInit)(CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Sign)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SignFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignRecoverInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_SignRecover)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_VerifyInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Verify)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyRecoverInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_VerifyRecover)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DigestEncryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptDigestUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignEncryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptVerifyUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GenerateKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_GenerateKeyPair)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_ATTRIBUTE_PTR, CK_ULONG, CK_ATTRIBUTE_PTR,
  CK_ULONG, CK_OBJECT_HANDLE_PTR, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_WrapKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_OBJECT_HANDLE,
  CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_UnwrapKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_BYTE_PTR, CK_ULONG,
  CK_ATTRIBUTE_PTR, CK_ULONG, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_DeriveKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_SeedRandom)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_GenerateRandom)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_GetFunctionStatus)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_CancelFunction)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_WaitForSlotEvent)(CK_FLAGS, CK_SLOT_ID_PTR, CK_VOID_PTR);
typedef CK_RV (*CK_C_GetInterfaceList)(CK_INTERFACE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetInterface)(
  CK_UTF8CHAR_PTR, CK_VERSION_PTR, CK_INTERFACE_PTR_PTR, CK_FLAGS);
typedef CK_RV (*CK_C_LoginUser)(
  CK_SESSION_HANDLE, CK_USER_TYPE, CK_UTF8CHAR_PTR, CK_ULONG, CK_UTF8CHAR_PTR,
  CK_ULONG);
typedef CK_RV (*CK_C_SessionCancel)(CK_SESSION_HANDLE, CK_FLAGS);
typedef CK_RV (*CK_C_MessageEncryptInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_EncryptMessage)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_EncryptMessageBegin)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_EncryptMessageNext)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG_PTR, CK_FLAGS);
typedef CK_RV (*CK_C_MessageEncryptFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_MessageDecryptInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_DecryptMessage)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptMessageBegin)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_DecryptMessageNext)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG_PTR, CK_FLAGS);
typedef CK_RV (*CK_C_MessageDecryptFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_MessageSignInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_SignMessage)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignMessageBegin)(CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SignMessageNext)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG_PTR);
typedef CK_RV (*CK_C_MessageSignFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_MessageVerifyInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_VerifyMessage)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG);
typedef CK_RV (*CK_C_VerifyMessageBegin)(CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyMessageNext)(
  CK_SESSION_HANDLE, CK_VOID_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR,
  CK_ULONG);
typedef CK_RV (*CK_C_MessageVerifyFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_EncapsulateKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_BYTE_PTR, CK_ULONG_PTR, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_DecapsulateKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_BYTE_PTR, CK_ULONG, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_VerifySignatureInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifySignature)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifySignatureUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifySignatureFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_GetSessionValidationFlags)(
  CK_SESSION_HANDLE, CK_SESSION_VALIDATION_FLAGS_TYPE, CK_FLAGS_PTR);
typedef CK_RV (*CK_C_AsyncComplete)(
  CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ASYNC_DATA_PTR);
typedef CK_RV (*CK_C_AsyncGetID)(CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_AsyncJoin)(
  CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_WrapKeyAuthenticated)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_OBJECT_HANDLE,
  CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_UnwrapKeyAuthenticated)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_BYTE_PTR, CK_ULONG,
  CK_ATTRIBUTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG, CK_OBJECT_HANDLE_PTR);

struct CK_FUNCTION_LIST {
  CK_VERSION version;
  CK_C_Initialize C_Initialize;
  CK_C_Finalize C_Finalize;
  CK_C_GetInfo C_GetInfo;
  CK_C_GetFunctionList C_GetFunctionList;
  CK_C_GetSlotList C_GetSlotList;
  CK_C_GetSlotInfo C_GetSlotInfo;
  CK_C_GetTokenInfo C_GetTokenInfo;
  CK_C_GetMechanismList C_GetMechanismList;
  CK_C_GetMechanismInfo C_GetMechanismInfo;
  CK_C_InitToken C_InitToken;
  CK_C_InitPIN C_InitPIN;
  CK_C_SetPIN C_SetPIN;
  CK_C_OpenSession C_OpenSession;
  CK_C_CloseSession C_CloseSession;
  CK_C_CloseAllSessions C_CloseAllSessions;
  CK_C_GetSessionInfo C_GetSessionInfo;
  CK_C_GetOperationState C_GetOperationState;
  CK_C_SetOperationState C_SetOperationState;
  CK_C_Login C_Login;
  CK_C_Logout C_Logout;
  CK_C_CreateObject C_CreateObject;
  CK_C_CopyObject C_CopyObject;
  CK_C_DestroyObject C_DestroyObject;
  CK_C_GetObjectSize C_GetObjectSize;
  CK_C_GetAttributeValue C_GetAttributeValue;
  CK_C_SetAttributeValue C_SetAttributeValue;
  CK_C_FindObjectsInit C_FindObjectsInit;
  CK_C_FindObjects C_FindObjects;
  CK_C_FindObjectsFinal C_FindObjectsFinal;
  CK_C_EncryptInit C_EncryptInit;
  CK_C_Encrypt C_Encrypt;
  CK_C_EncryptUpdate C_EncryptUpdate;
  CK_C_EncryptFinal C_EncryptFinal;
  CK_C_DecryptInit C_DecryptInit;
  CK_C_Decrypt C_Decrypt;
  CK_C_DecryptUpdate C_DecryptUpdate;
  CK_C_DecryptFinal C_DecryptFinal;
  CK_C_DigestInit C_DigestInit;
  CK_C_Digest C_Digest;
  CK_C_DigestUpdate C_DigestUpdate;
  CK_C_DigestKey C_DigestKey;
  CK_C_DigestFinal C_DigestFinal;
  CK_C_SignInit C_SignInit;
  CK_C_Sign C_Sign;
  CK_C_SignUpdate C_SignUpdate;
  CK_C_SignFinal C_SignFinal;
  CK_C_SignRecoverInit C_SignRecoverInit;
  CK_C_SignRecover C_SignRecover;
  CK_C_VerifyInit C_VerifyInit;
  CK_C_Verify C_Verify;
  CK_C_VerifyUpdate C_VerifyUpdate;
  CK_C_VerifyFinal C_VerifyFinal;
  CK_C_VerifyRecoverInit C_VerifyRecoverInit;
  CK_C_VerifyRecover C_VerifyRecover;
  CK_C_DigestEncryptUpdate C_DigestEncryptUpdate;
  CK_C_DecryptDigestUpdate C_DecryptDigestUpdate;
  CK_C_SignEncryptUpdate C_SignEncryptUpdate;
  CK_C_DecryptVerifyUpdate C_DecryptVerifyUpdate;
  CK_C_GenerateKey C_GenerateKey;
  CK_C_GenerateKeyPair C_GenerateKeyPair;
  CK_C_WrapKey C_WrapKey;
  CK_C_UnwrapKey C_UnwrapKey;
  CK_C_DeriveKey C_DeriveKey;
  CK_C_SeedRandom C_SeedRandom;
  CK_C_GenerateRandom C_GenerateRandom;
  CK_C_GetFunctionStatus C_GetFunctionStatus;
  CK_C_CancelFunction C_CancelFunction;
  CK_C_WaitForSlotEvent C_WaitForSlotEvent;
};

// The 3.0 and 3.2 function lists repeat the legacy members in the same
// order (the ABI is a strict prefix chain); REFINEID_CRYPTOKI_MEMBERS_*
// keeps the shared runs identical by construction, mirroring the
// pkcs11f.h include mechanism of the official headers.

#define REFINEID_CRYPTOKI_MEMBERS_2_40 \
  CK_C_Initialize C_Initialize; \
  CK_C_Finalize C_Finalize; \
  CK_C_GetInfo C_GetInfo; \
  CK_C_GetFunctionList C_GetFunctionList; \
  CK_C_GetSlotList C_GetSlotList; \
  CK_C_GetSlotInfo C_GetSlotInfo; \
  CK_C_GetTokenInfo C_GetTokenInfo; \
  CK_C_GetMechanismList C_GetMechanismList; \
  CK_C_GetMechanismInfo C_GetMechanismInfo; \
  CK_C_InitToken C_InitToken; \
  CK_C_InitPIN C_InitPIN; \
  CK_C_SetPIN C_SetPIN; \
  CK_C_OpenSession C_OpenSession; \
  CK_C_CloseSession C_CloseSession; \
  CK_C_CloseAllSessions C_CloseAllSessions; \
  CK_C_GetSessionInfo C_GetSessionInfo; \
  CK_C_GetOperationState C_GetOperationState; \
  CK_C_SetOperationState C_SetOperationState; \
  CK_C_Login C_Login; \
  CK_C_Logout C_Logout; \
  CK_C_CreateObject C_CreateObject; \
  CK_C_CopyObject C_CopyObject; \
  CK_C_DestroyObject C_DestroyObject; \
  CK_C_GetObjectSize C_GetObjectSize; \
  CK_C_GetAttributeValue C_GetAttributeValue; \
  CK_C_SetAttributeValue C_SetAttributeValue; \
  CK_C_FindObjectsInit C_FindObjectsInit; \
  CK_C_FindObjects C_FindObjects; \
  CK_C_FindObjectsFinal C_FindObjectsFinal; \
  CK_C_EncryptInit C_EncryptInit; \
  CK_C_Encrypt C_Encrypt; \
  CK_C_EncryptUpdate C_EncryptUpdate; \
  CK_C_EncryptFinal C_EncryptFinal; \
  CK_C_DecryptInit C_DecryptInit; \
  CK_C_Decrypt C_Decrypt; \
  CK_C_DecryptUpdate C_DecryptUpdate; \
  CK_C_DecryptFinal C_DecryptFinal; \
  CK_C_DigestInit C_DigestInit; \
  CK_C_Digest C_Digest; \
  CK_C_DigestUpdate C_DigestUpdate; \
  CK_C_DigestKey C_DigestKey; \
  CK_C_DigestFinal C_DigestFinal; \
  CK_C_SignInit C_SignInit; \
  CK_C_Sign C_Sign; \
  CK_C_SignUpdate C_SignUpdate; \
  CK_C_SignFinal C_SignFinal; \
  CK_C_SignRecoverInit C_SignRecoverInit; \
  CK_C_SignRecover C_SignRecover; \
  CK_C_VerifyInit C_VerifyInit; \
  CK_C_Verify C_Verify; \
  CK_C_VerifyUpdate C_VerifyUpdate; \
  CK_C_VerifyFinal C_VerifyFinal; \
  CK_C_VerifyRecoverInit C_VerifyRecoverInit; \
  CK_C_VerifyRecover C_VerifyRecover; \
  CK_C_DigestEncryptUpdate C_DigestEncryptUpdate; \
  CK_C_DecryptDigestUpdate C_DecryptDigestUpdate; \
  CK_C_SignEncryptUpdate C_SignEncryptUpdate; \
  CK_C_DecryptVerifyUpdate C_DecryptVerifyUpdate; \
  CK_C_GenerateKey C_GenerateKey; \
  CK_C_GenerateKeyPair C_GenerateKeyPair; \
  CK_C_WrapKey C_WrapKey; \
  CK_C_UnwrapKey C_UnwrapKey; \
  CK_C_DeriveKey C_DeriveKey; \
  CK_C_SeedRandom C_SeedRandom; \
  CK_C_GenerateRandom C_GenerateRandom; \
  CK_C_GetFunctionStatus C_GetFunctionStatus; \
  CK_C_CancelFunction C_CancelFunction; \
  CK_C_WaitForSlotEvent C_WaitForSlotEvent;

#define REFINEID_CRYPTOKI_MEMBERS_3_0 \
  CK_C_GetInterfaceList C_GetInterfaceList; \
  CK_C_GetInterface C_GetInterface; \
  CK_C_LoginUser C_LoginUser; \
  CK_C_SessionCancel C_SessionCancel; \
  CK_C_MessageEncryptInit C_MessageEncryptInit; \
  CK_C_EncryptMessage C_EncryptMessage; \
  CK_C_EncryptMessageBegin C_EncryptMessageBegin; \
  CK_C_EncryptMessageNext C_EncryptMessageNext; \
  CK_C_MessageEncryptFinal C_MessageEncryptFinal; \
  CK_C_MessageDecryptInit C_MessageDecryptInit; \
  CK_C_DecryptMessage C_DecryptMessage; \
  CK_C_DecryptMessageBegin C_DecryptMessageBegin; \
  CK_C_DecryptMessageNext C_DecryptMessageNext; \
  CK_C_MessageDecryptFinal C_MessageDecryptFinal; \
  CK_C_MessageSignInit C_MessageSignInit; \
  CK_C_SignMessage C_SignMessage; \
  CK_C_SignMessageBegin C_SignMessageBegin; \
  CK_C_SignMessageNext C_SignMessageNext; \
  CK_C_MessageSignFinal C_MessageSignFinal; \
  CK_C_MessageVerifyInit C_MessageVerifyInit; \
  CK_C_VerifyMessage C_VerifyMessage; \
  CK_C_VerifyMessageBegin C_VerifyMessageBegin; \
  CK_C_VerifyMessageNext C_VerifyMessageNext; \
  CK_C_MessageVerifyFinal C_MessageVerifyFinal;

#define REFINEID_CRYPTOKI_MEMBERS_3_2 \
  CK_C_EncapsulateKey C_EncapsulateKey; \
  CK_C_DecapsulateKey C_DecapsulateKey; \
  CK_C_VerifySignatureInit C_VerifySignatureInit; \
  CK_C_VerifySignature C_VerifySignature; \
  CK_C_VerifySignatureUpdate C_VerifySignatureUpdate; \
  CK_C_VerifySignatureFinal C_VerifySignatureFinal; \
  CK_C_GetSessionValidationFlags C_GetSessionValidationFlags; \
  CK_C_AsyncComplete C_AsyncComplete; \
  CK_C_AsyncGetID C_AsyncGetID; \
  CK_C_AsyncJoin C_AsyncJoin; \
  CK_C_WrapKeyAuthenticated C_WrapKeyAuthenticated; \
  CK_C_UnwrapKeyAuthenticated C_UnwrapKeyAuthenticated;

typedef struct CK_FUNCTION_LIST_3_0 {
  CK_VERSION version;
  REFINEID_CRYPTOKI_MEMBERS_2_40
  REFINEID_CRYPTOKI_MEMBERS_3_0
} CK_FUNCTION_LIST_3_0;
typedef CK_FUNCTION_LIST_3_0 *CK_FUNCTION_LIST_3_0_PTR;
typedef CK_FUNCTION_LIST_3_0_PTR *CK_FUNCTION_LIST_3_0_PTR_PTR;

typedef struct CK_FUNCTION_LIST_3_2 {
  CK_VERSION version;
  REFINEID_CRYPTOKI_MEMBERS_2_40
  REFINEID_CRYPTOKI_MEMBERS_3_0
  REFINEID_CRYPTOKI_MEMBERS_3_2
} CK_FUNCTION_LIST_3_2;
typedef CK_FUNCTION_LIST_3_2 *CK_FUNCTION_LIST_3_2_PTR;
typedef CK_FUNCTION_LIST_3_2_PTR *CK_FUNCTION_LIST_3_2_PTR_PTR;

#endif
