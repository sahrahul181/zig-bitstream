const std = @import("std");

/// Which end of a multi-byte integer the most significant bit occupies.
pub const Endian = enum {
    /// Most significant byte at the lowest address (network byte order).
    Big,
    /// Most significant byte at the highest address (x86 default).
    Little,

    /// Returns the endianness of the current compile target.
    pub fn native() Endian {
        return switch (@import("builtin").cpu.arch.endian()) {
            .big => .Big,
            .little => .Little,
        };
    }

    /// True when the value equals the compile-target's native endianness.
    pub fn isNative(self: Endian) bool {
        return self == Endian.native();
    }
};

// ---------------------------------------------------------------------------
// Compile-time byte-swap helpers
// ---------------------------------------------------------------------------

/// Swap the bytes of an integer at comptime or runtime.
/// `T` must be an unsigned integer type whose bit-width is a multiple of 8.
pub fn byteSwap(comptime T: type, value: T) T {
    return @byteSwap(value);
}

/// Convert `value` from `src` endianness to `dst` endianness.
pub fn convertEndian(comptime T: type, value: T, src: Endian, dst: Endian) T {
    if (src == dst) return value;
    return byteSwap(T, value);
}

/// Convert a native-endian integer to the requested wire endianness.
pub fn toWire(comptime T: type, value: T, endian: Endian) T {
    return convertEndian(T, value, Endian.native(), endian);
}

/// Convert a wire-endian integer to native byte order.
pub fn fromWire(comptime T: type, value: T, endian: Endian) T {
    return convertEndian(T, value, endian, Endian.native());
}

// ---------------------------------------------------------------------------
// Slice helpers
// ---------------------------------------------------------------------------

/// Read a `T` from `buf[0..@sizeOf(T)]` with the given endianness.
/// The caller guarantees `buf.len >= @sizeOf(T)`.
pub fn readInt(comptime T: type, buf: []const u8, endian: Endian) T {
    const raw = std.mem.readInt(T, buf[0..@sizeOf(T)], .little);
    return if (endian == .Little) raw else @byteSwap(raw);
}

/// Write `value` into `buf[0..@sizeOf(T)]` with the given endianness.
/// The caller guarantees `buf.len >= @sizeOf(T)`.
pub fn writeInt(comptime T: type, buf: []u8, value: T, endian: Endian) void {
    const wire = toWire(T, value, endian);
    std.mem.writeInt(T, buf[0..@sizeOf(T)], wire, .little);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "byteSwap u16" {
    const v: u16 = 0xABCD;
    try std.testing.expectEqual(@as(u16, 0xCDAB), byteSwap(u16, v));
}

test "byteSwap u32" {
    const v: u32 = 0x01020304;
    try std.testing.expectEqual(@as(u32, 0x04030201), byteSwap(u32, v));
}

test "byteSwap u64" {
    const v: u64 = 0x0102030405060708;
    try std.testing.expectEqual(@as(u64, 0x0807060504030201), byteSwap(u64, v));
}

test "convertEndian noop" {
    const v: u32 = 0xDEADBEEF;
    try std.testing.expectEqual(v, convertEndian(u32, v, .Big, .Big));
    try std.testing.expectEqual(v, convertEndian(u32, v, .Little, .Little));
}

test "readInt / writeInt round-trip" {
    var buf: [4]u8 = undefined;
    const val: u32 = 0xCAFEBABE;
    writeInt(u32, &buf, val, .Big);
    try std.testing.expectEqual(val, readInt(u32, &buf, .Big));
    writeInt(u32, &buf, val, .Little);
    try std.testing.expectEqual(val, readInt(u32, &buf, .Little));
}
