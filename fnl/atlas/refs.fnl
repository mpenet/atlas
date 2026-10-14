;; ABOUTME: Resolves $refs in OpenAPI and Arazzo documents: local JSON
;; ABOUTME: pointers, references into other files or URLs; recursion stays cyclic.
(local util (require :atlas.util))

(fn split-ref [ref]
  "(document-part pointer) of a $ref; the pointer is percent-decoded."
  (let [(doc fragment) (ref:match "^([^#]*)#?(.*)$")]
    (values doc (util.percent-decode fragment))))

(fn resolver [root ?opts]
  "Returns (fn [value]) giving value with every $ref replaced by its target.
?opts: {:base location-of-root :load (fn [location] parsed-document)}.
Refs into other documents resolve relative to the document holding them;
each document is loaded once. Every ref to the same place yields the same
table, so recursive schemas come out as cyclic tables. Refs that point
nowhere, or only at each other, raise."
  (let [opts (or ?opts {})
        ;; the root counts as loaded, so refs back to it reuse it
        documents (if opts.base {opts.base root} {})]
    (fn document-at [from ref doc-part]
      (if (= doc-part "")
          from
          (let [base (or from.base (error (.. "cannot resolve $ref '" ref
                                              "': the schema's location is unknown")
                                          0))
                location (util.resolve-reference base doc-part)]
            (when (= nil (. documents location))
              (assert opts.load (.. "cannot resolve $ref '" ref "': no loader"))
              (tset documents location (opts.load location)))
            {:root (. documents location) :base location})))

    ;; one expansion per ref, shared by all its uses; recursive schemas
    ;; become cyclic tables
    (local cache {})

    (fn ref-target [from ref]
      "(target-document value key) for ref."
      (let [(doc-part pointer) (split-ref ref)]
        (when (and (not= pointer "") (not= (pointer:sub 1 1) "/"))
          (error (.. "unsupported $ref '" ref
                     "': the fragment must be a JSON pointer like #/a/b")
                 0))
        (let [target (document-at from ref doc-part)
              value (util.json-pointer target.root pointer)]
          (when (= nil value)
            (error (.. "unresolved $ref '" ref "'"
                       (if target.base (.. " in " target.base) ""))
                   0))
          (values target value (.. (or target.base "") "#" pointer)))))

    (fn ref-of [value]
      (when (= (type value) :table)
        (let [ref (. value "$ref")]
          (when (= (type ref) :string) ref))))

    (var deref nil)

    (fn resolve-ref [from ref]
      ;; follow refs to refs to the value they finally name
      (var (target value key) (ref-target from ref))
      (let [chain [key]]
        (while (and (= nil (. cache key)) (ref-of value))
          (let [next-ref (ref-of value)]
            (set (target value key) (ref-target target next-ref))
            (when (accumulate [found false _ k (ipairs chain) &until found]
                    (= k key))
              (error (.. "circular $ref: " (table.concat chain " -> ") " -> "
                         key) 0))
            (table.insert chain key)))
        (let [cached (. cache key)
              expanded (if (not= nil cached) cached (not= (type value) :table)
                           value ;; registered before it is filled, so recursion
                           ;; comes back to this same table
                           (let [out {}]
                             (tset cache key out)
                             (each [k v (pairs value)]
                               (tset out k (deref target v)))
                             out))]
          (each [_ k (ipairs chain)]
            (tset cache k expanded))
          expanded)))

    (set deref (fn [from value]
                 (match (ref-of value)
                   ref (resolve-ref from ref)
                   _ (if (= (type value) :table)
                         (collect [k v (pairs value)]
                           k
                           (deref from v))
                         value))))
    (fn [value]
      (deref {: root :base opts.base} value))))

{: resolver}
