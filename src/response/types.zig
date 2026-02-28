const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const head = @import("../common/types.zig");

pub const ResponseLine = struct {
    httpVersion: []const u8 = "HTTP/1.1",
    status: u16,
    reason: []const u8,
};

pub const Response = struct {
    responseLine: ResponseLine,
    headers: []head.Header,
    body: ?[]const u8,

    pub fn serialize(self: *Response, writer: anytype) !void {
        // write Response line
        try writer.writeAll(self.responseLine.httpVersion);
        try writer.writeAll(" ");
        try writer.print("{d}", .{self.responseLine.status});
        try writer.writeAll(" ");
        try writer.writeAll(self.responseLine.reason);
        try writer.writeAll("\r\n");
        // write headers

        for (self.headers) |value| {
            try writeHeader(value, writer);
        }

        // write body and content-length header
        if (self.body) |body| {
            try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
            try writer.writeAll(body);
        } else {
            try writer.writeAll("\r\n");
        }
        try writer.flush();
    }

    fn writeHeader(header: head.Header, writer: anytype) !void {
        try writer.writeAll(header.key);
        try writer.writeAll(": ");
        try writer.writeAll(header.value);
        try writer.writeAll("\r\n");
    }

    pub fn deinit(self: *Response, allocator: Allocator) void {
        allocator.free(self.headers);
    }
};

pub const ResponseBuilder = struct {
    allocator: Allocator,
    status: u16,
    reason: []const u8,
    headers: ArrayList(head.Header),
    body: ?[]const u8,

    pub fn init(allocator: Allocator, status: u16, reason: []const u8) ResponseBuilder {
        return ResponseBuilder{
            .allocator = allocator,
            .status = status,
            .reason = reason,
            .headers = .empty,
            .body = null,
        };
    }

    pub fn addHeader(self: *ResponseBuilder, header: head.Header) !*ResponseBuilder {
        try self.headers.append(self.allocator, header);

        return self;
    }

    pub fn addBody(self: *ResponseBuilder, body: []const u8) *ResponseBuilder {
        self.body = body;
        return self;
    }

    pub fn build(self: *ResponseBuilder) !Response {
        const response = Response{
            .responseLine = ResponseLine{
                .reason = self.reason,
                .status = self.status,
            },
            .headers = try self.headers.toOwnedSlice(self.allocator),
            .body = self.body,
        };

        return response;
    }

    pub fn deinit(self: *ResponseBuilder) void {
        self.headers.deinit(self.allocator);
    }
};
