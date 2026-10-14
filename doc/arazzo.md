# Arazzo workflows

[Arazzo](https://spec.openapis.org/arazzo/latest.html) describes sequences of API calls: call this, take a value from the response, call that, repeat until a job is done. `atlas az` runs Arazzo 1.0 documents, using your [profiles](cli.md#configuration) for authentication and TLS.

It is the natural fit for asynchronous APIs: one workflow starts an operation, polls its status until it completes, and returns the result, in a single command.

## Running a workflow

[`examples/petstore.arazzo.yaml`](examples/petstore.arazzo.yaml) uses the public Petstore: it finds the first pet with a given status, then fetches it.

```console
$ atlas az doc/examples/petstore.arazzo.yaml
first-pet  Find the first pet with a given status and fetch its details.

$ atlas az doc/examples/petstore.arazzo.yaml first-pet --help
first-pet

Find the first pet with a given status and fetch its details.

Usage: atlas az <name-or-file> first-pet [-i KEY=VAL ...]

Inputs:
  status           string [available|pending|sold] (default: available) — Pet status to look for

Steps:
  1. find    findPetsByStatus
  2. fetch   getPetById

$ atlas az doc/examples/petstore.arazzo.yaml first-pet -i status=sold
{
  "name": "doggie-updated",
  "status": "sold"
}
```

The document is a file path, a URL, or a [name from the configuration](#named-workflow-documents). Without a workflow id, atlas lists the workflows; with `--help`, it describes one: its inputs (type, allowed values, default, description), which inputs can be given as arguments, and its steps with what they call.

The OpenAPI documents listed in `sourceDescriptions` are loaded automatically. Relative URLs resolve against the Arazzo document's own location.

## Inputs

```sh
# one at a time
atlas az pets first-pet -i status=sold
atlas az pets first-pet --i.status=sold

# all at once, inline or from a file
atlas az pets first-pet --inputs '{"status": "sold"}'
atlas az pets first-pet --inputs @inputs.json
```

Inputs used as path parameters (`value: $inputs.NAME` on a `path` parameter) can also be given as arguments after the workflow id, in the order they first appear in the steps:

```sh
atlas az myapi get-resource 0b6f3c2e
```

`-d` and `--b.` set inputs too, which reads naturally for workflows that send a body: `atlas az myapi create-vm --b.name=web --b.disk.size=50`.

When several sources set the same input, the last one in this list wins: the configured `inputs`, arguments, `--inputs`, `-d`, then `-i`, `--i.` and `--b.` fields. Field values are typed from the workflow's `inputs` schema, like `--b.` fields of an operation.

Inputs are checked against the `inputs` schema before anything runs (types, required inputs, allowed values…); `--no-validate` runs the workflow anyway. Inputs that aren't given take the schema's `default`.

## Output modes

| `--arazzo-output` | Prints |
|-------------------|--------|
| `final` | The workflow's outputs (default) |
| `progress` | Each step on stderr as it runs, with its outputs, then the workflow's outputs |
| `steps` | Each step's response body, then the outputs |
| `full` | For each step, the operation and request body, then the response, then the outputs |

```console
$ atlas az doc/examples/petstore.arazzo.yaml first-pet --arazzo-output progress
→ find
✓ find  0.181s  HTTP 200
{
  "id": 7
}
→ fetch
✓ fetch  0.115s  HTTP 200
{
  "pet": { ... }
}
✓ workflow first-pet  0.898s
{
  "name": "Lion 1",
  "status": "available"
}
```

A failed workflow ends with `✗ workflow NAME failed` and the reason, and atlas exits 1. `-v` shows progress as well and logs every request, credentials redacted. Outputs use the `--output` format.

## Named workflow documents

The configuration's `arazzo` section names documents and attaches a profile and default inputs:

```json
{
  "arazzo": {
    "pets": {
      "file": "/home/me/workflows/petstore.arazzo.yaml",
      "profile": "petstore",
      "inputs": {"status": "available"}
    }
  }
}
```

| Key | Description |
|-----|-------------|
| `file` | Path or URL of the document |
| `profile` | Profile whose authentication, headers, TLS and server settings apply to every request |
| `inputs` | Default inputs |

`--profile=NAME` uses another profile for one run. `base-url` and `server-index` are refused when the document has several OpenAPI sources, since they would be ambiguous; server variables go to the sources that declare them.

## Writing workflows

A short reference of what atlas supports. The [Arazzo specification](https://spec.openapis.org/arazzo/latest.html) has the details.

### Steps

A step calls an operation, named by `operationId` (written `$sourceDescriptions.NAME.ID` when several sources define the same id) or `operationPath`, or runs another workflow with `workflowId`. Its `parameters` fill path, query, header and cookie parameters (`in` is required); step parameters replace workflow-level parameters with the same `name` and `in`. `requestBody` gives the body: `payload` (with runtime expressions anywhere inside), `contentType` to override the operation's, and `replacements`, each setting the value at a JSON pointer `target` in the payload.

### Runtime expressions

| Expression | Value |
|------------|-------|
| `$inputs.NAME` | A workflow input |
| `$statusCode` | The current response's status |
| `$method`, `$url` | The current request's method and URL |
| `$response.body#/pointer` | Part of the current response body (a [JSON pointer](https://www.rfc-editor.org/rfc/rfc6901)) |
| `$response.header.NAME` | A header of the current response |
| `$request.body#/pointer`, `$request.header.NAME` | The same, for the current request |
| `$request.query.NAME`, `$request.path.NAME` | A query or path parameter of the current request |
| `$steps.ID.outputs.NAME` | An output of an earlier step |
| `$steps.ID.response.body#/pointer`, `$steps.ID.response.header.NAME` | An earlier step's response |
| `$workflows.ID.outputs.NAME` | An output of a workflow this one already ran |
| `$find(ARRAY, FIELD, VALUE[, RETURN])` | atlas extension: the first element of `ARRAY` whose `FIELD` is `VALUE`, or its `RETURN` field |
| `{$expression}` | Inside a string: the expression's value |

To reach inside an input or output, add a JSON pointer: `$steps.fetch.outputs.pet#/name`. Names may contain dots, so `$steps.fetch.outputs.pet.name` means an output named `pet.name`; when there is none but there is a `pet`, atlas says to use the pointer form.

### Success criteria

All of a step's `successCriteria` must hold; a step without any succeeds. Two kinds are supported:

- **Simple conditions:** comparisons `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, `!` and parentheses, with strings in single or double quotes (`''` for a quote inside: `'it''s'`), numbers, `true`, `false` and `null`. Strings compare case-insensitively, as the spec requires. Values from responses are compared as values, never read as part of the condition. A misspelled expression (`$statuscode`) is an error, not a silent `null`.

  ```yaml
  - condition: $statusCode == 200
  - condition: ($statusCode == 200 || $statusCode == 201) && $response.body#/state != 'failed'
  ```

- **Regular expressions** (`type: regex`) never match a missing value. They are written as [Lua patterns](https://www.lua.org/manual/5.4/manual.html#6.4.1) rather than ECMAScript regexes: `%d` for a digit, `%w` for an alphanumeric, `%` to escape. There is no `|` and no `{m,n}`: `^2%d%d$` matches a 2xx status.

  ```yaml
  - context: $statusCode
    type: regex
    condition: ^2%d%d$
  ```

JSONPath and XPath criteria are not supported.

### Actions

After a step, `onSuccess` or `onFailure` decide what happens next; the workflow's `successActions` and `failureActions` apply after the step's own, and a step action replaces a workflow action with the same `name`. The first action whose `criteria` hold is used.

- `end` stops the workflow.
- `goto` continues at `stepId`, or runs `workflowId` and stops. A `goto` to the same step waits `retryAfter` seconds first, which makes polling loops. A workflow aborts after 50 jumps to the same step; raise it with `--max-gotos`.
- `retry` runs the step again after `retryAfter` seconds, at most `retryLimit` times (default 1). With `workflowId` or `stepId`, that workflow or step runs first (to refresh a token, say).

When the response has a `Retry-After` header in seconds, it overrules `retryAfter`. A request that fails in transport (connection refused, timeout…) is a step failure like any other, so `retry` handles it too. A step that fails with no action to handle it fails the workflow.

### Polling

A common shape: start a job, then poll until it's done.

```yaml
steps:
  - stepId: start
    operationId: createExport
    successCriteria:
      - condition: $statusCode == 202
    outputs:
      job: $response.body#/id
  - stepId: wait
    operationId: getExport
    parameters:
      - name: id
        in: path
        value: $steps.start.outputs.job
    successCriteria:
      - condition: $response.body#/state == 'done'
    onFailure:
      - name: poll
        type: goto
        stepId: wait
        retryAfter: 5
        criteria:
          - condition: $response.body#/state == 'running'
    outputs:
      url: $response.body#/download_url
```

### Reuse and composition

`components` holds reusable `parameters`, `successActions`, `failureActions` and input schemas; refer to them with `reference: $components.parameters.NAME` (a `value` next to it overrides the component's); input schemas can use `$ref`. Workflows listed in `dependsOn` run first, once each, with the same inputs, and their outputs are available as `$workflows.ID.outputs.NAME`. A step with `workflowId` runs another workflow as a step: its `parameters` are that workflow's inputs, and its criteria, actions and outputs work as for any step (a step without `outputs` exposes the workflow's outputs).
