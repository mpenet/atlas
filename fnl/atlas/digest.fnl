;; ABOUTME: SHA-256 (FIPS 180-4), base64 and base64url in pure Lua 5.4,
;; ABOUTME: used for OAuth PKCE S256 challenges and HTTP Basic credentials.

(local k [0x428a2f98
          0x71374491
          0xb5c0fbcf
          0xe9b5dba5
          0x3956c25b
          0x59f111f1
          0x923f82a4
          0xab1c5ed5
          0xd807aa98
          0x12835b01
          0x243185be
          0x550c7dc3
          0x72be5d74
          0x80deb1fe
          0x9bdc06a7
          0xc19bf174
          0xe49b69c1
          0xefbe4786
          0x0fc19dc6
          0x240ca1cc
          0x2de92c6f
          0x4a7484aa
          0x5cb0a9dc
          0x76f988da
          0x983e5152
          0xa831c66d
          0xb00327c8
          0xbf597fc7
          0xc6e00bf3
          0xd5a79147
          0x06ca6351
          0x14292967
          0x27b70a85
          0x2e1b2138
          0x4d2c6dfc
          0x53380d13
          0x650a7354
          0x766a0abb
          0x81c2c92e
          0x92722c85
          0xa2bfe8a1
          0xa81a664b
          0xc24b8b70
          0xc76c51a3
          0xd192e819
          0xd6990624
          0xf40e3585
          0x106aa070
          0x19a4c116
          0x1e376c08
          0x2748774c
          0x34b0bcb5
          0x391c0cb3
          0x4ed8aa4a
          0x5b9cca4f
          0x682e6ff3
          0x748f82ee
          0x78a5636f
          0x84c87814
          0x8cc70208
          0x90befffa
          0xa4506ceb
          0xbef9a3f7
          0xc67178f2])

(fn rotr [x n]
  (band (bor (rshift x n) (lshift x (- 32 n))) 0xffffffff))

(fn compress [h block]
  "Process one 64-byte block, updating the 8-word state h in place."
  (let [w [(string.unpack ">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4" block)]]
    (for [i 17 64]
      (let [w15 (. w (- i 15))
            w2 (. w (- i 2))
            s0 (bxor (rotr w15 7) (rotr w15 18) (rshift w15 3))
            s1 (bxor (rotr w2 17) (rotr w2 19) (rshift w2 10))]
        (tset w i (band (+ (. w (- i 16)) s0 (. w (- i 7)) s1) 0xffffffff))))
    (var [a b c d e f g hh] h)
    (for [i 1 64]
      (let [s1 (bxor (rotr e 6) (rotr e 11) (rotr e 25))
            ch (bxor (band e f) (band (bnot e) g))
            t1 (band (+ hh s1 ch (. k i) (. w i)) 0xffffffff)
            s0 (bxor (rotr a 2) (rotr a 13) (rotr a 22))
            maj (bxor (band a b) (band a c) (band b c))
            t2 (band (+ s0 maj) 0xffffffff)]
        (set hh g)
        (set g f)
        (set f e)
        (set e (band (+ d t1) 0xffffffff))
        (set d c)
        (set c b)
        (set b a)
        (set a (band (+ t1 t2) 0xffffffff))))
    (each [i v (ipairs [a b c d e f g hh])]
      (tset h i (band (+ (. h i) v) 0xffffffff)))))

(fn sha256 [msg]
  "Raw 32-byte SHA-256 digest of msg."
  (let [h [0x6a09e667
           0xbb67ae85
           0x3c6ef372
           0xa54ff53a
           0x510e527f
           0x9b05688c
           0x1f83d9ab
           0x5be0cd19]
        zeros (% (- 56 (% (+ (length msg) 1) 64)) 64)
        padded (.. msg "\128" (string.rep "\0" zeros)
                   (string.pack ">I8" (* 8 (length msg))))]
    (for [i 1 (length padded) 64]
      (compress h (padded:sub i (+ i 63))))
    (string.pack ">I4I4I4I4I4I4I4I4" (table.unpack h))))

(fn encode-base64 [s alphabet pad?]
  (let [out []]
    (for [i 1 (length s) 3]
      (let [(b1 b2 b3) (string.byte s i (+ i 2))
            n (bor (lshift b1 16) (lshift (or b2 0) 8) (or b3 0))
            chars (if b3 4
                      b2 3
                      2)]
        (for [j 1 chars]
          (let [idx (+ 1 (band (rshift n (* 6 (- 4 j))) 63))]
            (table.insert out (alphabet:sub idx idx))))
        (when pad?
          (table.insert out (string.rep "=" (- 4 chars))))))
    (table.concat out)))

(fn base64 [s]
  "Standard base64 with padding (RFC 4648 §4)."
  (encode-base64 s
                 "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                 true))

(fn base64url [s]
  "Unpadded base64url encoding (RFC 4648 §5)."
  (encode-base64 s
                 "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
                 false))

(fn pkce-challenge [verifier]
  "S256 code challenge for an OAuth PKCE code verifier (RFC 7636)."
  (base64url (sha256 verifier)))

{: sha256 : base64 : base64url : pkce-challenge}
