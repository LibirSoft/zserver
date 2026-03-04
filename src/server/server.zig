const std = @import("std");
const net = std.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const Route = @import("types.zig").Route;
const StreamState = @import("types.zig").StreamState;
const HandlerFn = @import("types.zig").HandlerFn;
const SocketState = @import("types.zig").SocketState;
const ConnectionState = @import("types.zig").ConnectionState;
const HttpMethod = @import("../common/types.zig").HttpMethod;
const ArrayList = std.ArrayList;
const parseRequest = @import("../request/request.zig").parseRequest;
const readRequestStream = @import("../request/request.zig").readRequestStream;
const Request = @import("../request/types.zig").Request;
const streamRequestoBuffer = @import("../request/request.zig").streamRequestoBuffer;
const Response = @import("../response/types.zig").Response;
const ResponseBuilder = @import("../response/types.zig").ResponseBuilder;
const streamResponseToSocket = @import("../response/response_utils.zig").streamResponseToSocket;

pub const Server = struct {
    allocator: Allocator,
    routes: ArrayList(Route),
    address: []const u8,
    port: u16,
    notFoundHandler: ?HandlerFn,

    pub fn init(allocator: Allocator, port: ?u16, address: ?[]const u8) Server {
        const realPort: u16 = if (port) |val| val else 3000;
        const realAddres: []const u8 = if (address) |val| val else "127.0.0.1";

        return Server{
            .allocator = allocator,
            .address = realAddres,
            .port = realPort,
            .routes = .empty,
            .notFoundHandler = null,
        };
    }

    pub fn listen(self: *Server) !void {
        const address = try std.net.Address.parseIp(self.address, self.port);

        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
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

        std.debug.print("Server running at http://{s}:{} \n", .{ self.address, self.port });

        const epfd = try posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC);

        // add listener to epoll
        //
        var listenerEvent = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN,
            .data = .{ .fd = listener },
        };

        try posix.epoll_ctl(epfd, std.os.linux.EPOLL.CTL_ADD, listener, &listenerEvent);

        // epoll events
        var events: [1024]std.os.linux.epoll_event = undefined;

        // hasmap for socketStates
        var connections = std.AutoHashMap(i32, ConnectionState).init(self.allocator);
        defer connections.deinit();

        while (true) {
            // now we got sockets
            const n = posix.epoll_wait(epfd, &events, -1);

            for (events[0..n]) |event| {
                var client_address: net.Address = undefined;
                var client_address_len: posix.socklen_t = @sizeOf(net.Address);

                // if new connection
                if (event.events == std.os.linux.EPOLL.IN and event.data.fd == listener) {
                    const socket = posix.accept(listener, &client_address.any, &client_address_len, posix.SOCK.NONBLOCK) catch |err| {
                        std.debug.print("error accept: {any}\n", .{err});
                        continue;
                    };

                    var client_event = std.os.linux.epoll_event{ .events = std.os.linux.EPOLL.IN, .data = .{ .fd = socket } };

                    try posix.epoll_ctl(epfd, std.os.linux.EPOLL.CTL_ADD, socket, &client_event);

                    // ad it to hasmap so we can track status

                    if (connections.getPtr(socket)) |connectionState| {
                        if (connectionState.usable == true) {
                            connectionState.clear(self.allocator);
                        }
                    } else {
                        try connections.put(socket, ConnectionState.init(socket));
                    }
                } else {
                    const socket = event.data.fd;

                    if (connections.getPtr(socket)) |connectionState| {
                        self.stateMachine(epfd, connectionState) catch |err| {
                            std.debug.print("state machine error: {any}\n", .{err});
                            connectionState.state = .DONE;
                        };
                    }
                }
            }
        }
    }

    pub fn addNotFoundHandler(self: *Server, handler: HandlerFn) *Server {
        self.notFoundHandler = handler;
        return self;
    }

    pub fn add(self: *Server, route: Route) *Server {
        self.routes.append(self.allocator, route) catch {
            std.debug.print("Upsie we faild to add route sory :(", .{});
        };
        return self;
    }

    pub fn get(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.GET, .path = path, .handler = handler };
        _ = self.add(route);
        return self;
    }

    pub fn post(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.POST, .path = path, .handler = handler };
        self.add(route);
        return self;
    }

    pub fn put(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.PUT, .path = path, .handler = handler };
        self.add(route);
        return self;
    }

    pub fn delete(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.DELETE, .path = path, .handler = handler };
        self.add(route);
        return self;
    }

    pub fn patch(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.PATCH, .path = path, .handler = handler };
        self.add(route);
        return self;
    }

    pub fn head(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.HEAD, .path = path, .handler = handler };
        self.add(route);
        return self;
    }

    pub fn options(
        self: *Server,
        path: []const u8,
        handler: HandlerFn,
    ) *Server {
        const route: Route = Route{ .method = HttpMethod.OPTIONS, .path = path, .handler = handler };
        self.add(route);
        return self;
    }

    pub fn deinit(self: *Server) void {
        self.routes.deinit(self.allocator);
    }

    fn printAddress(socket: posix.socket_t) !void {
        var address: std.net.Address = undefined;
        var len: posix.socklen_t = @sizeOf(net.Address);

        try posix.getsockname(socket, &address.any, &len);
        std.debug.print("{any}\n", .{address.getPort()});
    }

    fn dispatch(self: *Server, request: Request, response: *?Response) void {
        for (self.routes.items) |route| {
            // if method not match continue
            const method = HttpMethod.fromString(request.requestLine.method) orelse continue;
            if (method != route.method) continue;

            // if path not match continue
            if (!std.mem.eql(u8, request.requestLine.requestTarget, route.path)) continue;

            if (route.handler(self.allocator, request)) |result| {
                response.* = result;
                return;
            } else |_| {
                var builder = ResponseBuilder.init(self.allocator, 500, "Internal Server Error");
                response.* = builder.build() catch return;
                return;
            }
        }

        var builder = ResponseBuilder.init(self.allocator, 404, "Not Found");
        response.* = builder.build() catch return;
    }

    fn stateMachine(self: *Server, epfd: i32, connection: *ConnectionState) !void {
        const state: SocketState = connection.state;

        _ = switch (state) {
            .READING => {
                // read here
                connection.usable = false;

                const stream = std.net.Stream{ .handle = connection.fd };
                const read_state: StreamState = try streamRequestoBuffer(stream, &connection.read_buffer, &connection.bytes_read, &connection.read_byte_target);

                // then we can strat dispatch and create response
                if (read_state == .READY) {
                    var bufferStream = std.io.fixedBufferStream(connection.read_buffer[0..connection.bytes_read]);

                    var response: ?Response = null;
                    defer if (response) |*r| r.deinit(self.allocator);

                    var req: ?Request = parseRequest(self.allocator, &bufferStream) catch |err| blk: {
                        std.debug.print("request parse error: {any}\n", .{err});

                        break :blk null;
                    };

                    defer if (req) |*valreq| {
                        valreq.deinit(self.allocator);
                    };

                    if (req) |valreq| {
                        self.dispatch(valreq, &response);
                    } else {
                        var builder = ResponseBuilder.init(self.allocator, 400, "Bad Request");
                        response = try builder.build();
                    }

                    // now we got response we can safely turn writing state
                    connection.state = .WRITING;
                    if (response) |*val_res| {
                        var writer_array: ArrayList(u8) = .empty;

                        const writer = writer_array.writer(self.allocator);
                        try val_res.serialize(writer);
                        connection.response_bytes = try writer_array.toOwnedSlice(self.allocator);

                        var client_event = std.os.linux.epoll_event{ .events = std.os.linux.EPOLL.OUT, .data = .{ .fd = connection.fd } };

                        try posix.epoll_ctl(epfd, std.os.linux.EPOLL.CTL_MOD, connection.fd, &client_event);
                    }
                }
            },
            .WRITING => {
                // create request object Than dispatch it and resolve response
                if (connection.response_bytes) |response| {
                    const write_state: StreamState = streamResponseToSocket(connection.fd, response, &connection.bytes_sent) catch |err| {
                        if (err == std.posix.WriteError.WouldBlock) return;
                        connection.state = .DONE;
                        return;
                    };

                    if (write_state == StreamState.READY) {
                        connection.state = .DONE;
                    }
                }
            },
            .DONE => {
                try posix.epoll_ctl(epfd, std.os.linux.EPOLL.CTL_DEL, connection.fd, null);
                posix.close(connection.fd);
                connection.clear(self.allocator);
            },
        };
    }
};
