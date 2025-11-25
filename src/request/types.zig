const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const RequestLine = struct {
    httpVersion: []const u8,
    requestTarget: []const u8,
    method: []const u8,

    pub fn deinit(self: *RequestLine, allocator: Allocator) void {
        allocator.free(self.httpVersion);
        allocator.free(self.requestTarget);
        allocator.free(self.method);
    }
};
pub const Header = struct {
    key: []const u8,
    value: []const u8,

    pub fn deinit(self: *Header, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const HeaderParseResult = struct {
    requestline: RequestLine,
    headers: []Header,
    // leftover data from reading header
    leftover: ?[]const u8,

    pub fn deinit(self: *HeaderParseResult, allocator: Allocator) void {
        self.headers.deinit();
        self.requestline.deinit(allocator);
        if (self.leftover) |value| {
            self.allocator.free(value);
        }
    }
};

pub const Request = struct {
    requestLine: RequestLine,
    headers: []Header,
    body: ?[]const u8,

    pub fn deinit(self: *Request, allocator: Allocator) void {
        self.requestLine.deinit(allocator);

        for (self.headers) |*header| {
            header.deinit(allocator);
        }

        allocator.free(self.headers);

        if (self.body) |body| {
            allocator.free(body);
        }
    }
};
