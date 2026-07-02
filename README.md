# Googly

Generate modern, self-contained Elixir clients for **any Google API** from its
[Discovery document](https://developers.google.com/discovery).

It keeps the proven idea behind
[`googleapis/elixir-google-api`](https://github.com/googleapis/elixir-google-api)
(Discovery doc → structs → templates) and rebuilds the output as tight, modern, Elixir
upon the sturdy foundations of [Req](https://hex.pm/packages/req) and
[Jason](https://hex.pm/packages/jason).

## Why

The Google-written generated clients still work! But they're dated: Tesla + Poison
at the core, a shared `google_gax` runtime every client depends on, `Poison.Decoder`
protocol impls and a `ModelBase` metaprogramming layer per model, and a
builder-pattern request API. googly takes a different tack:

- **Req + Jason**, nothing else — modern HTTP and JSON.
- **Self-contained clients.** Each generated package vendors its own ~150-line
  runtime and depends only on `req` + `jason`. No shared runtime dependency, so
  every client is independently publishable to Hex.
- **Flat, stateless API.** No `Connection` struct, no nesting —
  `Googly.CloudStorage.Objects.get(bucket, object, token: token)`.
- **snake_case fields, exact wire names.** Struct fields read like Elixir
  (`bucket.time_created`) while the exact JSON key (`timeCreated`, even
  `satisfiesPZS`) is baked in per field — no lossy round-trip heuristics.
- **Plain structs.** Models are `defstruct` + a macro-free `decode/1`. Encoding
  is one `Jason.Encoder` impl per client that drops `nil`s (so PATCH won't
  clobber unset fields).

## Quick start

```sh
mix deps.get
mix googly.generate Storage    # fetch + generate + format one API
mix googly.generate            # everything in config/apis.json
```

Generated clients land in `clients/<package>/` (e.g. `clients/googly_cloud_storage`),
each a standalone Mix project you can `cd` into, compile, test, and publish.

## Tasks

| Task                             | What it does                                                                         |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| `mix googly.discover [filter]`   | List every Google API from the Discovery service (optionally filtered by substring). |
| `mix googly.fetch [Name ...]`    | Download and cache discovery docs under `specifications/gdd/`.                       |
| `mix googly.generate [Name ...]` | Fetch (if needed), generate, and format clients.                                     |

With no argument, `fetch`/`generate` operate on every API in `config/apis.json`.

## Choosing which APIs to generate

`config/apis.json` is the manifest:

```json
[
  {
    "name": "CloudStorage",
    "version": "v1",
    "url": "https://storage.googleapis.com/$discovery/rest?version=v1"
  },
  {
    "name": "CloudVision",
    "version": "v1",
    "url": "https://vision.googleapis.com/$discovery/rest?version=v1"
  },
  {
    "name": "DocumentAI",
    "version": "v1",
    "url": "https://documentai.googleapis.com/$discovery/rest?version=v1"
  },
  ...
]
```

`name` is used verbatim as the module root (`Googly.CloudStorage`) and, snake-cased, as
the Hex package (`googly_cloud_storage`). Run `mix googly.discover <term>` to find the
discovery URL for an API you want to add.

## How it works

```
discovery JSON  →  parsed to maps (Jason, keys: :atoms)
                →  Model / Api / Endpoint / Type structs
                →  EEx templates in templates/client/
                →  clients/<package>/
```

The pipeline lives in `lib/googly/generator.ex`; discovery parsing dropped the
`google_api_discovery` dependency in favour of decoding straight to maps.

## Using a generated client

Authentication is the caller's concern — pass an OAuth2 bearer token (e.g. from
[Goth](https://hex.pm/packages/goth)) via the `:token` option:

```elixir
token = Goth.fetch!(MyApp.Goth).token

{:ok, buckets} = Googly.CloudStorage.Buckets.list("my-project", token: token)
{:ok, object}  = Googly.CloudStorage.Objects.get("my-bucket", "docs/report.pdf", token: token)

{:ok, bucket} =
  Googly.CloudStorage.Buckets.insert("my-project",
    body: %Googly.CloudStorage.Model.Bucket{name: "new-bucket", location: "US"},
    token: token
  )
```

Required path/query parameters are positional; everything else — query
parameters, the request `:body`, and `:token` — rides in the trailing `opts`
keyword. Every call returns `{:ok, decoded}` on success, `{:error, %Googly.CloudStorage.Error{}}`
for an error response (HTTP 4xx/5xx), or `{:error, exception}` (e.g.
`%Req.TransportError{}`) for transport-level failures.
