;; ABOUTME: Specs for the Unicode general category of a code point, as the
;; ABOUTME: regular expressions of JSONPath (\p{Lu}, \P{N}…) need it.
(local categories (require :atlas.unicode-categories))

(describe "unicode-categories.of"
          (fn []
            (it "gives the two-letter general category"
                (fn []
                  (each [cp category (pairs {0x41 :Lu
                                             0x61 :Ll
                                             0x1C5 :Lt
                                             0x2B0 :Lm
                                             0x5D0 :Lo
                                             0x300 :Mn
                                             0x30 :Nd
                                             0x2160 :Nl
                                             0xB2 :No
                                             0x5F :Pc
                                             0x2D :Pd
                                             0x28 :Ps
                                             0x29 :Pe
                                             0x21 :Po
                                             0x2B :Sm
                                             0x24 :Sc
                                             0x5E :Sk
                                             0x1F600 :So
                                             0x20 :Zs
                                             0x2028 :Zl
                                             0x2029 :Zp
                                             0x0 :Cc
                                             0xAD :Cf
                                             0xE000 :Co
                                             0xD800 :Cs})]
                    (assert.are.equal category (categories.of cp)
                                      (string.format "U+%04X" cp)))))
            (it "says Cn for unassigned code points, up to the last"
                (fn []
                  (assert.are.equal :Cn (categories.of 0x378))
                  (assert.are.equal :Cn (categories.of 0x10FFFF))))))
