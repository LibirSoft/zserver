const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Header = struct {
    key: []const u8,
    value: []const u8,

    pub fn deinit(self: *Header, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
}; 
