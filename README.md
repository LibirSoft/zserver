# ZServer

A simple HTTP/1.1 server written from scratch in Zig. Zero external dependencies — pure Zig standard library only. Built for learning purposes.

## Done

- [x] TCP socket server (bind, listen, accept)
- [x] HTTP request parsing (request line, headers, body)
- [x] HTTP response builder (builder pattern)
- [x] Response serialization with bufferedWriter
- [x] Routing system (Express.js style API: `server.get("/", handler)`)
- [x] All HTTP methods (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
- [x] Route dispatch with first-match semantics
- [x] 404 Not Found handling
- [x] 500 Internal Server Error on handler failure
- [x] 400 Bad Request on malformed requests
- [x] Memory management (DebugAllocator, proper deinit/free)
- [x] epoll event loop (non-blocking I/O)
- [x] State machine (READING → WRITING → DONE)
- [x] Connection state tracking (HashMap per fd)
- [x] Non-blocking read with Content-Length body support
- [x] Response serialize to memory buffer (ArrayList writer)
- [x] Non-blocking write with partial write handling
- [x] HTTP/1.1 Keep-alive (connection reuse)
- [x] Zero-copy request parsing (slice-based, no string allocations)
- [x] Fixed buffer response serialization (with heap fallback)
- [x] Tagged union for response memory ownership (ResponseSource)
- [x] Benchmarked: ~151K req/sec (12 threads, 400 connections, 30s)

## Performance Journey

| Milestone | req/sec |
|-----------|---------|
| Blocking I/O | ~6,600 |
| + epoll (non-blocking) | ~20,000 |
| + keep-alive | ~40,000 |
| + dispatch fix + fixed buffer | ~46,000 |
| + zero-copy parsing | ~151,000 |

## TODO

- [ ] Robust error handling (ConnectionReset, UnexpectedEndOfStream graceful handling)
- [ ] Memory pooling (Arena Allocator)
- [ ] Write batching (corking)
- [ ] WebSocket support

## Usage

```bash
zig build          # build
zig build run      # run the server
zig build test     # run tests
```

## Example

```zig
var server = Server.init(allocator, 3000, "127.0.0.1");
_ = server.get("/", handleHelloWorld);
_ = server.get("/test", testHandler);
try server.listen();
```
