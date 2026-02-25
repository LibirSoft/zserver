const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const reqParser = @import("./request/request.zig");
const request = @import("./request/types.zig");
const res = @import("response/types.zig");
const comm = @import("common/types.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator: Allocator = gpa.allocator();

    const port: u32 = 3000;

    const address = try std.net.Address.parseIp("127.0.0.1", port);

    const tpe: u32 = posix.SOCK.STREAM;
    const protocol: comptime_int = posix.IPPROTO.TCP;
    const listener: posix.socket_t = try posix.socket(address.any.family, tpe, protocol);
    defer posix.close(listener);

    // option to re use address thi need to be stop and start without getting an error
    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    // bind our socket to address we created.
    try posix.bind(listener, &address.any, address.getOsSockLen());
    // finally ve can listen (if we want to be client, We can use `.connect` for connecting), with 128 backlog
    try posix.listen(listener, 4096);

    // here we go boys we start rolling

    std.debug.print("Server running at http://localhost:{} \n", .{port});

    try printAddress(listener);

    while (true) {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err| {
            std.debug.print("error accept: {any}\n", .{err});
            continue;
        };
        defer posix.close(socket);

        // std.debug.print("socket connected on port: {any} \n", .{client_address.getPort()});

        const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };
        // read timeout 2.5 sec
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));

        // write timeout
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

        const stream = std.net.Stream{ .handle = socket };

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = stream.writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        var response: ?res.Response = null;
        defer if (response) |*r| r.deinit(allocator);

        var req: ?request.Request = reqParser.parseRequest(allocator, stream) catch |err| blk: {
            std.debug.print("request parse error: {any}\n", .{err});

            break :blk null;
        };
        defer if (req) |*valreq| {
            valreq.deinit(allocator);
        };

        if (req) |valreq| {
            std.debug.print("value: {any}\n", .{valreq});
            var builder = res.ResponseBuilder.init(allocator, 200, "OK");
            _ = try builder.addHeader(comm.Header{ .key = "x-test-header", .value = "test" });
            _ = try builder.addBody("Hey this is my first response!");

            response = try builder.build();
        } else {
            var builder = res.ResponseBuilder.init(allocator, 400, "Bad Request");
            response = try builder.build();
        }

        if (response) |*r| {
            try r.serialize(stdout);
        }
    }
}

fn printAddress(socket: posix.socket_t) !void {
    var address: std.net.Address = undefined;
    var len: posix.socklen_t = @sizeOf(net.Address);

    try posix.getsockname(socket, &address.any, &len);
    std.debug.print("{any}\n", .{address.getPort()});
}
