# Recording guide

Record your screen with terminal text large enough to read. Your group records/uploads both videos; the project does not fabricate video evidence. Record actual execution and retain visible HTTP server logs. Use three terminal panes: server, Alice client, Bob client. Run from the project directory in every pane. Start with a fresh server so the IDs below match. If an account already exists, stop and restart the server. Keep private PEM contents off-screen.

## Main demonstration: approximately five minutes

### 0:00–0:35 — Introduce and start

Narration: “We are Harsha Karimikonda and Venkatesh Gollepalli. This extends our Erlang Project 4.1 engine with an OTP HTTP server. Independent CLI processes send JSON requests over REST.”

Show these in the server pane:

```sh
./scripts/project4 build
./scripts/project4 server --mode base
```

Explain `READY`, loopback port 8080, and that restarting resets in-memory state. Briefly show README requirements (OTP 27+).

### 0:35–1:20 — Accounts and communities

Alice pane:

```sh
./scripts/project4 client --user alice --verbose register alice
./scripts/project4 client --user alice --verbose create erlang
```

Bob pane:

```sh
./scripts/project4 client --user bob --verbose register bob
./scripts/project4 client --user bob --verbose communities
./scripts/project4 client --user bob --verbose join erlang
```

Point to POST/PUT paths, 201/200 statuses, and matching request IDs in the response/server logs. Explain trusted username identity, with no password authentication.

### 1:20–2:15 — Post, feed, and search

Alice:

```sh
./scripts/project4 client --user alice --verbose post erlang 'Hello REST from Alice'
```

Bob:

```sh
./scripts/project4 client --user bob --verbose feed
./scripts/project4 client --user bob --verbose search REST
./scripts/project4 client --user bob --verbose get 1
```

Explain that Bob sees Alice's post through HTTP rather than directly accessing engine state. Point to `data.posts`, author, text, and ID 1.

### 2:15–3:05 — Nested comments, votes, and karma

Bob:

```sh
./scripts/project4 client --user bob --verbose comment 1 'Root comment'
```

Alice:

```sh
./scripts/project4 client --user alice --verbose comment 1 'Nested reply' 2
./scripts/project4 client --user alice --verbose thread 1
```

Bob:

```sh
./scripts/project4 client --user bob --verbose vote post 1 1
./scripts/project4 client --user bob --verbose karma alice
./scripts/project4 client --user bob --verbose post erlang 'Reposting Alice' 1
```

Explain parent ID 2, karma 1, and the repost's original ID 1.

### 3:05–4:00 — Offline delivery and messages

Bob:

```sh
./scripts/project4 client --user bob --verbose online false
```

Alice:

```sh
./scripts/project4 client --user alice --verbose send bob 'Message while Bob is offline'
```

Bob:

```sh
./scripts/project4 client --user bob --verbose online true
./scripts/project4 client --user bob --verbose inbox
./scripts/project4 client --user bob --verbose reply 5 'Received after reconnect'
```

Alice:

```sh
./scripts/project4 client --user alice --verbose inbox
```

Message ID is 5 if you followed the sequence exactly. Otherwise use the ID returned by `send`. Explain recipient-only inboxes and preserved subscriptions after reconnect.

### 4:00–5:00 — Multiple processes and validation

Show this in a client pane; it starts a separate ephemeral server and does not use the manual server's state:

```sh
./scripts/project4 demo base
```

Point out `CLIENT_PROCESS os_pid=...`, server `HTTP` lines, and the concurrent repeated vote requests. Explain the final karma assertion and show `DEMO PASS`. Show `evidence/base-tests.log` ending in passing tests, or run `./scripts/project4 test` if time permits. End by noting that both terminals are independent HTTP clients and the server serializes mutations atomically.

## Separate bonus demonstration: approximately three minutes

Use a fresh server on port 8081. In a client pane, generate unique keys (choose a new directory if these already exist):

```sh
./scripts/project4 client keygen build/video-alice
./scripts/project4 client keygen build/video-bob
```

Server pane:

```sh
./scripts/project4 server --mode bonus --port 8081
```

Alice:

```sh
./scripts/project4 client --url http://127.0.0.1:8081 --user alice --bonus --verbose register alice build/video-alice/public.pem
./scripts/project4 client --url http://127.0.0.1:8081 --user alice --bonus --verbose create erlang
./scripts/project4 client --url http://127.0.0.1:8081 --user alice --bonus --key build/video-alice/private.pem --verbose post erlang 'Signed post from Alice'
```

Bob:

```sh
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus --verbose register bob build/video-bob/public.pem
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus --verbose join erlang
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus --verbose public-key alice
./scripts/project4 client --url http://127.0.0.1:8081 --user bob --bonus --verbose feed
```

Point out the signature in the post response, the GET public-key request, and `SIGNATURE verified`. Explain RSA-2048/SHA-256 and that the private key stays on the posting client. State the exact signed fields: version, author, community, text, original ID.

Show an unsigned post being rejected:

```sh
curl -i -H 'X-User: alice' -H 'Content-Type: application/json' \
  -d '{"community":"erlang","text":"Unsigned post"}' \
  http://127.0.0.1:8081/api/v1/posts
```

Expected: HTTP 400. Then run:

```sh
./scripts/project4 test-bonus
```

Explain that this test uses a separate ephemeral server and deliberately changes signed content, checks wrong keys, and tampers stored posts through a test-only OTP state hook. Point out HTTP 422 responses for detail/feed/search and the final passing test. Explain that the client also rejects a modified download independently, and that votes can change without invalidating the original content signature.

## After recording

1. Export main video to `videos/main.mp4` and bonus video to `videos/bonus.mp4`.
2. Upload each to YouTube with visibility allowing graders to view them.
3. Put actual links in `config/submission.json` under `main_youtube_url` and `bonus_youtube_url`.
4. Run `./scripts/project4 report`, then `./scripts/project4 package --final`.
5. Open the report PDF and confirm both links. Verify the main MP4 is inside `project4.zip` and bonus MP4 inside `project4-bonus.zip`.
6. Submit both archives and the separate report PDF on Canvas; paste `SUBMISSION_COMMENT.txt` with both members and both links. Check the official Canvas deadline.
