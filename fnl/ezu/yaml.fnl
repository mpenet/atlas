;; ABOUTME: Parses YAML (or JSON) documents into plain Lua tables with JSON
;; ABOUTME: semantics, resolving plain scalars by the YAML 1.2 core schema.
(local libyaml (require :yaml))
(local json (require :ezu.json))

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

;; The loader works on a parser table:
;; {:next-event libyaml-iterator :event current-event
;;  :anchors {name {:value v :size nodes :building bool}}
;;  :nodes nodes-so-far :aliased nodes-aliases-added :text source}

;; aliases share their anchor's value, so a small document can stand for a
;; huge one (billion laughs): the nodes aliases add are counted (those
;; written out are bounded by the text's size)
(local max-aliased-nodes 1000000)

(fn count-nodes [parser n]
  (set parser.nodes (+ parser.nodes n)))

(fn count-aliased [parser n]
  (count-nodes parser n)
  (set parser.aliased (+ parser.aliased n))
  (when (> parser.aliased max-aliased-nodes)
    (error (.. "YAML parse error: the document's aliases expand to more than "
               max-aliased-nodes " nodes") 0)))

(fn advance [parser]
  (let [(ok e) (pcall parser.next-event)]
    (when (not ok)
      (error (.. "YAML parse error: "
                 (pick-values 1
                              (: (tostring e) :gsub
                                 " at document: %d+, line: (%d+), column: (%d+)"
                                 " at line %1, column %2"))) 0))
    (set parser.event e)
    e))

(fn remember [parser value]
  ;; boxed, so anchored false and null can be told apart from "unknown"
  (when parser.event.anchor
    (tset parser.anchors parser.event.anchor {: value :size 1}))
  value)

(fn load-collection [parser value load-items]
  "value, an anchored collection, filled by load-items; its anchor can't be
used inside it."
  (let [anchor parser.event.anchor
        start parser.nodes
        _ (remember parser value)
        ;; this anchor's box: the name may be given to another node inside
        box (when anchor (. parser.anchors anchor))]
    (count-nodes parser 1)
    (when box
      (set box.building true))
    (load-items value)
    (when box
      (set box.building nil)
      (set box.size (- parser.nodes start)))
    value))

(var load-node nil)

(fn mapping-key [parser]
  "The current key as a string; scalar keys keep their source text, so `010:`
stays \"010\"."
  (let [key-event parser.event]
    (if (= key-event.type :SCALAR)
        (do
          (load-node parser)
          key-event.value)
        (let [k (load-node parser)]
          (if (= (type k) :table)
              (error "YAML parse error: mapping keys must be scalars" 0)
              (tostring k))))))

(fn merge-into [m value]
  "Merge key (<<): a mapping or a list of mappings fills in absent keys."
  (each [_ source (ipairs (if (= nil (. value 1)) [value] value))]
    (each [k v (pairs source)]
      (when (= nil (. m k)) (tset m k v)))))

(fn load-mapping [parser]
  (load-collection parser {}
                   (fn [m]
                     (while (not= (. (advance parser) :type) :MAPPING_END)
                       (let [merge? (and (= parser.event.style :PLAIN)
                                         (= parser.event.value "<<"))
                             key (mapping-key parser)
                             value (do
                                     (advance parser)
                                     (load-node parser))]
                         (if (and merge? (= (type value) :table))
                             (merge-into m value)
                             (not= nil value)
                             (tset m key value)
                             parser.keep-null
                             (tset m key json.null)))))))

(fn load-sequence [parser]
  (load-collection parser (json.array [])
                   (fn [s]
                     (var n 0)
                     (while (not= (. (advance parser) :type) :SEQUENCE_END)
                       (set n (+ n 1))
                       ;; null keeps its place in a sequence
                       (tset s n (match (load-node parser) nil json.null v v))))))

(set load-node
     (fn [parser]
       (let [event parser.event]
         (match event.type
           :SCALAR (do
                     (count-nodes parser 1)
                     (remember parser (scalar-value event)))
           :ALIAS (let [box (or (. parser.anchors event.anchor)
                                (error (.. "YAML parse error: unknown alias *"
                                           event.anchor)
                                       0))]
                    (when box.building
                      (error (.. "YAML parse error: recursive alias *"
                                 event.anchor) 0))
                    (count-aliased parser box.size)
                    box.value)
           :MAPPING_START (load-mapping parser)
           :SEQUENCE_START (load-sequence parser)
           other (error (.. "YAML parse error: unexpected " other) 0)))))

(fn load-events [text ?keep-null]
  "Build the first document of text."
  ;; libyaml reads text through a bare pointer and lyaml does not keep it
  ;; alive: the parser table holds it until loading ends, or the collector
  ;; could free it mid-parse
  (let [parser {:next-event (libyaml.parser text)
                :anchors {}
                :nodes 0
                :aliased 0
                : text
                :keep-null ?keep-null}]
    (advance parser)
    (when (= (. (advance parser) :type) :DOCUMENT_START)
      (advance parser)
      (load-node parser))))

(fn parse [content ?keep-null]
  "Parse YAML text into Lua values with JSON semantics: maps get string keys,
plain scalars follow the YAML 1.2 core schema, null in a sequence is
json.null and a null mapping value is left out (json.null when ?keep-null)."
  (load-events content ?keep-null))

(fn decode [content ?keep-null]
  "Try JSON first (faster, stricter); fall back to YAML on parse failure.
?keep-null as for json.decode and parse."
  (let [(ok parsed) (pcall json.decode content ?keep-null)]
    (if ok parsed (parse content ?keep-null))))

{: parse : decode}
