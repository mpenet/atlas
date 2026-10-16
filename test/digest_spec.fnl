;; ABOUTME: Specs for SHA-256, HMAC-SHA256, base64, hex and PKCE challenges,
;; ABOUTME: against the published test vectors (FIPS 180-2, RFC 4231, RFC 4648).
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

(describe "digest.base64"
          (fn []
            (it "encodes with the standard alphabet and padding (RFC 4648 vectors)"
                (fn []
                  (assert.are.equal "" (digest.base64 ""))
                  (assert.are.equal "Zg==" (digest.base64 "f"))
                  (assert.are.equal "Zm8=" (digest.base64 "fo"))
                  (assert.are.equal "Zm9v" (digest.base64 "foo"))
                  (assert.are.equal "Zm9vYmFy" (digest.base64 "foobar"))
                  (assert.are.equal "+/8=" (digest.base64 "\251\255"))))))

(fn unhex [s]
  (pick-values 1 (s:gsub "%x%x" #(string.char (tonumber $ 16)))))

(describe "sha256 (FIPS 180-2 examples)"
          (fn []
            (it "hashes the empty string, abc, and a two-block message"
                (fn []
                  (assert.are.equal "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                                    (digest.hex (digest.sha256 "")))
                  (assert.are.equal "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                    (digest.hex (digest.sha256 "abc")))
                  (assert.are.equal "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
                                    (digest.hex (digest.sha256 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))))
            (it "hashes a million a's"
                (fn []
                  (assert.are.equal "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
                                    (digest.hex (digest.sha256 (string.rep "a"
                                                                           1000000))))))
            (it "hashes messages around the padding boundaries"
                (fn []
                  ;; 55, 56 and 64 bytes: one block, two blocks, and a full block
                  (assert.are.equal "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"
                                    (digest.hex (digest.sha256 (string.rep "a"
                                                                           55))))
                  (assert.are.equal "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"
                                    (digest.hex (digest.sha256 (string.rep "a"
                                                                           56))))
                  (assert.are.equal "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
                                    (digest.hex (digest.sha256 (string.rep "a"
                                                                           64))))))))

(describe "hmac_sha256 (RFC 4231)"
          (fn []
            (it "passes test cases 1 to 4"
                (fn []
                  (assert.are.equal "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
                                    (digest.hex (digest.hmac-sha256 (string.rep "\011"
                                                                                20)
                                                                    "Hi There")))
                  (assert.are.equal "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
                                    (digest.hex (digest.hmac-sha256 "Jefe"
                                                                    "what do ya want for nothing?")))
                  (assert.are.equal "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"
                                    (digest.hex (digest.hmac-sha256 (string.rep "\170"
                                                                                20)
                                                                    (string.rep "\221"
                                                                                50))))
                  (assert.are.equal "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"
                                    (digest.hex (digest.hmac-sha256 (unhex "0102030405060708090a0b0c0d0e0f10111213141516171819")
                                                                    (string.rep "\205"
                                                                                50))))))
            (it "passes test cases 6 and 7, with keys longer than a block"
                (fn []
                  (assert.are.equal "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
                                    (digest.hex (digest.hmac-sha256 (string.rep "\170"
                                                                                131)
                                                                    "Test Using Larger Than Block-Size Key - Hash Key First")))
                  (assert.are.equal "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"
                                    (digest.hex (digest.hmac-sha256 (string.rep "\170"
                                                                                131)
                                                                    "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.")))))))

(describe "base64 (RFC 4648)"
          (fn []
            (it "encodes and decodes the test vectors"
                (fn []
                  (each [plain encoded (pairs {"" ""
                                               :f "Zg=="
                                               :fo "Zm8="
                                               :foo "Zm9v"
                                               :foob "Zm9vYg=="
                                               :fooba "Zm9vYmE="
                                               :foobar "Zm9vYmFy"})]
                    (assert.are.equal encoded (digest.base64 plain))
                    (assert.are.equal plain (digest.unbase64 encoded)))))
            (it "encodes any byte"
                (fn []
                  (let [all (string.char (table.unpack (fcollect [i 0 255] i)))]
                    (assert.are.equal all (digest.unbase64 (digest.base64 all))))))
            (it "refuses text that isn't base64"
                (fn []
                  (assert.has.error #(digest.unbase64 "Zm9v!"))))))

(describe "hex"
          (fn []
            (it "writes bytes as lowercase hexadecimal"
                (fn []
                  (assert.are.equal "00ff10" (digest.hex "\000\255\016"))))))
