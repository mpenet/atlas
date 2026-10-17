;; ABOUTME: Specs for I-Regexp (RFC 9485), the regular expressions of JSONPath:
;; ABOUTME: syntax, whole-string and substring matching, linear-time matching.
(local iregexp (require :ezu.iregexp))

(fn matches? [pattern s]
  (iregexp.matches? (iregexp.compile pattern) s))

(fn finds? [pattern s]
  (iregexp.search? (iregexp.compile pattern) s))

(describe "iregexp matching"
          (fn []
            (it "matches the whole string"
                (fn []
                  (assert.is_true (matches? "abc" "abc"))
                  (assert.is_false (matches? "abc" "abcd"))
                  (assert.is_false (matches? "abc" "xabc"))
                  (assert.is_true (matches? "" ""))))
            (it "finds a match anywhere with search"
                (fn []
                  (assert.is_true (finds? "abc" "xxabcxx"))
                  (assert.is_false (finds? "abd" "xxabcxx"))
                  (assert.is_true (finds? "" "anything"))))
            (it "matches any character but line ends with ."
                (fn []
                  (assert.is_true (matches? "a.c" "abc"))
                  (assert.is_true (matches? "a.c" "aéc"))
                  (assert.is_false (matches? "a.c" "a\nc"))
                  (assert.is_false (matches? "a.c" "a\rc"))))
            (it "matches character classes"
                (fn []
                  (assert.is_true (matches? "[a-z]+" "abc"))
                  (assert.is_false (matches? "[a-z]+" "aBc"))
                  (assert.is_true (matches? "[^a]" "b"))
                  (assert.is_false (matches? "[^a]" "a"))
                  (assert.is_true (matches? "[-a]" "-"))
                  (assert.is_true (matches? "[a-]" "-"))
                  (assert.is_true (matches? "[\\]]" "]"))
                  (assert.is_true (matches? "a[.b]c" "a.c"))
                  (assert.is_false (matches? "a[.b]c" "axc"))))
            (it "matches alternatives and groups"
                (fn []
                  (assert.is_true (matches? "ab|cd" "cd"))
                  (assert.is_false (matches? "ab|cd" "ad"))
                  (assert.is_true (matches? "(ab)*" "abab"))
                  (assert.is_false (matches? "(ab)*" "aba"))
                  (assert.is_true (matches? "a(b|c)d" "acd"))))
            (it "repeats with quantifiers"
                (fn []
                  (assert.is_true (matches? "a?b" "b"))
                  (assert.is_true (matches? "a+b" "aaab"))
                  (assert.is_false (matches? "a+b" "b"))
                  (assert.is_true (matches? "a{2}" "aa"))
                  (assert.is_false (matches? "a{2}" "aaa"))
                  (assert.is_true (matches? "a{2,3}" "aaa"))
                  (assert.is_false (matches? "a{2,3}" "aaaa"))
                  (assert.is_true (matches? "a{2,}" "aaaaa"))
                  (assert.is_true (matches? "a{0}b" "b"))))
            (it "reads escapes"
                (fn []
                  (assert.is_true (matches? "a\\.c" "a.c"))
                  (assert.is_false (matches? "a\\.c" "abc"))
                  (assert.is_true (matches? "\\n\\t" "\n\t"))
                  (assert.is_true (matches? "\\(\\)\\{\\}\\[\\]\\|\\\\"
                                            "(){}[]|\\"))))
            (it "takes ^ and $ as ordinary characters"
                (fn []
                  (assert.is_true (matches? "^ab$" "^ab$"))
                  (assert.is_false (matches? "^ab" "ab"))))
            (it "matches Unicode categories"
                (fn []
                  (assert.is_true (matches? "\\p{Lu}" "A"))
                  (assert.is_false (matches? "\\p{Lu}" "a"))
                  (assert.is_true (matches? "\\P{Lu}" "a"))
                  (assert.is_true (matches? "\\p{L}+" "héllo"))
                  (assert.is_true (matches? "\\p{Nd}{3}" "123"))
                  (assert.is_true (matches? "[\\p{Lu}0-9]+" "A1B2"))
                  (assert.is_false (matches? "[^\\p{L}]" "x"))))
            (it "never matches text that isn't UTF-8"
                (fn []
                  (assert.is_false (matches? ".*" "a\255"))))
            (it "takes linear time, even on patterns that make backtracking explode"
                (fn []
                  (let [t0 (os.clock)]
                    (assert.is_false (matches? "(a*)*b" (string.rep "a" 40)))
                    (assert.is_false (matches? "(a|a)*b" (string.rep "a" 40)))
                    (assert.is_true (< (- (os.clock) t0) 1)))))))

(fn ecma-finds? [pattern s]
  (iregexp.search? (iregexp.compile pattern {:ecmascript true}) s))

(describe "iregexp ECMAScript syntax"
          (fn []
            (it "anchors with ^ and $"
                (fn []
                  (assert.is_true (ecma-finds? "^2\\d{2}$" "204"))
                  (assert.is_false (ecma-finds? "^2\\d{2}$" "2040"))
                  (assert.is_false (ecma-finds? "^2\\d{2}$" "1204"))
                  (assert.is_true (ecma-finds? "^(ready|done)$" "done"))
                  (assert.is_false (ecma-finds? "^(ready|done)$" "undone"))
                  (assert.is_true (ecma-finds? "a$|^b" "xa"))
                  (assert.is_true (ecma-finds? "^$" ""))))
            (it "matches word boundaries"
                (fn []
                  (assert.is_true (ecma-finds? "\\bcat\\b" "a cat sat"))
                  (assert.is_false (ecma-finds? "\\bcat\\b" "concatenate"))
                  (assert.is_true (ecma-finds? "\\Bcat\\B" "concatenate"))))
            (it "has the shorthand classes, in and out of brackets"
                (fn []
                  (assert.is_true (ecma-finds? "^\\w+$" "a_Z9"))
                  (assert.is_false (ecma-finds? "^\\w+$" "a-b"))
                  (assert.is_true (ecma-finds? "^\\W$" "-"))
                  (assert.is_true (ecma-finds? "^\\s\\S$" "\tx"))
                  (assert.is_true (ecma-finds? "^\\D$" "x"))
                  (assert.is_true (ecma-finds? "^[\\d.]+$" "1.2.3"))))
            (it "reads ECMAScript escapes"
                (fn []
                  (assert.is_true (ecma-finds? "^\\/\\$\\^$" "/$^"))
                  (assert.is_true (ecma-finds? "^\\x41\\u00e9$" "Aé"))
                  (assert.is_true (ecma-finds? "^\\f\\v$" "\f\v"))))
            (it "takes non-capturing and named groups and lazy quantifiers"
                (fn []
                  (assert.is_true (ecma-finds? "^(?:ab)+$" "abab"))
                  (assert.is_true (ecma-finds? "^(?<id>\\d+)$" "42"))
                  (assert.is_true (ecma-finds? "^a+?b*?c??$" "aab"))))
            (it "stops . at line terminators"
                (fn []
                  (assert.is_false (ecma-finds? "^a.b$" "a\u{2028}b"))))
            (it "refuses what it can't match in linear time, or doesn't know"
                (fn []
                  (each [_ pattern (ipairs ["(a)\\1"
                                            "a(?=b)"
                                            "a(?!b)"
                                            "(?<=a)b"
                                            "(?i)a"
                                            "^*"
                                            "\\q"])]
                    (assert.is_false (pcall iregexp.compile pattern
                                            {:ecmascript true})
                                     pattern))))
            (it "keeps I-Regexp unchanged without the option"
                (fn []
                  (assert.is_true (matches? "^a$" "^a$"))
                  (assert.is_false (pcall iregexp.compile "\\d"))))))

(describe "iregexp syntax"
          (fn []
            (it "refuses what isn't I-Regexp"
                (fn []
                  (each [_ pattern (ipairs ["("
                                            ")"
                                            "a{3,2}"
                                            "[b-a]"
                                            "\\d"
                                            "*a"
                                            "a**"
                                            "{1}"
                                            "]"
                                            "["
                                            "a{"
                                            "\\p{Xx}"
                                            "\\p{L"
                                            "\\"
                                            "[a"
                                            "a{1,2"
                                            "(?:a)"
                                            "\\w"
                                            "a|*"])]
                    (let [(ok err) (pcall iregexp.compile pattern)]
                      (assert.is_false ok pattern)
                      (assert.is_truthy (: (tostring err) :find
                                           "invalid regular expression" 1 true)
                                        pattern)))))
            (it "refuses repetitions too large to run"
                (fn []
                  (assert.is_false (pcall iregexp.compile "(a{1000}){1000}"))))))
