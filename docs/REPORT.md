## Project 4.2: Reddit REST API and Digital Signatures

Group members:

Harsha Karimikonda | hkarimkonda@ufl.edu | UFID 50966091

Venkatesh Gollepalli | ve.gollepalli@ufl.edu | UFID 24690032



Main demonstration YouTube link: PENDING - add your uploaded video link

Separate bonus demonstration YouTube link: PENDING - add your uploaded video link



This project extends our Project 4.1 Erlang/OTP Reddit engine with a JSON REST API and independent Erlang CLI clients. The optional bonus registers public keys, signs every post, and verifies post integrity both at the server and on clients.

Implementation uses OTP libraries only: inets HTTP server/client, built-in JSON, gen_server/supervisor, public_key, and crypto. Python standard-library scripts generate this PDF and the submission ZIP archives; they are not part of the engine or client runtime.

Deliverables: project4.zip, project4-bonus.zip, and this separate report.pdf. The group must add the actual main and bonus MP4 recordings and replace pending links before final submission.

Due date supplied in the assignment: December 13 at midnight. The group should use the exact deadline shown in Canvas.

## Architecture and state model

Request flow: independent Erlang CLI OS process -> httpc -> HTTP/JSON -> inets:httpd request callback -> reddit_server gen_server -> reddit_engine pure state transition -> JSON response.

reddit_sup supervises the authoritative engine server. Its serialized transitions keep post IDs, votes, scores, karma, memberships, messages, and signatures consistent. HTTP connection processes call the same engine with a five-second timeout.

Each CLI uses only REST for user operations. The demo prints client OS PIDs and launches concurrent clients to exercise shared server state. There is no Erlang distribution requirement for REST clients.

Engine state uses indexed maps for users, communities, subscriptions, posts, community posts, comments, thread relationships, votes, and inboxes. All content receives increasing global IDs.

The server defaults to 127.0.0.1:8080. Address, port, and base/bonus mode are configurable. inets supervises the HTTP service. Engine state is intentionally in memory; server or engine restart loses data.

Identity follows the existing engine: clients supply trusted X-User usernames. Registration needs no password. Caller checks protect operations relative to that supplied identity; this is not real authentication.

The implementation adds case-insensitive Unicode substring search over post text and community names, community listing, and single-post retrieval to support an end-to-end demonstration.

## REST interface and behavior

All application endpoints use /api/v1. Requests/responses are JSON. Success has data and request_id fields; failure has error and request_id. Created objects return data.id. Lists use data.posts, data.comments, or data.messages.

POST /users registers username and, for bonus mode, a PEM public_key. GET /users/:name/karma returns received vote total. PUT /users/:name/online updates only the caller. GET /users/:name/public-key returns the registered key.

GET/POST /subreddits lists/creates communities. PUT/DELETE /subreddits/:name/subscription joins/leaves. Creating a community also joins its creator.

POST /posts creates text posts or reposts with community, text, and optional original ID. GET /posts/:id downloads a post. GET/POST /posts/:id/comments reads the thread or adds comments with optional parent ID.

PUT /posts/:id/vote and /comments/:id/vote set direction to -1, 0, or 1. A repeated vote is idempotent; changing direction updates author karma by the delta. Self-votes are forbidden.

GET /feed returns posts in joined communities. GET /search?q=... searches globally visible posts. Feed/search/inbox use descending IDs, optional exclusive before cursor, and limit 1-100 (default 20). Thread comments return creation order with parent IDs.

POST /messages sends to a recipient, including offline recipients. POST /messages/:id/replies permits only the recipient to reply. GET /inbox returns only the caller's received messages. Reconnect preserves subscriptions and messages.

Statuses: 200 reads/updates; 201 creation; 400 invalid requests/keys/signatures; 403 forbidden/offline; 404 missing; 405 unsupported method; 409 duplicate; 422 download integrity failure; 503 engine unavailable; 504 engine timeout.

Names/text must be nonempty UTF-8 after trimming and at most 10,000 bytes. Request bodies are capped at 64 KiB. Malformed JSON, IDs, or limits receive errors without crashing the HTTP service. Mutations are never automatically retried.

The README provides exact methods, JSON fields, CLI commands, curl examples, and response shapes for every resource.

## Running and demonstrating the project

Install Erlang/OTP 27+ with compiler, development headers, EUnit, inets, public_key, and crypto. Put escript on PATH. The scripts/project4 launcher also recognizes a user-local Erlang installation. Use Python 3 only for report/package commands.

Build and run: ./scripts/project4 build; ./scripts/project4 test; ./scripts/project4 server --mode base. Use separate terminals for Alice and Bob.

Alice: ./scripts/project4 client --user alice --verbose register alice; then create erlang; then post erlang "Hello REST" using the same client prefix.

Bob: register bob; join erlang; feed; search REST; vote post 1 1. Alice or Bob can inspect karma alice. Comments support arbitrary nesting via parent IDs.

Use --url http://127.0.0.1:8081 for another port. The interactive shell accepts JSON arrays of command arguments, such as ["feed"] or ["post","erlang","Hello"].

Automated multi-process demos: ./scripts/project4 demo base and ./scripts/project4 demo bonus. Each starts a fresh ephemeral server, launches independent client OS processes, runs all supported features, and asserts concurrent repeated votes preserve karma one.

Server logs include request ID, method, path, username, status, and elapsed microseconds. Verbose clients print the actual HTTP method/URL and returned status/JSON, including matching request IDs.

docs/VIDEO_GUIDE.md contains a timed approximately five-minute main demo, exact commands and expected IDs, narration, a separate bonus walkthrough, and recording/upload instructions.

## Bonus signature design

Client keys use RSA-2048 with public exponent 65537. Signatures use SHA-256 and PKCS#1 v1.5 through OTP public_key/crypto. Private keys are generated locally with permissions 0600; only public keys and post signatures cross the REST API.

Registration in bonus mode requires a valid RSA-2048 public key. It is stored with the account and cannot be replaced. Other registered online users retrieve it through GET /users/:name/public-key.

The exact signed bytes are UTF-8 OTP JSON encoding of the fixed ordered array [1, author, community, exact_text, original_id_or_null]. Version and fixed field order avoid map-order ambiguity. Text is not normalized before signing.

The posting CLI reads its private PEM, signs locally, and sends a Base64 signature with the post. A repost signs its own author, text, destination community, and source ID.

The engine verifies the signature before creating the post and stores post/signature atomically. Bonus mode rejects unsigned and invalidly signed posts. Base mode preserves the original unsigned behavior.

Every post returned through detail, feed, or search is checked on the server. A failure produces HTTP 422. The bonus CLI separately fetches each author's public key over HTTP, checks each returned post, and prints SIGNATURE verified or fails.

Server ID and mutable score are excluded from the signed payload; voting therefore preserves content signatures. The signed fields protect content integrity relative to the server-provided key. They do not authenticate unsigned operations, provide key certification, or prevent replay.

Bonus demo: keygen local key directories; start server --mode bonus; register each public PEM; post with --key PRIVATE_PEM; read with --bonus and observe key lookup and verification. See the video guide for complete commands.

## Validation evidence and limitations

Base regression and HTTP suite: 13 tests passed.

Bonus suite: Passed (crypto, engine, HTTP, and independent client checks).

Base multi-process demo: PASS; 27 independent client OS process IDs recorded.

Bonus multi-process demo: PASS; 28 independent client OS process IDs recorded.

Both extracted archives passed build, applicable tests, and independent-client demos.

Evidence is preserved in evidence/base-tests.log, bonus-tests.log, base-demo.log, and bonus-demo.log. These are actual executions, not expected-output examples.

Base checks cover registration, membership, nested comments, reposts, vote/karma updates, pagination, private inboxes, replies, offline delivery, search, malformed input, engine timeout (504), and unavailable engine (503).

Bonus checks cover wrong/malformed keys, invalid/missing signatures, changes to all signed fields, valid reposts, score changes, server-side tampering on detail/feed/search, and independent client rejection of changed downloaded text. Test-only OTP state replacement injects corruption; no corruption endpoint is exposed.

The local OTP 29.1.2 installation initially lacked crypto. Validation used a locally built OTP crypto application linked against OpenSSL 3.5.4 in an excluded build/runtime overlay. Submitted sources require a complete OTP installation and contain no native binaries.

Limits: in-memory data, single serialized engine bottleneck, trusted identities, no TLS/persistence, no replay prevention/key rotation, and no signatures on comments/messages. Public-key lookup trusts the server; there is no PKI. This submission makes no new performance-capacity claims.

Recording and YouTube upload remain group tasks. Add videos/main.mp4 and videos/bonus.mp4, enter real links in config/submission.json, regenerate the report, and run package --final. Final packaging rejects missing video files or links.

## Submission and references

Submit report.pdf separately from both code archives. project4.zip defaults to base mode and includes the main MP4 when supplied. project4-bonus.zip defaults to bonus mode and includes the separate bonus MP4 when supplied. Each archive is self-contained.

Both archives include source, tests, scripts, team configuration, README, video documentation, and test/demo evidence. They exclude this report PDF, private PEM files, runtime/build artifacts, and Project 4.1 benchmark results.

SUBMISSION_COMMENT.txt is generated from the two members' configuration and video links. Paste it into the single group Canvas submission. Pending links are explicitly marked rather than invented.

Main video: PENDING - add your uploaded video link

Bonus video: PENDING - add your uploaded video link



References:

OTP HTTP server callback interface: https://www.erlang.org/doc/apps/inets/httpd.html

OTP HTTP client: https://www.erlang.org/doc/apps/inets/httpc.html

OTP public-key library: https://www.erlang.org/doc/apps/public_key/public_key.html

OTP gen_server: https://www.erlang.org/doc/apps/stdlib/gen_server.html

Reddit API structure reference: https://www.reddit.com/dev/api/
