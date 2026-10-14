;; ABOUTME: Specs for SHA-256, base64url and PKCE challenge derivation.
;; ABOUTME: Run with `make test` (busted, Fennel loader).
(local digest (require :atlas.digest))

(fn hex [s]
  (pick-values 1 (s:gsub "." #(string.format "%02x" (string.byte $)))))

(describe "digest.sha256"
          (fn []
            (it "hashes the empty string"
                (fn []
                  (assert.are.equal "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                                    (hex (digest.sha256 "")))))
            (it "hashes abc"
                (fn []
                  (assert.are.equal "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                    (hex (digest.sha256 "abc")))))
            (it "hashes a two-block message"
                (fn []
                  (assert.are.equal "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
                                    (hex (digest.sha256 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))))
            (it "hashes a message of exactly 64 bytes"
                (fn []
                  (assert.are.equal "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
                                    (hex (digest.sha256 (string.rep "a" 64))))))))

(describe "digest.base64url"
          (fn []
            (it "encodes without padding using the URL alphabet"
                (fn []
                  (assert.are.equal "" (digest.base64url ""))
                  (assert.are.equal "Zg" (digest.base64url "f"))
                  (assert.are.equal "Zm8" (digest.base64url "fo"))
                  (assert.are.equal "Zm9v" (digest.base64url "foo"))
                  (assert.are.equal "-_8" (digest.base64url "\251\255"))))))

(describe "digest.pkce-challenge"
          (fn []
            (it "matches the RFC 7636 appendix B example"
                (fn []
                  (assert.are.equal "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
                                    (digest.pkce-challenge "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))))))
