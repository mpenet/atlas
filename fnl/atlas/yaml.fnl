;; ABOUTME: Parses YAML (or JSON) documents into plain Lua tables with JSON
;; ABOUTME: semantics, resolving plain scalars by the YAML 1.2 core schema.
(local libyaml (require :yaml))
(local json (require :lunajson))

(local tag-prefix "tag:yaml.org,2002:")

(local core-null {"" true "~" true :null true :Null true :NULL true})

(local core-bool {:true true
                  :True true
                  :TRUE true
                  :false false
                  :False false
                  :FALSE false})

(fn core-number [s]
  "Number for a YAML 1.2 core int/float literal, or nil."
  (if (s:match "^[-+]?%d+$") (or (math.tointeger (tonumber s)) (tonumber s))
      (s:match "^0o[0-7]+$") (tonumber (s:sub 3) 8) (s:match "^0x%x+$")
      (tonumber (s:sub 3) 16)
      (or (s:match "^[-+]?%.%d+$") (s:match "^[-+]?%d+%.%d*$")
          (s:match "^[-+]?%.?%d+[eE][-+]?%d+$")
          (s:match "^[-+]?%d+%.%d*[eE][-+]?%d+$")) (tonumber s)
      (s:match "^[-+]?%.[iI][nN][fF]$")
      (if (= (s:sub 1 1) "-") (- math.huge) math.huge)
      (s:match "^%.[nN][aA][nN]$") (/ 0 0) nil))

(fn scalar-value [event]
  "Lua value of a scalar event: explicit !!tags first, then plain scalars by
the core schema; quoted scalars are strings. Nulls are nil."
  (let [s event.value
        tag (and event.tag (event.tag:match (.. "^" tag-prefix "(.*)$")))]
    (if (= tag :str) s (= tag :int)
        (or (core-number s) (error (.. "invalid !!int value: " s)))
        (= tag :float)
        (or (core-number s) (error (.. "invalid !!float value: " s)))
        (= tag :bool) (. core-bool s) (= tag :null) nil
        (not= event.style :PLAIN) s (. core-null s) nil
        (not= nil (. core-bool s)) (. core-bool s)
        (let [n (core-number s)]
          (if (not= nil n) n s)))))

(fn load-events [next-event]
  "Build the first document from a libyaml event iterator."
  (let [anchors {}]
    (var event nil)

    (fn advance []
      (let [(ok e) (pcall next-event)]
        (when (not ok)
          (error (.. "YAML parse error: "
                     (pick-values 1
                                  (: (tostring e) :gsub
                                     " at document: %d+, line: (%d+), column: (%d+)"
                                     " at line %1, column %2")))
                 0))
        (set event e)
        e))

    (fn remember [value]
      ;; boxed, so anchored false and null can be told apart from "unknown"
      (when event.anchor (tset anchors event.anchor {: value}))
      value)

    (var load-node nil)

    (fn load-mapping []
      (let [m (remember {})]
        (var done false)
        (while (not done)
          (advance)
          (if (= event.type :MAPPING_END)
              (set done true)
              (let [key-event event
                    key (if (= key-event.type :SCALAR)
                            ;; keys keep their source text: `010:` stays "010"
                            (do
                              (load-node)
                              key-event.value)
                            (let [k (load-node)]
                              (if (= (type k) :table)
                                  (error "YAML parse error: mapping keys must be scalars"
                                         0)
                                  (tostring k))))
                    value (do
                            (advance)
                            (load-node))]
                (if (and (= key "<<") (= key-event.style :PLAIN)
                         (= (type value) :table))
                    ;; merge key: a mapping or a list of mappings fills in absent keys
                    (each [_ source (ipairs (if (= nil (. value 1)) [value]
                                                value))]
                      (each [k v (pairs source)]
                        (when (= nil (. m k)) (tset m k v))))
                    (not= nil value)
                    (tset m key value)))))
        m))

    (fn load-sequence []
      (let [s (remember {})]
        (var n 0)
        (var done false)
        (while (not done)
          (advance)
          (if (= event.type :SEQUENCE_END)
              (set done true)
              (do
                (set n (+ n 1))
                (tset s n (load-node)))))
        s))

    (set load-node (fn []
                     (match event.type
                       :SCALAR (remember (scalar-value event))
                       :ALIAS (. (or (. anchors event.anchor)
                                     (error (.. "YAML parse error: unknown alias *"
                                                event.anchor)
                                            0))
                                 :value)
                       :MAPPING_START (load-mapping)
                       :SEQUENCE_START (load-sequence)
                       other (error (.. "YAML parse error: unexpected " other)
                                    0))))
    (advance)
    (advance)
    (if (= event.type :DOCUMENT_START)
        (do
          (advance)
          (load-node))
        nil)))

(fn parse [content]
  "Parse YAML text into Lua values with JSON semantics: maps get string keys,
nulls become nil, plain scalars follow the YAML 1.2 core schema."
  (load-events (libyaml.parser content)))

(fn decode [content]
  "Try JSON first (faster, stricter); fall back to YAML on parse failure."
  (let [(ok parsed) (pcall json.decode content)]
    (if ok parsed (parse content))))

{: parse : decode}
