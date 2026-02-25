const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;
const head = @import("../common/types.zig");

const types = @import("types.zig");
const Request = types.Request;
const RequestLine = types.RequestLine;
const HeaderParseResult = types.HeaderParseResult;

const SEPERATOR = "\r\n";
const ENDOFHEADER = "\r\n\r\n";

pub fn parseRequest(allocator: Allocator, stream: anytype) !Request {
    // this is nginx default so it safe to use idk
    const MAX_HEADER_SIZE = 8192;

    const requestHeader: HeaderParseResult = try parseRequestHeader(allocator, stream, MAX_HEADER_SIZE);

    const contentLength = getContentLength(requestHeader.headers) orelse 0;

    // no body
    if (contentLength == 0) {
        return Request{ .headers = requestHeader.headers, .requestLine = requestHeader.requestline, .body = null };
    }

    var bodyBuffer: ArrayList(u8) = .empty;
    defer bodyBuffer.deinit(allocator);

    // add leftover
    if (requestHeader.leftover) |leftover| {
        try bodyBuffer.appendSlice(allocator, leftover);
        allocator.free(leftover);
    }

    // read all data left
    var tempChunk: [512]u8 = undefined;
    while (bodyBuffer.items.len < contentLength) {
        const remaining = contentLength - bodyBuffer.items.len;
        const toRead = @min(remaining, tempChunk.len);

        const bytesRead = try stream.read(tempChunk[0..toRead]);
        if (bytesRead == 0) {
            return error.UnexpectedEndOfStream;
        }

        try bodyBuffer.appendSlice(allocator, tempChunk[0..bytesRead]);
    }

    const body = try allocator.dupe(u8, bodyBuffer.items);

    return Request{ .headers = requestHeader.headers, .requestLine = requestHeader.requestline, .body = body };
}

fn getContentLength(headers: []const head.Header) ?usize {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.key, "content-length")) {
            return std.fmt.parseInt(usize, header.value, 10) catch null;
        }
    }
    return null;
}

fn parseRequestHeader(allocator: Allocator, stream: anytype, maxheadersize: u32) !HeaderParseResult {
    var buffer: ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    const headerEndPos = try readUntilDoubleNewline(allocator, stream, &buffer, maxheadersize);

    // headerPart of data
    const headerData = buffer.items[0..headerEndPos];

    const bodyStartPos = headerEndPos + 4; // \r\n\r\n = 4 byte

    // buffer can read more than header so we need to check leftover
    const leftover = if (bodyStartPos < buffer.items.len)
        buffer.items[bodyStartPos..]
    else
        null;

    var lines = std.mem.splitAny(u8, headerData, SEPERATOR);

    // if no line then return error
    const requestLineStr = lines.next() orelse return error.EmptyRequest;

    const requestLine = try parseRequestLine(allocator, requestLineStr);

    var headers: ArrayList(head.Header) = .empty;
    defer headers.deinit(allocator);

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const header = try parseHeaderLine(allocator, line);
        try headers.append(allocator, header);
    }

    return HeaderParseResult{
        .requestline = requestLine,
        .headers = try allocator.dupe(head.Header, headers.items),
        .leftover = if (leftover) |value| try allocator.dupe(u8, value) else null,
    };
}

fn parseHeaderLine(allocator: Allocator, headerLine: []const u8) !head.Header {
    var splited = std.mem.splitSequence(u8, headerLine, ": ");

    const key = splited.next() orelse return error.MalformedRequestLine;
    const value = splited.next() orelse return error.MalformedRequestLine;

    return head.Header{ .key = try allocator.dupe(u8, key), .value = try allocator.dupe(u8, value) };
}

fn parseRequestLine(allocator: Allocator, line: []const u8) !RequestLine {
    var parts = std.mem.splitAny(u8, line, " ");

    const method = parts.next() orelse return error.MalformedRequestLine;
    const target = parts.next() orelse return error.MalformedRequestLine;
    const version = parts.next() orelse return error.MalformedRequestLine;

    if (parts.next() != null) {
        return error.MalformedRequestLine;
    }
    // RFC 9112, Section 2.3: HTTP-version = HTTP-name "/" DIGIT "." DIGIT
    if (!std.mem.startsWith(u8, version, "HTTP/")) {
        return error.InvalidHttpVersion;
    }

    return RequestLine{
        .method = try allocator.dupe(u8, method),
        .requestTarget = try allocator.dupe(u8, target),
        .httpVersion = try allocator.dupe(u8, version),
    };
}

fn readUntilDoubleNewline(allocator: Allocator, stream: anytype, buffer: *ArrayList(u8), maxheadersize: u32) !usize {
    var tempChunk: [512]u8 = undefined;

    while (true) {
        const bytesRead = try stream.read(&tempChunk);

        if (bytesRead == 0) {
            return error.UnexpectedEndOfStream;
        }

        // add to bufer
        try buffer.appendSlice(allocator, tempChunk[0..bytesRead]);

        if (buffer.items.len > maxheadersize) {
            return error.HeaderTooLarge;
        }

        if (std.mem.indexOf(u8, buffer.items, ENDOFHEADER)) |pos| {
            return pos;
        }
    }
}

test "parse simple GET request" {
    const allocator = std.testing.allocator;

    // 1. Fake request data
    const requestData = "GET /hello HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "\r\n";
    var fbs = std.io.fixedBufferStream(requestData);
    const reader = fbs.reader();

    var lines = try parseRequest(allocator, reader);
    defer lines.deinit(allocator);

    try std.testing.expectEqualStrings("HTTP/1.1", lines.requestLine.httpVersion);
    try std.testing.expectEqualStrings("GET", lines.requestLine.method);
    try std.testing.expectEqualStrings("/hello", lines.requestLine.requestTarget);
    try std.testing.expectEqualStrings("Host", lines.headers[0].key);
    try std.testing.expectEqualStrings("localhost", lines.headers[0].value);
    try std.testing.expect(lines.body == null);
}

test "parse simple POST request" {
    const allocator = std.testing.allocator;

    const body = "{\"username\":\"test\"}";
    const requestData = "POST /api/login HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 19\r\n" ++
        "\r\n" ++
        body;

    var fbs = std.io.fixedBufferStream(requestData);
    const reader = fbs.reader();

    var request = try parseRequest(allocator, reader);
    defer request.deinit(allocator);

    try std.testing.expectEqualStrings("POST", request.requestLine.method);
    try std.testing.expectEqualStrings("/api/login", request.requestLine.requestTarget);
    try std.testing.expectEqualStrings("HTTP/1.1", request.requestLine.httpVersion);
    try std.testing.expect(request.body != null);
    try std.testing.expectEqualStrings(body, request.body.?);
}
