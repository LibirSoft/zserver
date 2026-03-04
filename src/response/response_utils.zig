const StreamState = @import("../server/types.zig").StreamState;
const std = @import("std");

pub fn streamResponseToSocket(socket: std.posix.socket_t, buffer: []const u8, bytes_sent: *usize) !StreamState {
    const bytesSent = try std.posix.write(socket, buffer[bytes_sent.*..buffer.len]);

    if (bytesSent == 0) {
        return error.UnexpectedEndOfStream;
    }

    bytes_sent.* += bytesSent;

    // we sent all of it
    if (bytes_sent.* >= buffer.len) {
        return .READY;
    }

    return .NEED_MORE;
}
