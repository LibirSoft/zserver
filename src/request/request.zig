const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;
const head = @import("../common/types.zig");

const types = @import("types.zig");
const Request = types.Request;
const RequestLine = types.RequestLine;
const ConnectionState = @import("../server/types.zig").ConnectionState;
const HeaderParseResult = types.HeaderParseResult;
const StreamState = @import("../server/types.zig").StreamState;

const SEPERATOR = "\r\n";
const ENDOFHEADER = "\r\n\r\n";

pub fn streamRequestoBuffer(stream: anytype, connectionState: *ConnectionState) !StreamState {
    const MAX_HEADER_SIZE = 4096;
    const rd = &connectionState.read_data;

    const read_slice = if (rd.read_byte_target == 0)
        rd.read_buffer[rd.bytes_read..]
    else
        rd.read_buffer[rd.bytes_read..rd.read_byte_target];

    const bytesRead = try stream.read(read_slice);

    if (bytesRead == 0) return error.UnexpectedEndOfStream;
    if (rd.read_buffer.len > MAX_HEADER_SIZE) return error.HeaderTooLarge;

    rd.bytes_read += bytesRead;

    // already reading body, check if we got all of it
    if (rd.read_byte_target > 0 and rd.bytes_read >= rd.read_byte_target) {
        return .READY;
    }

    const data = rd.read_buffer[0..rd.bytes_read];

    if (std.mem.indexOf(u8, data, ENDOFHEADER)) |header_end_pos| {
        rd.header_pos = header_end_pos;

        if (std.mem.indexOf(u8, data, "Content-Length: ")) |cl_pos| {
            const value_slice = rd.read_buffer[cl_pos + 16 .. header_end_pos];
            const cr_pos = std.mem.indexOf(u8, value_slice, "\r") orelse return error.MalformedHeader;
            const length = try std.fmt.parseInt(usize, value_slice[0..cr_pos], 10);

            rd.read_byte_target = header_end_pos + 4 + length;
            rd.have_body = true;

            if (rd.bytes_read >= rd.read_byte_target) return .READY;
        } else {
            return .READY;
        }
    }

    return .NEED_MORE;
}

pub fn parseRequest(allocator: Allocator, buffer: []const u8, header_pos: usize, have_body: bool) !Request {
    const header_data = buffer[0..header_pos];

    const body_start = header_pos + 4;
    const body: ?[]const u8 = if (have_body)
        buffer[body_start..]
    else
        null;

    var lines = std.mem.splitSequence(u8, header_data, SEPERATOR);

    // first line is Request line so here we go
    const request_line_str = lines.next() orelse return error.EmptyRequest;
    const request_line = try parseRequestLine(request_line_str);

    var header_count: usize = 0;
    var counter = lines;
    while (counter.next()) |line| {
        if (line.len > 0) header_count += 1;
    }

    // alloc memory for headers one time
    const headers = try allocator.alloc(head.Header, header_count);

    // parse headers line by line
    var i: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        headers[i] = try parseHeaderLine(line);
        i += 1;
    }

    return Request{
        .requestLine = request_line,
        .headers = headers,
        .body = body,
    };
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

fn parseHeaderLine(headerLine: []const u8) !head.Header {
    var splited = std.mem.splitSequence(u8, headerLine, ": ");

    const key = splited.next() orelse return error.MalformedRequestLine;
    const value = splited.next() orelse return error.MalformedRequestLine;

    return head.Header{ .key = key, .value = value };
}
fn parseRequestLine(line: []const u8) !RequestLine {
    var parts = std.mem.splitScalar(u8, line, ' ');

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
        .method = method,
        .requestTarget = target,
        .httpVersion = version,
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
