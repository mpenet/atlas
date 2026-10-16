# Requests

[Documentation](README.md) › Requests

How atlas builds a request from the command line, checks it against the spec, and sends it.

## Path parameters

Path parameters are positional, in the order they appear in the path, and sent exactly as typed (percent-encoded). `--help` shows them.

```sh
atlas op petstore get-pet-by-id 7
```

## Query parameters and headers

```sh
atlas op petstore find-pets-by-status --q.status=available
atlas op myapi list-items --q.tag=a --q.tag=b --h.X-Request-Id=42
```

A profile's `query` and `headers` are added to every request; values given on the command line win.

## Body

```sh
# inline JSON (or YAML)
atlas op myapi add-pet -d '{"name": "Rex", "status": "available"}'

# from a file
atlas op myapi add-pet -d @pet.json

# from stdin
cat pet.json | atlas op myapi add-pet -d @-

# field by field
atlas op myapi add-pet --b.name=Rex --b.status=available --b.age=3

# nested fields
atlas op myapi create-vm --b.instance-type.id=abc123 --b.disk.size=10
```

`--b.` fields are merged: `--b.a.b=1 --b.a.c=2` gives `{"a": {"b": 1, "c": 2}}`. With `-d` as well, the fields are merged over its object.

Field values take their type from the request schema: a `string` property keeps `007` as `"007"`, `integer` and `number` properties become numbers, `boolean` takes `true` or `false`, and `array` and `object` properties take JSON (`--b.tags='["a","b"]'`). A field the schema doesn't describe follows JSON's rules: `42`, `-1.5`, `true` and `false` become numbers and booleans, anything else stays a string.

How `-d` is read depends on the operation's request content type:

- JSON, form (`application/x-www-form-urlencoded`) and `multipart/form-data` operations take JSON or YAML.
- Any other type (`application/octet-stream`, `text/plain`, XML, images…) is sent byte for byte: `atlas op myapi upload-image -d @photo.png`.

For `multipart/form-data`, a field whose value starts with `@` becomes a file part, named after the file: `--b.file=@photo.png`. Write `@@` for a value that starts with a literal `@`.

JSON bodies are encoded with object keys in sorted order, integers exactly and decimals in their shortest exact form, so the same command always sends the same bytes.

## Checks before sending

Before sending, atlas compares the request with the operation's description:

- A required query parameter or header that is missing is an error naming the option to add (`--q.status=…`). Headers count wherever they come from: `--h.`, the profile, or authentication.
- A query parameter the operation doesn't declare (often a typo) prints a warning listing the declared ones; the request is still sent.
- A JSON body is checked against the request schema: required properties, types, `enum`, nested objects and arrays, `additionalProperties: false`, lengths, ranges and item counts, `allOf`, `anyOf` and `oneOf`. Errors name the exact place, such as `body.disks[0].size: expected integer, got string`. `pattern` and `format` are not checked.

All problems are reported together and nothing is sent. `--no-validate` sends anyway, for specs stricter or looser than the API they describe.

## Retries

Responses with status 408, 429, 500, 502, 503 or 504, and network errors, are retried up to `--retry` times (default 2), for GET, HEAD and OPTIONS requests only unless `--retry-unsafe` is given. atlas waits as long as the response's `Retry-After` header asks, at most `--retry-max-wait` seconds, and otherwise 1, 2, 4… seconds. An authentication failure is never retried.

## Pagination

When a GET response is a JSON array and has a `Link: <…>; rel="next"` header, atlas follows the links and prints all items as one array. Every page is requested with the same headers and credentials; a link to another origin (scheme, host or port) is not followed. atlas stops after `--max-pages` pages (default 25). If a later page fails, the items collected so far are printed with a warning naming the failing status. `--no-paginate` prints the first page as it is.

## Dry runs

`--dry-run` prints the request that would be sent, without sending it or authenticating: the header authentication would add shows as `<redacted>`. `--curl` prints a runnable `curl` command instead; it does authenticate, and its output contains the credentials.
