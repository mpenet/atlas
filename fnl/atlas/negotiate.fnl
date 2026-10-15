;; ABOUTME: Chooses request Content-Type and Accept headers from an operation's
;; ABOUTME: declared media types.
(fn rank [media-type]
  "Preference of a media type: JSON first, then forms, then the rest, ranges
(*/*, application/*) last."
  (let [mt (media-type:lower)]
    (if (or (mt:match "^application/json") (mt:match "^[^;]*%+json")) 1
        (mt:match "^application/x%-www%-form%-urlencoded") 2
        (mt:match "^multipart/form%-data") 3
        (mt:find "*" 1 true) 5
        4)))

(fn pick-media-type [content]
  "The media type to send among content's: the most preferred, then the first
by name, so the choice is the same on every run."
  (when content
    (let [types (doto (icollect [k (pairs content)] k)
                  (table.sort #(let [a (rank $1)
                                     b (rank $2)]
                                 (if (= a b) (< $1 $2) (< a b)))))]
      (. types 1))))

(fn wire-type [media-type]
  "The Content-Type to send for a declared media type: a range (*/*) names no
type, so the body goes as JSON."
  (if (and media-type (media-type:find "*" 1 true)) "application/json"
      media-type))

(fn pick-content-type [op-spec]
  (when op-spec.requestBody
    (pick-media-type op-spec.requestBody.content)))

(fn response-code? [key]
  "Whether a key of an operation's responses is a status code or default,
rather than an extension (x-...)."
  (not (: (tostring key) :match "^x%-")))

(fn pick-accept [op-spec]
  (let [seen {}
        types []]
    (each [code resp (pairs (or op-spec.responses {}))]
      (each [mt _ (pairs (if (response-code? code) (or resp.content {}) {}))]
        (when (not (. seen mt))
          (tset seen mt true)
          (table.insert types mt))))
    (when (> (length types) 0)
      (table.sort types)
      (table.concat types ", "))))

{: pick-content-type
 : pick-accept
 : pick-media-type
 : response-code?
 : wire-type}
