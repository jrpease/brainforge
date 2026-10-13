# Gate fixtures

Recorded responses for the offline gate tests, served by `tests/lib/curl-stub.sh`.
One directory per HTTP adapter (`figma/`, `website/`, `monday/`, `ga/`), each holding `*.http`
files. Use invented names only; the repo is public. `gate-github.sh` is tested in
`tests/gate-github.test.sh` against a local bare origin, so there are no HTTP fixtures for it.

A fixture looks like this:

```
# match: POST ^https://api\.monday\.com/v2$ "ids":\["1","2"\]
# status: 200
# header: ETag: "abc"
{"data":{"boards":[]}}
```

- Line 1 is required: `# match: <METHOD> <URL-regex> [<body-regex>]`. The URL regex has no spaces;
  everything after it is the body regex. Both are `grep -E` patterns. A request with `-d` and no `-X`
  is a `POST`.
- `# status: <code>` is optional (default 200). `# header: <Name: value>` lines are optional and are
  written to the `-D` file.
- Everything after those lines is the response body.
- A 3xx fixture with a `# header: Location: <url>` line is followed when the caller passes `-L`,
  as curl does: each hop is logged, every hop's headers go to `-D` in order, and `-w`/`-o` get the
  last hop's. Without a `Location` line, or without `-L`, the 3xx is the final response.
- The first fixture (glob order) that matches wins, so put specific ones in names that sort first.
- No match: the stub exits 7, which is curl's "couldn't connect". A missing fixture reads as offline,
  never as success.
- Each call is appended to `$CURL_STUB_DIR/calls.log` as tab-separated
  `METHOD  URL  headers  body`, so tests can count calls and assert on headers or body.
