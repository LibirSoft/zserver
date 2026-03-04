const std = @import("std");
const Allocator = std.mem.Allocator;
const Server = @import("./server/server.zig").Server;
const Request = @import("request/types.zig").Request;
const Response = @import("response/types.zig").Response;
const ResponseBuilder = @import("response/types.zig").ResponseBuilder;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator: Allocator = gpa.allocator();

    var server = Server.init(allocator, 3000, "127.0.0.1");

    _ = server.get("/", handleHelloWorld);

    _ = server.get("/test", testHandler);

    try server.listen();
}

fn handleHelloWorld(allocator: Allocator, req: Request) anyerror!Response {
    _ = req;
    var builder = ResponseBuilder.init(allocator, 200, "OK");
    _ = builder.addBody("Hello from home!\n");
    _ = try builder.addHeader(.{ .key = "Connection", .value = "close" });
    return try builder.build();
}

fn testHandler(allocator: Allocator, req: Request) anyerror!Response {
    _ = req;
    var builder = ResponseBuilder.init(allocator, 200, "OK");
    _ = builder.addBody("This is a test hanndler!\n");
    return try builder.build();
}
