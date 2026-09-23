# WHATSUP

branch: agent/ondemand-pin1
purpose: Experiment: determine if Safari client-cert auth can request PIN1 on demand via CryptoTokenKit native UI and complete over NFC without prior PIN1 caching.
started: 2026-09-23T19:52+03:00 by antigravity
heartbeat: 2026-09-24T01:22+03:00
status: verified (direct APDU transport resolved RSA-3072 signature transmission; eliminated double PIN1 prompt; preserved accepted PIN1 across retries and separate site logins; verified on RefineID-dev)
