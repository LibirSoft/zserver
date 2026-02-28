const Allocator = @import("std").mem.Allocator;
const HttpMethod = @import("../common/types.zig").HttpMethod;
const Request = @import("../request/types.zig").Request;
const Response = @import("../response/types.zig").Response;

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
