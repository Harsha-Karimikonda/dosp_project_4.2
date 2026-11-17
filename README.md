# Project 4.2 — Erlang Reddit REST API

| Member | Email | UFID |
| --- | --- | --- |
| Harsha Karimikonda | hkarimkonda@ufl.edu | 50966091 |
| Venkatesh Gollepalli | ve.gollepalli@ufl.edu | 24690032 |

An extension of our Project 4.1 Erlang/OTP engine. The server serializes state transitions in a `gen_server`; independent Erlang CLI processes use JSON REST over HTTP. Includes the RSA-2048 signature bonus, integration tests, actual demo logs, report generator, and submission packager.

## Requirements and quick start

Install **Erlang/OTP 27+** with compiler, development headers, EUnit, `inets`, `public_key`, and `crypto`. No Hex, Rebar, Cowboy, or other Erlang dependency is used. Python 3 with its standard library is required **only for generating the report and ZIP files**.

For macOS with Homebrew: `brew install erlang`. On Ubuntu/Debian, install `erlang-base erlang-dev erlang-eunit erlang-inets erlang-crypto erlang-public-key`; verify the distribution supplies OTP 27+ for the built-in JSON module. Put `escript` on PATH. The launcher also recognizes `$HOME/.local/bin/escript`.

From this directory:

```sh
./scripts/project4 build
./scripts/project4 test
./scripts/project4 server --mode base
```

In another terminal, from this directory:

```sh
./scripts/project4 client --user alice --verbose register alice
./scripts/project4 client --user alice --verbose create erlang
./scripts/project4 client --user alice --verbose post erlang 'Hello REST'
./scripts/project4 client --user alice --verbose feed
```

In a third terminal:

```sh
./scripts/project4 client --user bob --verbose register bob
./scripts/project4 client --user bob --verbose join erlang
./scripts/project4 client --user bob --verbose search REST
./scripts/project4 client --user bob --verbose vote post 1 1
```

Use `Ctrl-C` twice to stop the foreground server. All engine data is in memory and resets on server restart. The server binds to loopback port 8080 by default. `server --bind 127.0.0.1 --port 8081 --mode bonus` changes these settings. Use client `--url http://127.0.0.1:8081` for that server. Configured mode in `config/default.config` is used when `--mode` is omitted; packaged base/bonus archives have different defaults.

## CLI

Syntax: `./scripts/project4 client [--url URL] [--user NAME] [--verbose] [--bonus] [--key PRIVATE_PEM] COMMAND ARGS...`.

| Command arguments | Behavior |
| --- | --- |
| `register NAME [PUBLIC_PEM]` | Register account; public key required in bonus mode |
| `communities` | List community names and member counts |
| `create COMMUNITY` | Create community and join it |
| `join COMMUNITY` / `leave COMMUNITY` | Idempotent subscription changes |
| `post COMMUNITY TEXT [ORIGINAL_ID]` | Create a post or repost |
| `get POST_ID` / `thread POST_ID` | Download post or read comments |
| `comment POST_ID TEXT [PARENT_ID]` | Root comment or nested reply |
| `vote post\|comment ID -1\|0\|1` | Set vote; zero removes it |
| `karma NAME` | Read received vote total |
| `feed [LIMIT [BEFORE_ID]]` | Feed from subscribed communities |
| `search QUERY [LIMIT [BEFORE_ID]]` | Search all posts by text or community name |
| `send RECIPIENT TEXT` / `reply MESSAGE_ID TEXT` | Send or reply to private message |
| `inbox [LIMIT [BEFORE_ID]]` | Read received messages |
| `online true\|false` | Change own connection state |
| `keygen DIRECTORY` | Create RSA key pair; refuses to overwrite private key |
| `public-key NAME` | Retrieve registered public key |
| `shell` | Interactive client for the selected username |

Quote arguments containing spaces. Interactive mode takes JSON arrays, e.g. `["post","erlang","Hello from the interactive client"]`, `["feed"]`, or `["comment","1","A reply"]`. Enter `quit` to exit. It uses the same HTTP client as the command interface. Each invocation exits nonzero on HTTP or integrity failure. Do not automatically retry timed-out mutations: they may already have taken effect.

## REST contract

Base URL: `/api/v1`. All operations except registration require `X-User: NAME` identifying a registered, online account. Changing your own online state is allowed while offline. **Usernames are trusted, not authenticated.** This preserves Part 4.1 and is a local classroom demonstration, not an Internet service.

Requests and responses are JSON. Successful responses use `{"data": VALUE, "request_id":"..."}`; failures use `{"error":"REASON", "request_id":"..."}`. Created content returns `data.id`; votes/karma return `data.score`; collections return `data.posts`, `data.comments`, or `data.messages`; a single post returns `data.post`. Simple updates return `data.ok`. Optional missing IDs are JSON `null`, represented internally as `none`.

| Method and path | JSON body or query |
| --- | --- |
| `POST /users` | `{"username":"alice","public_key":"PEM..."}` (key optional in base mode) |
| `GET /users/:name/karma` | none |
| `GET /users/:name/public-key` | none; bonus registered key |
| `PUT /users/:name/online` | `{"online":true}`; caller must match name |
| `GET /subreddits` | none; `data.communities` contains name/member counts |
| `POST /subreddits` | `{"name":"erlang"}` |
| `PUT /subreddits/:name/subscription` | join, empty body |
| `DELETE /subreddits/:name/subscription` | leave |
| `POST /posts` | `{"community":"erlang","text":"Hello","original":null,"signature":"BASE64"}`; signature required in bonus mode |
| `GET /posts/:id` | none |
| `GET /posts/:id/comments` | none; comments include parent IDs |
| `POST /posts/:id/comments` | `{"text":"Reply","parent":null}` |
| `PUT /posts/:id/vote` | `{"direction":1}` |
| `PUT /comments/:id/vote` | `{"direction":-1}` |
| `GET /feed` | `?limit=20&before=100` |
| `GET /search` | `?q=rest&limit=20&before=100` |
| `POST /messages` | `{"recipient":"bob","text":"Hello"}` |
| `POST /messages/:id/replies` | `{"text":"Received"}` |
| `GET /inbox` | `?limit=20&before=100` |

`GET /health` (outside the version prefix) reports mode and HTTP service liveness. It is not an engine readiness check. URL-encode usernames, names, and queries. Search is Unicode case-folded substring matching of post text/community names, globally visible to online users. Feed/search/inbox descend by global content ID; cursors are exclusive, default limit 20, allowed range 1–100. Community listing sorts by name. Threads return creation order with parent IDs. Posting/commenting requires membership; self-votes are forbidden. One vote per account/target is updated atomically with author karma. Messages remain available after offline/reconnect and only recipients can reply. Text/names must be nonempty UTF-8 after trimming and at most 10,000 bytes.

HTTP statuses: 200 read/update, 201 creation, 400 invalid JSON/fields/IDs/limits/keys/signatures, 403 forbidden or offline, 404 missing resource, 405 unsupported resource method, 409 duplicate, 422 downloaded post integrity failure, 503 unavailable engine, 504 engine timeout. HTTP requests have a 64 KiB body limit. No internal diagnostics or direct engine RPC are exposed to clients.

Example showing wire communication:

```sh
curl -i -H 'X-User: bob' 'http://127.0.0.1:8080/api/v1/feed?limit=10'
```

Server logs include method, path, username, status, elapsed microseconds, and a request ID also returned in JSON. `--verbose` shows CLI requests and complete server responses.

## Signature bonus

```sh
./scripts/project4 client keygen build/alice-keys
./scripts/project4 client keygen build/bob-keys
./scripts/project4 test-bonus
./scripts/project4 server --mode bonus --port 8081
```

In separate terminals:

```sh
./scripts/project4 client --url http://127.0.0.1:8081 --user alice --bonus register alice build/alice-keys/public.pem
./scripts/project4 client --url http://127.0.0.1:8081 --user alice --bonus create erlang
./scripts/project4 client --url http://127.0.0.1:8081 --user alice --bonus --key build/alice-keys/private.pem post erlang 'Signed hello'
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus register bob build/bob-keys/public.pem
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus join erlang
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus --verbose feed
```

The client prints `SIGNATURE verified` after fetching the author's public key over REST. In the base archive, specify `--bonus` when connecting to a bonus server. The bonus archive enables verification by default. A private key is only needed for posting; it is never transmitted. Files are generated with private-key permissions 0600 and excluded from archives.

RSA-2048, exponent 65537, SHA-256, PKCS#1 v1.5 use OTP standard crypto libraries. The signed UTF-8 bytes are the OTP JSON encoding of `[1, author, community, exact_text, original_id_or_null]`. Version 1 fixes that field order and uses the same encoder on both sides. Downloaded records include `signature` and `signature_version`. Mutable score and server ID are not signed. Public keys are immutable after registration. The engine verifies before committing a post and again for every post returned via detail/feed/search; the CLI independently verifies these downloads and fails on tampering. A repost has its own author and signature and includes the source ID.

This is content integrity relative to a server-supplied key, not a public-key infrastructure or authentication system. Trusted username headers remain impersonable for unsigned operations. No replay prevention, key rotation, TLS, persistence, or comment signatures are provided.

## Tests and demo evidence

```sh
./scripts/project4 test
./scripts/project4 test-bonus
./scripts/project4 demo base
./scripts/project4 demo bonus
```

Allow loopback networking. Tests start an ephemeral HTTP port; demos start a fresh server and many independent CLI OS processes, including two concurrent voting processes. Logs print their OS PIDs and wire requests. Final demo assertions check that repeated concurrent votes leave karma at one. Each demo owns and stops its server. Runtime keys stay under `build/`.

`evidence/` contains actual test/demo logs. Engine regressions cover the Part 4.1 behavior; HTTP tests cover request validation, privacy, status mapping, pagination, timeout and unavailability. Bonus tests cover valid/wrong keys, changed signed fields, missing signatures, reposts, server-side tampering on all post downloads, and independent client tamper rejection. Test-only state tampering uses `sys:replace_state`; it is not a REST endpoint.

## Report, recordings, and packaging

```sh
./scripts/project4 report
./scripts/project4 package
# After recording and adding links:
./scripts/project4 report
./scripts/project4 package --final
```

The report generator uses Python's standard library and creates `report.pdf` separately. Packaging creates self-contained `project4.zip` (base default) and `project4-bonus.zip` (bonus default). Both include source, tests, docs, and evidence; neither includes the report, private keys, compiled binaries, or prior benchmark results.

Follow [the video guide](docs/VIDEO_GUIDE.md) to record the main ~5-minute demonstration and separate bonus video. Save the MP4 files as `videos/main.mp4` and `videos/bonus.mp4`. Fill both YouTube links in `config/submission.json`, regenerate the report, and copy the generated `SUBMISSION_COMMENT.txt` into Canvas. Draft packaging flags pending videos/links; `--final` refuses incomplete video materials. Submit both archives and **report.pdf separately**, one group submission with both members in the comments. The stated deadline is December 13 at midnight; use the course's Canvas deadline for the exact cutoff.

Local toolchain note: this workstation's OTP initially omitted crypto. A local, excluded `build/runtime/crypto` overlay was built from OTP 29.1.2 and OpenSSL 3.5.4 for validation. The launcher discovers that overlay, or accepts `PROJECT4_CRYPTO_ROOT=/path/to/crypto`. Submitted archives require a complete OTP installation and contain no machine-specific crypto binaries.

Architecture/reference: [OTP HTTP server callbacks](https://www.erlang.org/doc/apps/inets/httpd.html), [OTP HTTP client](https://www.erlang.org/doc/apps/inets/httpc.html), [OTP public_key](https://www.erlang.org/doc/apps/public_key/public_key.html), [Reddit API reference](https://www.reddit.com/dev/api/). This API follows Reddit-style resources without attempting compatibility with Reddit OAuth or its complete wire protocol.
