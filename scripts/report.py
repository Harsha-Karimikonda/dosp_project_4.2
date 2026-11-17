#!/usr/bin/env python3
"""Generate a standalone PDF report using Python's standard library only."""
import json
import re
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
metadata = json.loads((ROOT / 'config/submission.json').read_text())
members_text = (ROOT / 'config/members.config').read_text()
members = re.findall(r'name\s*=>\s*<<"([^"]+)".*?email\s*=>\s*<<"([^"]+)".*?ufid\s*=>\s*<<"([^"]+)"', members_text, re.S)
assert len(members) == 2, 'Expected both team members in config/members.config'
links = {k: metadata.get(k + '_youtube_url') or 'PENDING - add your uploaded video link' for k in ('main', 'bonus')}

def evidence(name):
    path = ROOT / 'evidence' / name
    return path.read_text() if path.exists() else ''

base_tests = evidence('base-tests.log')
bonus_tests = evidence('bonus-tests.log')
base_demo = evidence('base-demo.log')
bonus_demo = evidence('bonus-demo.log')
archive_log = evidence('archive-validation.log')
archive_summary = 'Both extracted archives passed build, applicable tests, and independent-client demos.' if all(f'ARCHIVE PASS {name}' in archive_log for name in ('project4.zip', 'project4-bonus.zip')) else 'Extracted archive validation not yet recorded.'
base_status = re.search(r'All (\d+) tests passed\.', base_tests)
base_summary = f'{base_status.group(1)} tests passed' if base_status else 'Not verified: inspect evidence/base-tests.log'
bonus_summary = 'Passed (crypto, engine, HTTP, and independent client checks)' if 'Test passed.' in bonus_tests and '*failed*' not in bonus_tests else 'Not verified: inspect evidence/bonus-tests.log'

def demo_summary(log, mode):
    pids = set(re.findall(r'CLIENT_PROCESS os_pid=(\d+)', log))
    status = 'PASS' if f'DEMO PASS mode={mode}' in log else 'Not verified'
    return f'{status}; {len(pids)} independent client OS process IDs recorded'

sections = [
('Project 4.2: Reddit REST API and Digital Signatures', [
    'Group members:',
    *[f'{name} | {email} | UFID {ufid}' for name, email, ufid in members],
    '',
    'Main demonstration YouTube link: ' + links['main'],
    'Separate bonus demonstration YouTube link: ' + links['bonus'],
    '',
    'This project extends our Project 4.1 Erlang/OTP Reddit engine with a JSON REST API and independent Erlang CLI clients. The optional bonus registers public keys, signs every post, and verifies post integrity both at the server and on clients.',
    'Implementation uses OTP libraries only: inets HTTP server/client, built-in JSON, gen_server/supervisor, public_key, and crypto. Python standard-library scripts generate this PDF and the submission ZIP archives; they are not part of the engine or client runtime.',
    'Deliverables: project4.zip, project4-bonus.zip, and this separate report.pdf. The group must add the actual main and bonus MP4 recordings and replace pending links before final submission.',
    'Due date supplied in the assignment: December 13 at midnight. The group should use the exact deadline shown in Canvas.'
]),
('Architecture and state model', [
    'Request flow: independent Erlang CLI OS process -> httpc -> HTTP/JSON -> inets:httpd request callback -> reddit_server gen_server -> reddit_engine pure state transition -> JSON response.',
    'reddit_sup supervises the authoritative engine server. Its serialized transitions keep post IDs, votes, scores, karma, memberships, messages, and signatures consistent. HTTP connection processes call the same engine with a five-second timeout.',
    'Each CLI uses only REST for user operations. The demo prints client OS PIDs and launches concurrent clients to exercise shared server state. There is no Erlang distribution requirement for REST clients.',
    'Engine state uses indexed maps for users, communities, subscriptions, posts, community posts, comments, thread relationships, votes, and inboxes. All content receives increasing global IDs.',
    'The server defaults to 127.0.0.1:8080. Address, port, and base/bonus mode are configurable. inets supervises the HTTP service. Engine state is intentionally in memory; server or engine restart loses data.',
    'Identity follows the existing engine: clients supply trusted X-User usernames. Registration needs no password. Caller checks protect operations relative to that supplied identity; this is not real authentication.',
    'The implementation adds case-insensitive Unicode substring search over post text and community names, community listing, and single-post retrieval to support an end-to-end demonstration.'
]),
('REST interface and behavior', [
    'All application endpoints use /api/v1. Requests/responses are JSON. Success has data and request_id fields; failure has error and request_id. Created objects return data.id. Lists use data.posts, data.comments, or data.messages.',
    'POST /users registers username and, for bonus mode, a PEM public_key. GET /users/:name/karma returns received vote total. PUT /users/:name/online updates only the caller. GET /users/:name/public-key returns the registered key.',
    'GET/POST /subreddits lists/creates communities. PUT/DELETE /subreddits/:name/subscription joins/leaves. Creating a community also joins its creator.',
    'POST /posts creates text posts or reposts with community, text, and optional original ID. GET /posts/:id downloads a post. GET/POST /posts/:id/comments reads the thread or adds comments with optional parent ID.',
    'PUT /posts/:id/vote and /comments/:id/vote set direction to -1, 0, or 1. A repeated vote is idempotent; changing direction updates author karma by the delta. Self-votes are forbidden.',
    'GET /feed returns posts in joined communities. GET /search?q=... searches globally visible posts. Feed/search/inbox use descending IDs, optional exclusive before cursor, and limit 1-100 (default 20). Thread comments return creation order with parent IDs.',
    'POST /messages sends to a recipient, including offline recipients. POST /messages/:id/replies permits only the recipient to reply. GET /inbox returns only the caller\'s received messages. Reconnect preserves subscriptions and messages.',
    'Statuses: 200 reads/updates; 201 creation; 400 invalid requests/keys/signatures; 403 forbidden/offline; 404 missing; 405 unsupported method; 409 duplicate; 422 download integrity failure; 503 engine unavailable; 504 engine timeout.',
    'Names/text must be nonempty UTF-8 after trimming and at most 10,000 bytes. Request bodies are capped at 64 KiB. Malformed JSON, IDs, or limits receive errors without crashing the HTTP service. Mutations are never automatically retried.',
    'The README provides exact methods, JSON fields, CLI commands, curl examples, and response shapes for every resource.'
]),
('Running and demonstrating the project', [
    'Install Erlang/OTP 27+ with compiler, development headers, EUnit, inets, public_key, and crypto. Put escript on PATH. The scripts/project4 launcher also recognizes a user-local Erlang installation. Use Python 3 only for report/package commands.',
    'Build and run: ./scripts/project4 build; ./scripts/project4 test; ./scripts/project4 server --mode base. Use separate terminals for Alice and Bob.',
    'Alice: ./scripts/project4 client --user alice --verbose register alice; then create erlang; then post erlang "Hello REST" using the same client prefix.',
    'Bob: register bob; join erlang; feed; search REST; vote post 1 1. Alice or Bob can inspect karma alice. Comments support arbitrary nesting via parent IDs.',
    'Use --url http://127.0.0.1:8081 for another port. The interactive shell accepts JSON arrays of command arguments, such as ["feed"] or ["post","erlang","Hello"].',
    'Automated multi-process demos: ./scripts/project4 demo base and ./scripts/project4 demo bonus. Each starts a fresh ephemeral server, launches independent client OS processes, runs all supported features, and asserts concurrent repeated votes preserve karma one.',
    'Server logs include request ID, method, path, username, status, and elapsed microseconds. Verbose clients print the actual HTTP method/URL and returned status/JSON, including matching request IDs.',
    'docs/VIDEO_GUIDE.md contains a timed approximately five-minute main demo, exact commands and expected IDs, narration, a separate bonus walkthrough, and recording/upload instructions.'
]),
('Bonus signature design', [
    'Client keys use RSA-2048 with public exponent 65537. Signatures use SHA-256 and PKCS#1 v1.5 through OTP public_key/crypto. Private keys are generated locally with permissions 0600; only public keys and post signatures cross the REST API.',
    'Registration in bonus mode requires a valid RSA-2048 public key. It is stored with the account and cannot be replaced. Other registered online users retrieve it through GET /users/:name/public-key.',
    'The exact signed bytes are UTF-8 OTP JSON encoding of the fixed ordered array [1, author, community, exact_text, original_id_or_null]. Version and fixed field order avoid map-order ambiguity. Text is not normalized before signing.',
    'The posting CLI reads its private PEM, signs locally, and sends a Base64 signature with the post. A repost signs its own author, text, destination community, and source ID.',
    'The engine verifies the signature before creating the post and stores post/signature atomically. Bonus mode rejects unsigned and invalidly signed posts. Base mode preserves the original unsigned behavior.',
    'Every post returned through detail, feed, or search is checked on the server. A failure produces HTTP 422. The bonus CLI separately fetches each author\'s public key over HTTP, checks each returned post, and prints SIGNATURE verified or fails.',
    'Server ID and mutable score are excluded from the signed payload; voting therefore preserves content signatures. The signed fields protect content integrity relative to the server-provided key. They do not authenticate unsigned operations, provide key certification, or prevent replay.',
    'Bonus demo: keygen local key directories; start server --mode bonus; register each public PEM; post with --key PRIVATE_PEM; read with --bonus and observe key lookup and verification. See the video guide for complete commands.'
]),
('Validation evidence and limitations', [
    'Base regression and HTTP suite: ' + base_summary + '.',
    'Bonus suite: ' + bonus_summary + '.',
    'Base multi-process demo: ' + demo_summary(base_demo, 'base') + '.',
    'Bonus multi-process demo: ' + demo_summary(bonus_demo, 'bonus') + '.',
    archive_summary,
    'Evidence is preserved in evidence/base-tests.log, bonus-tests.log, base-demo.log, and bonus-demo.log. These are actual executions, not expected-output examples.',
    'Base checks cover registration, membership, nested comments, reposts, vote/karma updates, pagination, private inboxes, replies, offline delivery, search, malformed input, engine timeout (504), and unavailable engine (503).',
    'Bonus checks cover wrong/malformed keys, invalid/missing signatures, changes to all signed fields, valid reposts, score changes, server-side tampering on detail/feed/search, and independent client rejection of changed downloaded text. Test-only OTP state replacement injects corruption; no corruption endpoint is exposed.',
    'The local OTP 29.1.2 installation initially lacked crypto. Validation used a locally built OTP crypto application linked against OpenSSL 3.5.4 in an excluded build/runtime overlay. Submitted sources require a complete OTP installation and contain no native binaries.',
    'Limits: in-memory data, single serialized engine bottleneck, trusted identities, no TLS/persistence, no replay prevention/key rotation, and no signatures on comments/messages. Public-key lookup trusts the server; there is no PKI. This submission makes no new performance-capacity claims.',
    'Recording and YouTube upload remain group tasks. Add videos/main.mp4 and videos/bonus.mp4, enter real links in config/submission.json, regenerate the report, and run package --final. Final packaging rejects missing video files or links.'
]),
('Submission and references', [
    'Submit report.pdf separately from both code archives. project4.zip defaults to base mode and includes the main MP4 when supplied. project4-bonus.zip defaults to bonus mode and includes the separate bonus MP4 when supplied. Each archive is self-contained.',
    'Both archives include source, tests, scripts, team configuration, README, video documentation, and test/demo evidence. They exclude this report PDF, private PEM files, runtime/build artifacts, and Project 4.1 benchmark results.',
    'SUBMISSION_COMMENT.txt is generated from the two members\' configuration and video links. Paste it into the single group Canvas submission. Pending links are explicitly marked rather than invented.',
    'Main video: ' + links['main'],
    'Bonus video: ' + links['bonus'],
    '',
    'References:',
    'OTP HTTP server callback interface: https://www.erlang.org/doc/apps/inets/httpd.html',
    'OTP HTTP client: https://www.erlang.org/doc/apps/inets/httpc.html',
    'OTP public-key library: https://www.erlang.org/doc/apps/public_key/public_key.html',
    'OTP gen_server: https://www.erlang.org/doc/apps/stdlib/gen_server.html',
    'Reddit API structure reference: https://www.reddit.com/dev/api/'
])]

# Also preserve readable report source for review/editing.
markdown = '\n\n'.join('## ' + title + '\n\n' + '\n\n'.join(paragraphs) for title, paragraphs in sections)
(ROOT / 'docs/REPORT.md').write_text(markdown + '\n')
comment = 'Project 4.2 group submission\n\n' + '\n'.join(f'{n} | {e} | UFID {u}' for n, e, u in members)
comment += '\n\nMain demo YouTube: ' + links['main'] + '\nBonus demo YouTube: ' + links['bonus']
comment += '\n\nAttachments: report.pdf (separate), project4.zip, project4-bonus.zip.\n'
(ROOT / 'SUBMISSION_COMMENT.txt').write_text(comment)

# Simple searchable multi-page PDF with built-in fonts and link annotations.
def ascii_text(s):
    return s.encode('ascii', 'replace').decode('ascii')

def literal(s):
    return ascii_text(s).replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')

pages = []
for title, paragraphs in sections:
    lines = []
    for paragraph in paragraphs:
        lines.extend(textwrap.wrap(ascii_text(paragraph), width=92, break_long_words=True) or [''])
        lines.append('')
    for offset in range(0, len(lines), 51):
        pages.append((title + (' (continued)' if offset else ''), lines[offset:offset + 51]))
objects = []
def obj(data):
    objects.append(data.encode('ascii') if isinstance(data, str) else data)
    return len(objects)
catalog = obj('')
pages_id = obj('')
font = obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
font_bold = obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>')
page_ids = []
for i, (title, lines) in enumerate(pages, 1):
    commands = ['BT', '/F2 13 Tf', '48 751 Td', f'({literal(title)}) Tj', 'ET', 'BT', '/F1 10 Tf', '12 TL', '48 725 Td']
    for line in lines:
        commands.extend([f'({literal(line)}) Tj', 'T*'])
    commands.extend(['ET', 'BT', '/F1 9 Tf', '48 35 Td', f'(Project 4.2 | Page {i} of {len(pages)}) Tj', 'ET'])
    stream = '\n'.join(commands).encode('ascii')
    content = obj(b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'\nendstream')
    annotations = []
    for j, line in enumerate(lines):
        for url in re.findall(r'https?://\S+', line):
            y = 725 - j * 12
            annotations.append(obj(f'<< /Type /Annot /Subtype /Link /Rect [48 {y-2} 565 {y+10}] /Border [0 0 0] /A << /S /URI /URI ({literal(url)}) >> >>'))
    annots = ' /Annots [' + ' '.join(f'{a} 0 R' for a in annotations) + ']' if annotations else ''
    page_ids.append(obj(f'<< /Type /Page /Parent {pages_id} 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {font} 0 R /F2 {font_bold} 0 R >> >> /Contents {content} 0 R{annots} >>'))
objects[catalog-1] = f'<< /Type /Catalog /Pages {pages_id} 0 R >>'.encode()
objects[pages_id-1] = ('<< /Type /Pages /Kids [' + ' '.join(f'{p} 0 R' for p in page_ids) + f'] /Count {len(pages)} >>').encode()
pdf = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
offsets = [0]
for n, data in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf += f'{n} 0 obj\n'.encode() + data + b'\nendobj\n'
xref = len(pdf)
pdf += f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode()
for offset in offsets[1:]:
    pdf += f'{offset:010d} 00000 n \n'.encode()
pdf += f'trailer\n<< /Size {len(objects)+1} /Root {catalog} 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
(ROOT / 'report.pdf').write_bytes(pdf)
print(f'Generated report.pdf ({len(pages)} pages), docs/REPORT.md, and SUBMISSION_COMMENT.txt')
if any('PENDING' in v for v in links.values()):
    print('YouTube links are pending: update config/submission.json after recording.')
