# Data

[Documentation](../README.md) › [Library](../library.md) › Data

JSON values as ezu decodes and encodes them, and checking values against a schema.

## JSON values

Response bodies are decoded with `ezu.json`, which keeps arrays apart from objects even when empty: a decoded `[]` is a table marked as an array, so it prints and re-encodes as `[]`, never `{}`. A body you build in Lua has no such mark, so mark empty arrays yourself:

```fennel
(local json (require :ezu.json))

;; sends "tags": []
(client.update-pet.invoke {:body {:name "Rex" :tags (json.array [])}})

;; true for any decoded array
(json.array? (. resp.body :tags))
```

JSON `null` is `json.null`, a value of its own: in arrays it keeps its place (`[1,null,3]` has three elements), and in response bodies a `null` member is kept (`{"a": null}` gives `{:a json.null}`), so a body prints and re-encodes as it was received. Test for it with `(= x json.null)`; it is truthy, like any table. `json.decode` leaves null members out unless its second argument is true; arrays always keep theirs.

`json.decode` and `json.encode` are available for your own JSON handling; `json.encode` sorts object keys, writes integers exactly and decimals in their shortest exact form.

## Validation

`ezu.validate.check` returns a list of `"path: problem"` strings for a decoded value against a JSON Schema (the subset OpenAPI bodies use; `pattern` and `format` are not checked). Combined with an operation's `:body-schema`:

```fennel
(local validate (require :ezu.validate))
(validate.check client.create-instance.body-schema body :body)
;; => ["body.instance-type: required" "body.disk-size: expected integer, got string"]
```
