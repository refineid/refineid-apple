# ssh with the Finnish identity card

OpenSSH authenticates with the card's basic PIN (PIN1) key through the
PKCS#11 bridge.

## Install

From a source checkout:

```sh
Scripts/apple-app-store-connect-release-manager.swift install-pkcs11
```

ssh uses `/usr/local/lib/librefineid_pkcs11.dylib`, which exposes only
the authentication identity. The companion
`librefineid_pkcs11_sign.dylib` is for document signing, never ssh.

## Your public key

```sh
ssh-keygen -D /usr/local/lib/librefineid_pkcs11.dylib
```

No PIN needed. It prints one `authorized_keys` line, commented with
the holder and the card:

```
ecdsa-sha2-nistp384 AAAA... SURNAME GIVENNAME 99999999A (AB1234567)
```

Append it to `~/.ssh/authorized_keys` on each server.

## Configuration

Per destination, in `~/.ssh/config`:

```
Match host server.example.com user cardlogin
    PKCS11Provider /usr/local/lib/librefineid_pkcs11.dylib
```

`Host` patterns match the hostname only, so selecting on the username
needs `Match`; `Host *` applies the card everywhere. Existing `Host`
blocks for the same machine do not conflict: the first value found for
each keyword wins, and a username given on the command line overrides
the block's, which is what makes `Match user` fire.

The system PIN dialog appears when the connection is signed -- the
token uses the protected authentication path, so no PIN is typed into
the terminal. Reusing a multiplexed ssh session avoids a dialog per
connection.

That dialog cannot be answered over a remote or headless session.
`REFINEID_PKCS11_PIN_ENTRY=textual` withdraws the protected
authentication path, so ssh prompts for the PIN itself and it passes
through the ssh process instead of the system dialog. The default is
`graphical`.

### Offering only the card

Where a server counts authentication attempts, add both lines, never
`IdentitiesOnly` alone:

```
    IdentityFile ~/.ssh/id_AB1234567.pub
    IdentitiesOnly yes
```

`IdentitiesOnly yes` restricts ssh to configured identities, and a
PKCS#11 key counts as configured only when a matching public key file
is named; without one the card is dropped and the login fails with
`Permission denied (publickey)`. Write the file once:

```sh
ssh-keygen -D /usr/local/lib/librefineid_pkcs11.dylib > ~/.ssh/id_AB1234567.pub
```

ssh matches it by key, not by name; name it after the card it belongs
to. It has no private counterpart -- that key stays on the card.

## With ssh-agent

```sh
ssh-add -s /usr/local/lib/librefineid_pkcs11.dylib   # add, prompts for PIN1
ssh-add -l                                           # list
ssh-add -e /usr/local/lib/librefineid_pkcs11.dylib   # remove
```

The prompt reads `Enter passphrase for PKCS#11:`; enter the basic PIN
(PIN1), which OpenSSH will not accept empty. Logins then need no
further prompt while the card stays in the reader.

`ssh-agent` loads modules only from `/usr/lib*` and `/usr/local/lib*`
unless started with `-P`, which is why the module lives in
`/usr/local/lib`. It checks the resolved path, so a symlink from an
allowed directory to a module outside one is refused.

## Troubleshooting

- **`ssh-keygen -D` lists nothing**: check the reader, and that
  `security list-smartcards` shows the token. A listed token that
  enumerates slowly and empty means the token daemon holds a stale
  extension handle; `killall ctkd`.
- **`agent refused operation`**: empty PIN, or a module path outside
  the agent's allowlist.
- **Reinserted card, or reinstalled module**: `ssh-pkcs11-helper`
  holds the module for the agent's lifetime; re-add with `ssh-add -e`
  then `ssh-add -s`. The agentless path needs no such step.
