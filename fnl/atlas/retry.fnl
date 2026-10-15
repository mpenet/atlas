;; ABOUTME: Wraps an http-fn to retry transient failures (408/429/5xx and
;; ABOUTME: transport errors), honoring Retry-After with a capped backoff.
(local util (require :atlas.util))

(local retryable-status {408 true 429 true 500 true 502 true 503 true 504 true})

(local safe-methods {:GET true :HEAD true :OPTIONS true})

(local months {:Jan 1
               :Feb 2
               :Mar 3
               :Apr 4
               :May 5
               :Jun 6
               :Jul 7
               :Aug 8
               :Sep 9
               :Oct 10
               :Nov 11
               :Dec 12})

(fn http-date->epoch [s]
  "Seconds since the epoch for an IMF-fixdate such as
\"Wed, 21 Oct 2015 07:28:00 GMT\", or nil."
  (let [(day mon year hour min sec) (s:match "%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) GMT")]
    (when (and day (. months mon))
      (let [local-time (os.time {:year (tonumber year)
                                 :month (. months mon)
                                 :day (tonumber day)
                                 :hour (tonumber hour)
                                 :min (tonumber min)
                                 :sec (tonumber sec)
                                 :isdst false})
            utc-offset (- (os.time) (os.time (os.date "!*t")))]
        (+ local-time utc-offset)))))

(fn retry-after [resp now]
  "Seconds requested by a Retry-After header (delta or HTTP date), or nil."
  (let [value (util.header (?. resp :headers) "retry-after")]
    (when value
      (or (tonumber value)
          (match (http-date->epoch value)
            epoch (math.max 0 (- epoch (now))))))))

(fn wrap [http-fn opts]
  "Retry http-fn up to opts.attempts extra times.
opts: {:attempts n :unsafe bool :max-wait seconds :sleep fn :now fn}"
  (let [attempts (or opts.attempts 0)
        max-wait (or opts.max-wait 300)
        sleep (or opts.sleep (. (require :socket) :sleep))
        now (or opts.now os.time)]
    (fn [req]
      (let [retry? (and (> attempts 0)
                        (or opts.unsafe
                            (. safe-methods (: (or req.method "GET") :upper))))]
        (var attempt 0)
        (var result nil)
        (while (= result nil)
          (let [(ok resp) (pcall http-fn req)
                ;; network errors are transient; requests that can't be
                ;; built and authentication failures aren't
                transient? (if ok (. retryable-status resp.status)
                               (not (and (= (type resp) :table) resp.permanent)))]
            (if (and retry? transient? (< attempt attempts))
                (do
                  (set attempt (+ attempt 1))
                  (sleep (math.min max-wait
                                   (or (and ok (retry-after resp now))
                                       (^ 2 (- attempt 1))))))
                (set result [ok resp]))))
        (let [[ok resp] result]
          (if ok resp (error resp 0)))))))

{: wrap : retry-after}
