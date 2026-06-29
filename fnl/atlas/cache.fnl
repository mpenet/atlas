(local json (require :lunajson))

(fn cache-dir []
  (.. (or (os.getenv :HOME) ".") "/.cache/atlas/schemas"))

(fn hash-url [url]
  (var h 5381)
  (for [i 1 (length url)]
    (set h (% (+ (* h 31) (string.byte url i)) 2147483647)))
  (string.format "%d" h))

(fn cache-path [url]
  (.. (cache-dir) "/" (hash-url url) ".json"))

(fn get [url ttl]
  (let [f (io.open (cache-path url) :r)]
    (when f
      (let [(ok data) (pcall json.decode (f:read :*a))]
        (f:close)
        (when (and ok data
                   (= data.url url)
                   (< (- (os.time) data.cached_at) ttl))
          data.schema)))))

(fn put [url schema]
  (let [dir (cache-dir)]
    (os.execute (.. "mkdir -p '" (dir:gsub "'" "'\\''") "'"))
    (let [f (io.open (cache-path url) :w)]
      (when f
        (f:write (json.encode {:url url :cached_at (os.time) :schema schema}))
        (f:close)))))

{: get : put}
