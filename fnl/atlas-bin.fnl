;; ABOUTME: Entry point for the standalone atlas binary: preloads every bundled
;; ABOUTME: module so the static build can resolve them, then runs the CLI.
;; fennel --compile-binary cannot follow transitive requires,
;; so every dependency must be required directly from the entry point,
;; and before any module that requires it.
(require :lunajson.decoder)

(require :lunajson.encoder)

(require :lunajson.sax)

(require :lunajson)

(require :lyaml.functional)

(require :lyaml.implicit)

(require :lyaml.explicit)

(require :lyaml)

(require :ltn12)

(require :mime)

(require :socket)

(require :socket.url)

(require :socket.headers)

(require :socket.tp)

(require :socket.http)

(require :ssl)

(require :ssl.https)

(require :atlas.util)

(require :atlas.digest)

(require :atlas.coerce)

(require :atlas.yaml)

(require :atlas.negotiate)

(require :atlas.doc)

(require :atlas.http)

(require :atlas.pretty)

(require :atlas.cache)

(require :atlas.auth)

(require :atlas)

(require :atlas.arazzo.expr)

(require :atlas.arazzo)

(require :atlas.cli)

(local cli (require :atlas.cli))

(cli.main arg)
