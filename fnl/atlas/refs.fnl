;; ABOUTME: Resolves $refs in OpenAPI and Arazzo documents: local JSON
;; ABOUTME: pointers, references into other files or URLs, and cycles.
(local util (require :atlas.util))

(fn split-ref [ref]
  "(document-part pointer) of a $ref; the pointer is percent-decoded."
  (let [(doc fragment) (ref:match "^([^#]*)#?(.*)$")]
    (values doc (util.percent-decode fragment))))

(fn resolver [root ?opts]
  "Returns (fn [value]) giving value with every $ref replaced by its target.
?opts: {:base location-of-root :load (fn [location] parsed-document)}.
Refs into other documents resolve relative to the document holding them;
each document is loaded once. A ref back into its own chain resolves to {}
so recursive schemas terminate. Refs that point nowhere raise."
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

    (fn deref [from value seen]
      (if (not= (type value) :table)
          value
          (let [ref (. value "$ref")]
            (if (not= (type ref) :string)
                (collect [k v (pairs value)]
                  k
                  (deref from v seen))
                (let [(doc-part pointer) (split-ref ref)
                      _ (when (and (not= pointer "")
                                   (not= (pointer:sub 1 1) "/"))
                          (error (.. "unsupported $ref '" ref
                                     "': the fragment must be a JSON pointer like #/a/b")
                                 0))
                      target (document-at from ref doc-part)
                      key (.. (or target.base "") "#" pointer)]
                  (if (. seen key)
                      {}
                      (let [resolved (util.json-pointer target.root pointer)]
                        (when (= nil resolved)
                          (error (.. "unresolved $ref '" ref "'"
                                     (if target.base (.. " in " target.base) ""))
                                 0))
                        (deref target resolved
                               (doto (collect [k v (pairs seen)] k v)
                                 (tset key true))))))))))

    (fn [value]
      (deref {: root :base opts.base} value {}))))

{: resolver}
