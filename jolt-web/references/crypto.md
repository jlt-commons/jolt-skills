# crypto (jolt-crypto)

The `javax.crypto` / `java.security` classes Clojure libraries use, over the
system OpenSSL 3 via `jolt.ffi`. What a web app needs: digests, HMAC, random
tokens, AES, signatures, X.509 parsing. TLS for the server is in
ring-chez-adapter, for clients in http-client. Source:
https://github.com/jolt-lang/crypto (also reachable as `jolt-lang/jolt-crypto`).

```clojure
;; ring-chez-adapter, http-client and otel already bring it. Use this lib key
;; (the one they use) or the tree gets two copies.
jolt-lang/jolt-crypto
{:git/url "https://github.com/jolt-lang/crypto"
 :git/tag "<latest>" :git/sha "<sha>"}
```

Fill tags with `jdep OWNER/REPO` (jolt skill, deps-and-tasks.md). Add it at top level when a dependency pins an older crypto
(`jolt -Stree` shows which one wins).

The classes are declared in `:jolt/provides`, so a reference autoloads them
(ring-defaults' session/CSRF stack included); `(require 'jolt.crypto)` only
makes it explicit. `SecureRandom` is built into jolt itself.

```clojure
(require 'jolt.crypto)
(defn hex [^bytes bs] (apply str (map #(format "%02x" (bit-and % 0xff)) bs)))

(hex (.digest (java.security.MessageDigest/getInstance "SHA-256") (.getBytes "hello" "UTF-8")))
;; "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

(hex (let [mac (javax.crypto.Mac/getInstance "HmacSHA256")]
       (.init mac (javax.crypto.spec.SecretKeySpec. (.getBytes "key" "UTF-8") "HmacSHA256"))
       (.doFinal mac (.getBytes "msg" "UTF-8"))))

;; URL-safe random token (session ids, CSRF, API keys)
(let [b (byte-array 32)]
  (.nextBytes (java.security.SecureRandom.) b)
  (.encodeToString (.withoutPadding (java.util.Base64/getUrlEncoder)) b))
```

Verified on jolt 0.8.25. Also provided: `Cipher` `AES/CBC/PKCS5Padding`,
`MessageDigest` SHA-1/224/256/384/512 and MD5, `Mac` HmacSHA1/256/384/512,
`KeyPairGenerator`/`Signature`/`KeyFactory` for EC (P-256/384/521, secp256k1),
RSA and Ed25519, `CertificateFactory`/`X509Certificate`. Not provided: chain
validation, `KeyStore`, `SSLContext`. No password-hashing KDF (bcrypt, scrypt,
PBKDF2) is in the list; don't store passwords as a plain SHA digest.

Compare secrets in constant time (e.g. `crypto-equality`, which ring-core brings).

## OpenSSL at runtime

macOS: Homebrew or MacPorts `openssl@3` (never `/usr/lib/libcrypto.dylib`,
Apple's stub aborts the process). Linux: `libcrypto.so.3`/`.1.1`. Windows:
`libcrypto-3-x64.dll` beside the exe or on PATH. The natives are declared
`:optional`: an app (or `jolt build` binary) with this library in its tree opens
OpenSSL at startup when it is there, and on a host without it still starts;
a crypto call (or TLS) then fails when it is made. To link it in instead, in
the app's deps.edn:

```clojure
:jolt/native [{:name "crypto" :static {:archive "/path/to/libcrypto.a"}}
              {:name "ssl"    :static {:archive "/path/to/libssl.a"}}]
```

(From the crypto README; not run here.)
