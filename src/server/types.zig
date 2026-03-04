const Allocator = @import("std").mem.Allocator;
const HttpMethod = @import("../common/types.zig").HttpMethod;
const Request = @import("../request/types.zig").Request;
const Response = @import("../response/types.zig").Response;
const posix = @import("std").posix;
/// Handler function type.
///
/// Example usage:
/// ```zig
/// fn handleHelloWorld(allocator: Allocator, req: Request) anyerror!Response {
///     _ = req;
///     var builder = ResponseBuilder.init(allocator, 200, "OK");
///     _ = try builder.addHeader(.{ .key = "Content-Type", .value = "text/plain" });
///     _ = builder.addBody("Hello World!");
///     return try builder.build();
/// }
/// ```
pub const HandlerFn = *const fn (Allocator, Request) anyerror!Response;

pub const Route = struct {
    method: HttpMethod,
    path: []const u8,
    handler: HandlerFn,
};

pub const SocketState = enum {
    READING,
    WRITING,
    DONE,
};

pub const StreamState = enum {
    NEED_MORE,
    READY,
};

pub const ConnectionState = struct {
    state: SocketState = SocketState.READING,
    read_buffer: [4096]u8 = undefined,
    bytes_read: usize = 0,
    read_byte_target: usize = 0,
    response_bytes: ?[]const u8 = null,
    bytes_sent: usize = 0,
    usable: bool = true,
    fd: posix.socket_t,

    pub fn init(fd: posix.socket_t) ConnectionState {
        return ConnectionState{
            .fd = fd,
        };
    }

    pub fn clear(self: *ConnectionState, allocator: Allocator) void {
        self.usable = true;
        self.state = SocketState.READING;
        self.bytes_read = 0;
        self.bytes_sent = 0;
        self.read_byte_target = 0;

        if (self.response_bytes) |responseBytes| {
            allocator.free(responseBytes);
            self.response_bytes = null;
        }
    }
};
