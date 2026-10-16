;; ABOUTME: I-Regexp (RFC 9485), the regular expressions of JSONPath: compiles a
;; ABOUTME: pattern to a program run as a Pike VM, in time linear in the text.
(local categories (require :atlas.unicode-categories))

;; a pattern is compiled to instructions:
;;   {:op :char :test (fn [cp] bool)}  consume one code point that passes
;;   {:op :split :x pc :y pc}           go on at both
;;   {:op :jmp :x pc}                   go on at x
;;   {:op :match}                       the pattern matched
;; and run by advancing every possible position in the program together, one
;; code point at a time: no backtracking, so no pattern can take exponential
;; time (I-Regexp has no back-references, which would need it).

;; a bound on the program, so {m,n} can't make one too large to run
(local max-instructions 20000)

(fn fail [pattern why]
  (error (.. "invalid regular expression: " why " in " pattern) 0))

;; ---- parsing ----

;; characters that can't stand for themselves outside a class
(local meta {"(" true
             ")" true
             "*" true
             "+" true
             "." true
             "?" true
             "[" true
             "\\" true
             "]" true
             "{" true
             "|" true
             "}" true})

;; what a backslash may escape (SingleCharEsc)
(local escapes {"(" "("
                ")" ")"
                "*" "*"
                "+" "+"
                "-" "-"
                "." "."
                "?" "?"
                "[" "["
                "\\" "\\"
                "]" "]"
                "^" "^"
                "{" "{"
                "|" "|"
                "}" "}"
                :n "\n"
                :r "\r"
                :t "\t"})

(local category-names {:L true
                       :Ll true
                       :Lm true
                       :Lo true
                       :Lt true
                       :Lu true
                       :M true
                       :Mc true
                       :Me true
                       :Mn true
                       :N true
                       :Nd true
                       :Nl true
                       :No true
                       :P true
                       :Pc true
                       :Pd true
                       :Pe true
                       :Pf true
                       :Pi true
                       :Po true
                       :Ps true
                       :Z true
                       :Zl true
                       :Zp true
                       :Zs true
                       :S true
                       :Sc true
                       :Sk true
                       :Sm true
                       :So true
                       :C true
                       :Cc true
                       :Cf true
                       :Cn true
                       :Co true})

(fn in-category [name]
  "A test for the code points of general category name (L, or Lu…)."
  (fn [cp]
    (= name (: (categories.of cp) :sub 1 (length name)))))

;; The parser works on {:chars [one string per code point] :pos index
;; :pattern source-text}.

(fn peek [p]
  (. p.chars p.pos))

(fn take [p]
  (set p.pos (+ p.pos 1))
  (. p.chars (- p.pos 1)))

(fn expect [p char]
  (when (not= (take p) char)
    (fail p.pattern (.. "expected " char))))

(fn category-escape [p]
  "The test of \\p{…} or \\P{…}, after the backslash."
  (let [complement (= (take p) "P")]
    (expect p "{")
    (var name "")
    (while (and (peek p) (not= (peek p) "}"))
      (set name (.. name (take p))))
    (expect p "}")
    (when (not (. category-names name))
      (fail p.pattern (.. "unknown category " name)))
    (let [test (in-category name)]
      (if complement #(not (test $)) test))))

(fn escape [p]
  "After a backslash: (:char code-point) or (:test function)."
  (let [c (peek p)]
    (if (or (= c "p") (= c "P")) (values :test (category-escape p))
        (. escapes c)
        (do
          (take p)
          (values :char (utf8.codepoint (. escapes c))))
        (fail p.pattern (.. "unknown escape \\" (tostring c))))))

(fn class-char [p]
  "A class character, or nil when the next one isn't one (CCchar)."
  (let [c (peek p)]
    (if (= c "\\") (do
                     (take p)
                     (escape p))
        (and c (not= c "[") (not= c "]") (not= c "-")) (values :char
                                                               (utf8.codepoint (take p))))))

(fn class-expr [p]
  "The test of [...], after the [."
  (let [negated (when (= (peek p) "^")
                  (take p)
                  true)
        tests []
        add-char #(table.insert tests #(= $2 $1))]
    (fn item []
      (let [(kind v) (class-char p)]
        (if (= kind :test) (table.insert tests v) (= kind :char)
            (if (and (= (peek p) "-") (not= (. p.chars (+ p.pos 1)) "]"))
                (do
                  (take p)
                  (let [(hi-kind hi) (class-char p)]
                    (when (not= hi-kind :char)
                      (fail p.pattern "bad range in class"))
                    (when (< hi v)
                      (fail p.pattern "range out of order in class"))
                    (table.insert tests #(and (<= v $) (<= $ hi)))))
                (table.insert tests #(= $ v)))
            (fail p.pattern "bad character in class"))))

    ;; - is literal first and last
    (if (= (peek p) "-")
        (do
          (take p)
          (table.insert tests #(= $ 45)))
        (item))
    (while (and (peek p) (not= (peek p) "]") (not= (peek p) "-"))
      (item))
    (when (= (peek p) "-")
      (take p)
      (table.insert tests #(= $ 45)))
    (expect p "]")
    (fn [cp]
      (let [hit (accumulate [found false _ t (ipairs tests) &until found]
                  (t cp))]
        (if negated (not hit) hit)))))

(var parse-alternatives nil)

(fn atom [p]
  "One atom as a node: {:kind :test :test f} or a group's alternatives."
  (let [c (take p)]
    (if (= c nil) (fail p.pattern "unexpected end") (= c "(")
        (let [node (parse-alternatives p)]
          (expect p ")")
          node) (= c ".")
        {:kind :test :test #(and (not= $ 10) (not= $ 13))} (= c "[")
        {:kind :test :test (class-expr p)} (= c "\\")
        (let [(kind v) (escape p)]
          (if (= kind :test)
              {:kind :test :test v}
              {:kind :test :test #(= $ v)})) (. meta c)
        (fail p.pattern (.. "unexpected " c))
        (let [cp (utf8.codepoint c)]
          {:kind :test :test #(= $ cp)}))))

(fn digits [p]
  (var text "")
  (while (and (peek p) (: (peek p) :match "^%d$"))
    (set text (.. text (take p))))
  (when (= text "")
    (fail p.pattern "expected a number in {}"))
  (tonumber text))

(fn quantifier [p]
  "(min max) of the quantifier that follows, max nil for no limit; (1 1)
when none does."
  (let [c (peek p)]
    (if (= c "*") (do
                    (take p)
                    (values 0 nil)) (= c "+")
        (do
          (take p)
          (values 1 nil)) (= c "?")
        (do
          (take p)
          (values 0 1)) (= c "{")
        (do
          (take p)
          (let [low (digits p)
                high (if (= (peek p) ",")
                         (do
                           (take p)
                           (when (not= (peek p) "}") (digits p)))
                         low)]
            (expect p "}")
            (when (and high (< high low))
              (fail p.pattern "{m,n} with n < m"))
            (values low high))) (values 1 1))))

(fn branch [p]
  (let [pieces []]
    (while (and (peek p) (not= (peek p) "|") (not= (peek p) ")"))
      (let [node (atom p)
            (low high) (quantifier p)]
        (table.insert pieces {:kind :repeat : node :min low :max high})))
    {:kind :sequence : pieces}))

(set parse-alternatives
     (fn [p]
       (let [branches [(branch p)]]
         (while (= (peek p) "|")
           (take p)
           (table.insert branches (branch p)))
         {:kind :alternatives : branches})))

(fn parse [pattern]
  (let [chars []]
    (when (not (utf8.len pattern))
      (fail pattern "not UTF-8"))
    (each [_ cp (utf8.codes pattern)]
      (table.insert chars (utf8.char cp)))
    (let [p {: chars :pos 1 : pattern}
          node (parse-alternatives p)]
      (when (peek p)
        (fail pattern (.. "unexpected " (peek p))))
      node)))

;; ---- compiling ----

(fn emit [prog pattern instruction]
  (table.insert prog instruction)
  (when (> (length prog) max-instructions)
    (fail pattern "the repetitions make it too large"))
  (length prog))

(var compile-node nil)

(fn compile-repeat [prog pattern {: node : min : max}]
  (for [_ 1 min]
    (compile-node prog pattern node))
  (if (= max nil)
      ;; loop: split to the body or past it, the body jumps back
      (let [split (emit prog pattern {:op :split})]
        (set (. prog split :x) (+ split 1))
        (compile-node prog pattern node)
        (emit prog pattern {:op :jmp :x split})
        (set (. prog split :y) (+ (length prog) 1)))
      (let [splits (fcollect [_ 1 (- max min)]
                     (let [split (emit prog pattern {:op :split})]
                       (set (. prog split :x) (+ split 1))
                       (compile-node prog pattern node)
                       split))]
        (each [_ split (ipairs splits)]
          (set (. prog split :y) (+ (length prog) 1))))))

(set compile-node
     (fn [prog pattern node]
       (match node.kind
         :test (emit prog pattern {:op :char :test node.test})
         :repeat (compile-repeat prog pattern node)
         :sequence (each [_ piece (ipairs node.pieces)]
                     (compile-node prog pattern piece))
         :alternatives (let [jumps []]
                         (each [i b (ipairs node.branches)]
                           (if (< i (length node.branches))
                               (let [split (emit prog pattern {:op :split})]
                                 (set (. prog split :x) (+ split 1))
                                 (compile-node prog pattern b)
                                 (table.insert jumps
                                               (emit prog pattern {:op :jmp}))
                                 (set (. prog split :y) (+ (length prog) 1)))
                               (compile-node prog pattern b)))
                         (each [_ j (ipairs jumps)]
                           (set (. prog j :x) (+ (length prog) 1)))))))

(fn compile [pattern]
  "The program of I-Regexp pattern; raises \"invalid regular expression: …\"
for anything RFC 9485 doesn't allow."
  (let [prog []]
    (compile-node prog pattern (parse pattern))
    (emit prog pattern {:op :match})
    prog))

;; ---- running ----

(fn add-thread [prog threads seen pc]
  "Add pc to threads, following jumps and splits, each pc once."
  (let [stack [pc]]
    (while (next stack)
      (let [at (table.remove stack)]
        (when (not (. seen at))
          (tset seen at true)
          (let [ins (. prog at)]
            (match ins.op
              :jmp
              (table.insert stack ins.x)
              ;; x first: pushed last
              :split
              (do
                (table.insert stack ins.y)
                (table.insert stack ins.x))
              _
              (table.insert threads at))))))))

(fn run [prog s anywhere]
  "Whether prog matches all of s, or (anywhere) part of it."
  (if (not (utf8.len s))
      false
      (let [cps (icollect [_ cp (utf8.codes s)] cp)]
        (var threads [])
        (add-thread prog threads {} 1)
        (var matched false)
        (for [i 1 (+ (length cps) 1) &until matched]
          (when (accumulate [found false _ pc (ipairs threads) &until found]
                  (= (. prog pc :op) :match))
            (when (or anywhere (= i (+ (length cps) 1)))
              (set matched true)))
          (when (and (not matched) (<= i (length cps)))
            (let [cp (. cps i)
                  next-threads []
                  seen {}]
              (each [_ pc (ipairs threads)]
                (let [ins (. prog pc)]
                  (when (and (= ins.op :char) (ins.test cp))
                    (add-thread prog next-threads seen (+ pc 1)))))
              ;; searching: a match may also start at the next code point
              (when anywhere
                (add-thread prog next-threads seen 1))
              (set threads next-threads))))
        matched)))

(fn matches? [prog s]
  "Whether compiled prog matches the whole of string s."
  (run prog s false))

(fn search? [prog s]
  "Whether compiled prog matches some part of string s."
  (run prog s true))

{: compile : matches? : search?}
