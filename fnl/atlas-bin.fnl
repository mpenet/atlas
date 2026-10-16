;; ABOUTME: Entry point for the standalone atlas binary: preloads every bundled
;; ABOUTME: module so the static build can resolve them, then runs the CLI.
;; fennel --require-as-include cannot follow the requires of the modules it
;; includes, so every dependency must be required directly from the entry
;; point, and before any module that requires it.
(require :lunajson.decoder)

(require :lunajson.encoder)

(require :lunajson.sax)

(require :lunajson)

(require :atlas.json)

(require :socket)

(require :socket.url)

(require :atlas.util)

(require :atlas.digest)

(require :atlas.refs)

(require :atlas.coerce)

(require :atlas.validate)

(require :atlas.retry)

(require :atlas.paginate)

(require :atlas.yaml)

(require :atlas.negotiate)

(require :atlas.doc)

(require :atlas.tls)

(require :atlas.http)

(require :atlas.pretty)

(require :atlas.cache)

(require :atlas.auth)

(require :atlas)

(require :atlas.unicode-categories)

(require :atlas.iregexp)

(require :atlas.jsonpath)

(require :atlas.arazzo.expr)

(require :atlas.arazzo)

(require :atlas.cli.request)

(require :atlas.cli.args)

(require :atlas.cli.width)

(require :atlas.cli.progress)

(require :atlas.cli.output)

(require :atlas.cli.settings)

(require :atlas.cli.help)

(require :atlas.cli.restish)

(require :atlas.cli.complete)

(require :atlas.cli.mcp)

(require :atlas.cli)

(local cli (require :atlas.cli))

(cli.main arg)
