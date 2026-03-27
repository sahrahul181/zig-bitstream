/// bitstream.zig — Generic, production-grade bit-level stream library for Zig 0.15
///
/// Refactored to support both high-performance slice manipulation AND 
/// generic stream I/O using Zig's powerful compile-time dispatch.

const std = @import("std");
const BitstreamError = @import("error.zig").BitstreamError;
const endian_mod = @import("endian.zig");
pub const Endian = endian_mod.Endian;

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

inline fn lowMask(n: u7) u64 {
    if (n == 0) return 0;
    if (n >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @as(u6, @intCast(n))) -% 1;
}

inline fn reverseByte(b: u8) u8 {
    var x: u8 = b;
    x = (x & 0xF0) >> 4 | (x & 0x0F) << 4;
    x = (x & 0xCC) >> 2 | (x & 0x33) << 2;
    x = (x & 0xAA) >> 1 | (x & 0x55) << 1;
    return x;
}

pub const BitOrder = enum { MsbFirst, LsbFirst };

// ─────────────────────────────────────────────────────────────────────────────
// BitWriter(T)
// ─────────────────────────────────────────────────────────────────────────────

pub fn BitWriter(comptime T: type) type {
    const is_slice = switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.size == .slice and (ptr.child == u8),
        else => false,
    };

    if (is_slice) {
        return SliceBitWriterImpl;
    } else {
        return GenericBitWriterImpl(T);
    }
}

/// Implementation for writing directly to a byte slice (fastest).
const SliceBitWriterImpl = struct {
    const Self = @This();
    buf: []u8,
    bit_pos: usize = 0,
    byte_endian: Endian,
    bit_order: BitOrder,

    pub fn init(buf: []u8, be: Endian, bo: BitOrder) Self {
        return .{ .buf = buf, .byte_endian = be, .bit_order = bo };
    }

    pub fn reset(self: *Self) void { self.bit_pos = 0; }
    pub fn isAligned(self: *const Self) bool { return (self.bit_pos & 7) == 0; }
    pub fn bitsWritten(self: *const Self) usize { return self.bit_pos; }
    pub fn bytesWritten(self: *const Self) usize { return (self.bit_pos + 7) / 8; }

    pub fn writeSingleBit(self: *Self, bit: u1) void {
        const byte_idx = self.bit_pos / 8;
        const bit_idx: u3 = @intCast(self.bit_pos & 7);
        if (self.bit_order == .MsbFirst) {
            const shift: u3 = 7 - bit_idx;
            if (bit == 1) self.buf[byte_idx] |= (@as(u8, 1) << shift)
            else self.buf[byte_idx] &= ~(@as(u8, 1) << shift);
        } else {
            if (bit == 1) self.buf[byte_idx] |= (@as(u8, 1) << bit_idx)
            else self.buf[byte_idx] &= ~(@as(u8, 1) << bit_idx);
        }
        self.bit_pos += 1;
    }

    pub fn writeBitsRaw(self: *Self, value: u64, n: u7) BitstreamError!void {
        if (n == 0) return;
        if (n > 64) return BitstreamError.InvalidBitCount;
        const masked = value & lowMask(n);

        // General bit-by-bit path for slice write.
        if (self.bit_order == .MsbFirst) {
            var i: i128 = @as(i128, n) - 1;
            while (i >= 0) : (i -= 1) self.writeSingleBit(@intCast((masked >> @as(u6, @intCast(i))) & 1));
        } else {
            var i: u7 = 0;
            while (i < n) : (i += 1) self.writeSingleBit(@intCast((masked >> @as(u6, @intCast(i))) & 1));
        }
    }

    pub fn write(self: *Self, value: anytype) !void {
        return writeAny(Self, self, value);
    }

    pub fn writeBits(self: *Self, comptime Type: type, value: Type, n: u7) !void {
        return self.writeBitsRaw(@intCast(value), n);
    }

    pub fn writeU32(self: *Self, value: u32) !void {
        if (self.byte_endian == .Big) {
            try self.writeBitsRaw(value >> 24, 8);
            try self.writeBitsRaw(value >> 16, 8);
            try self.writeBitsRaw(value >> 8, 8);
            try self.writeBitsRaw(value, 8);
        } else {
            try self.writeBitsRaw(value, 8);
            try self.writeBitsRaw(value >> 8, 8);
            try self.writeBitsRaw(value >> 16, 8);
            try self.writeBitsRaw(value >> 24, 8);
        }
    }

    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        for (bytes) |b| try self.writeBitsRaw(b, 8);
    }

    pub fn flush(self: *Self) !void { _ = self; }
};

/// Implementation for writing to any generic Sink (Reader/File/etc).
fn GenericBitWriterImpl(comptime Sink: type) type {
    return struct {
        const Self = @This();
        inner: Sink,
        bit_buffer: u8 = 0,
        bits_used: u4 = 0,
        total_bits: usize = 0,
        byte_endian: Endian,
        bit_order: BitOrder,

        pub fn init(inner: Sink, be: Endian, bo: BitOrder) Self {
            return .{ .inner = inner, .byte_endian = be, .bit_order = bo };
        }

        pub fn isAligned(self: *const Self) bool { return self.bits_used == 0; }
        pub fn bitsUsed(self: *const Self) u4 { return self.bits_used; }
        pub fn bitsWritten(self: *const Self) usize { return self.total_bits; }

        fn writeToInner(self: *Self, b: u8) !void {
            if (@hasDecl(Sink, "writeByte")) {
                try self.inner.writeByte(b);
            } else {
                // Try treating as a standard Writer interface or something with .writer()
                if (@hasDecl(Sink, "writer")) {
                    try self.inner.writer().writeByte(b);
                } else if (@hasDecl(Sink, "writeAll")) {
                    try self.inner.writeAll(&[_]u8{b});
                } else {
                    // Final fallback: assume Sink IS a Writer interface (has write method)
                    _ = try self.inner.write(&[_]u8{b});
                }
            }
        }

        pub fn writeSingleBit(self: *Self, bit: u1) !void {
            if (self.bit_order == .MsbFirst) {
                const shift: u3 = @intCast(7 - self.bits_used);
                if (bit == 1) self.bit_buffer |= (@as(u8, 1) << shift)
                else self.bit_buffer &= ~(@as(u8, 1) << shift);
            } else {
                if (bit == 1) self.bit_buffer |= (@as(u8, 1) << @intCast(self.bits_used))
                else self.bit_buffer &= ~(@as(u8, 1) << @intCast(self.bits_used));
            }
            self.bits_used += 1;
            if (self.bits_used == 8) {
                try self.writeToInner(self.bit_buffer);
                self.bit_buffer = 0;
                self.bits_used = 0;
            }
            self.total_bits += 1;
        }

        pub fn writeBitsRaw(self: *Self, value: u64, n: u7) !void {
            if (n == 0) return;
            if (n > 64) return BitstreamError.InvalidBitCount;
            const masked = value & lowMask(n);

            if (self.bit_order == .MsbFirst) {
                var i: i128 = @as(i128, n) - 1;
                while (i >= 0) : (i -= 1) try self.writeSingleBit(@intCast((masked >> @as(u6, @intCast(i))) & 1));
            } else {
                var i: u7 = 0;
                while (i < n) : (i += 1) try self.writeSingleBit(@intCast((masked >> @as(u6, @intCast(i))) & 1));
            }
        }

        pub fn write(self: *Self, value: anytype) !void {
            return writeAny(Self, self, value);
        }

        pub fn writeBits(self: *Self, comptime Type: type, value: Type, n: u7) !void {
            return self.writeBitsRaw(@intCast(value), n);
        }

        pub fn writeU32(self: *Self, value: u32) !void {
            if (self.byte_endian == .Big) {
                try self.writeBitsRaw(value >> 24, 8);
                try self.writeBitsRaw(value >> 16, 8);
                try self.writeBitsRaw(value >> 8, 8);
                try self.writeBitsRaw(value, 8);
            } else {
                try self.writeBitsRaw(value, 8);
                try self.writeBitsRaw(value >> 8, 8);
                try self.writeBitsRaw(value >> 16, 8);
                try self.writeBitsRaw(value >> 24, 8);
            }
        }

        pub fn writeBytes(self: *Self, bytes: []const u8) !void {
            for (bytes) |b| try self.writeBitsRaw(b, 8);
        }

        pub fn flush(self: *Self) !void {
            if (self.bits_used != 0) {
                try self.writeToInner(self.bit_buffer);
                self.bit_buffer = 0;
                self.bits_used = 0;
            }
        }
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// BitReader(T)
// ─────────────────────────────────────────────────────────────────────────────

pub fn BitReader(comptime T: type) type {
    const is_slice = switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.size == .slice and (ptr.child == u8),
        else => false,
    };

    if (is_slice) {
        return SliceBitReaderImpl;
    } else {
        return GenericBitReaderImpl(T);
    }
}

const SliceBitReaderImpl = struct {
    const Self = @This();
    buf: []const u8,
    bit_pos: usize = 0,
    byte_endian: Endian,
    bit_order: BitOrder,

    pub fn init(buf: []const u8, be: Endian, bo: BitOrder) Self {
        return .{ .buf = buf, .byte_endian = be, .bit_order = bo };
    }

    pub fn isAligned(self: *const Self) bool { return (self.bit_pos & 7) == 0; }
    pub fn bitsRead(self: *const Self) usize { return self.bit_pos; }

    pub fn readSingleBit(self: *Self) u1 {
        const byte_idx = self.bit_pos / 8;
        const bit_idx: u3 = @intCast(self.bit_pos & 7);
        self.bit_pos += 1;
        if (self.bit_order == .MsbFirst) {
            return @intCast((self.buf[byte_idx] >> (7 - bit_idx)) & 1);
        } else {
            return @intCast((self.buf[byte_idx] >> bit_idx) & 1);
        }
    }

    pub fn readBitsRaw(self: *Self, n: u7) BitstreamError!u64 {
        if (n == 0) return 0;
        if (n > 64) return BitstreamError.InvalidBitCount;
        if (self.bit_pos + n > self.buf.len * 8) return BitstreamError.EndOfStream;
        var res: u64 = 0;
        if (self.bit_order == .MsbFirst) {
            for (0..n) |_| res = (res << 1) | @as(u64, self.readSingleBit());
        } else {
            for (0..n) |i| res |= @as(u64, self.readSingleBit()) << @intCast(i);
        }
        return res;
    }

    pub fn peekBitsRaw(self: *Self, n: u7) BitstreamError!u64 {
        const saved_pos = self.bit_pos;
        defer self.bit_pos = saved_pos;
        return self.readBitsRaw(n);
    }

    pub fn read(self: *Self, comptime Type: type) !Type {
        return @intCast(try self.readBitsRaw(@bitSizeOf(Type)));
    }
};

fn GenericBitReaderImpl(comptime Source: type) type {
    return struct {
        const Self = @This();
        inner: Source,
        bit_buffer: u8 = 0,
        bits_remaining: u4 = 0,
        total_bits: usize = 0,
        byte_endian: Endian,
        bit_order: BitOrder,

        pub fn init(inner: Source, be: Endian, bo: BitOrder) Self {
            return .{ .inner = inner, .byte_endian = be, .bit_order = bo };
        }

        pub fn isAligned(self: *const Self) bool { return self.bits_remaining == 0; }
        pub fn bitsRemaining(self: *const Self) u4 { return self.bits_remaining; }
        pub fn bitsRead(self: *const Self) usize { return self.total_bits; }

        fn readFromInner(self: *Self) !u8 {
            if (@hasDecl(Source, "readByte")) {
                return try self.inner.readByte();
            } else if (@hasDecl(Source, "reader")) {
                return try self.inner.reader().readByte();
            } else {
                var b: [1]u8 = undefined;
                const n = try self.inner.read(&b);
                if (n == 0) return error.EndOfStream;
                return b[0];
            }
        }

        pub fn readSingleBit(self: *Self) !u1 {
            if (self.bits_remaining == 0) {
                self.bit_buffer = try self.readFromInner();
                self.bits_remaining = 8;
            }
            const bit_idx = 8 - self.bits_remaining;
            self.bits_remaining -= 1;
            self.total_bits += 1;
            if (self.bit_order == .MsbFirst) return @intCast((self.bit_buffer >> @intCast(7 - bit_idx)) & 1)
            else return @intCast((self.bit_buffer >> @intCast(bit_idx)) & 1);
        }

        pub fn readBitsRaw(self: *Self, n: u7) !u64 {
            if (n == 0) return 0;
            var res: u64 = 0;
            if (self.bit_order == .MsbFirst) {
                for (0..n) |_| res = (res << 1) | @as(u64, try self.readSingleBit());
            } else {
                for (0..n) |i| res |= @as(u64, try self.readSingleBit()) << @intCast(i);
            }
            return res;
        }

        pub fn read(self: *Self, comptime Type: type) !Type {
            return @intCast(try self.readBitsRaw(@bitSizeOf(Type)));
        }
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Generic Logic
// ─────────────────────────────────────────────────────────────────────────────

fn writeAny(comptime WriterType: type, self: *WriterType, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .int => |info| try self.writeBitsRaw(@intCast(value), info.bits),
        .bool => try self.writeBitsRaw(if (value) 1 else 0, 1),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                for (value) |b| try self.writeBitsRaw(b, 8);
            } else if (ptr.size == .one) {
                try writeAny(WriterType, self, value.*);
            } else {
                @compileError("Unsupported pointer type: " ++ @typeName(T));
            }
        },
        .@"enum" => |info| try self.writeBitsRaw(@intFromEnum(value), @bitSizeOf(info.tag_type)),
        .array => |info| {
            if (info.child == u8) for (value) |b| try self.writeBitsRaw(b, 8)
            else for (value) |item| try writeAny(WriterType, self, item);
        },
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience constructors
// ─────────────────────────────────────────────────────────────────────────────

pub fn bitWriter(inner: anytype, be: Endian, bo: BitOrder) BitWriter(@TypeOf(inner)) {
    return BitWriter(@TypeOf(inner)).init(inner, be, bo);
}

pub fn bitReader(inner: anytype, be: Endian, bo: BitOrder) BitReader(@TypeOf(inner)) {
    return BitReader(@TypeOf(inner)).init(inner, be, bo);
}

pub const SliceBitWriter = BitWriter([]u8);
pub const SliceBitReader = BitReader([]const u8);

pub fn sliceWriter(buf: []u8, be: Endian, bo: BitOrder) SliceBitWriter {
    return SliceBitWriter.init(buf, be, bo);
}

pub fn sliceReader(buf: []const u8, be: Endian, bo: BitOrder) SliceBitReader {
    return SliceBitReader.init(buf, be, bo);
}

pub const BitstreamBuffer = struct {
    data: []u8,
    byte_endian: Endian,
    bit_order: BitOrder,

    pub fn init(data: []u8, be: Endian, bo: BitOrder) BitstreamBuffer {
        return .{ .data = data, .byte_endian = be, .bit_order = bo };
    }

    pub fn writer(self: *BitstreamBuffer) SliceBitWriter {
        return sliceWriter(self.data, self.byte_endian, self.bit_order);
    }

    pub fn reader(self: *const BitstreamBuffer) SliceBitReader {
        return sliceReader(self.data, self.byte_endian, self.bit_order);
    }
};
