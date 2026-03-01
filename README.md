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

## TODO

- [ ] Static file serving
- [ ] epoll (non-blocking I/O)
- [ ] Zero-copy parsing
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
