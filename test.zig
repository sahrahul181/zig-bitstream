/// test.zig — Comprehensive test suite for 100% coverage
const std = @import("std");
const bs = @import("zig_bitstream");
const BitOrder = bs.BitOrder;
const Endian = bs.Endian;

// ─────────────────────────────────────────────────────────────────────────────
// Basic Slice Reader/Writer (Fast Path)
// ─────────────────────────────────────────────────────────────────────────────

test "Slice BitWriter: MsbFirst" {
    var buf = [_]u8{0} ** 4;
    var w = bs.sliceWriter(&buf, .Big, .MsbFirst);
    
    try w.writeBitsRaw(0b101, 3);
    try w.writeBitsRaw(0b11, 2);
    try w.writeBitsRaw(0b001, 3); // 101 11 001 = 0xB9
    
    try std.testing.expectEqual(@as(u8, 0xB9), buf[0]);
    try std.testing.expectEqual(@as(usize, 8), w.bitsWritten());
    try std.testing.expect(w.isAligned());
}

test "Slice BitWriter: LsbFirst" {
    var buf = [_]u8{0} ** 4;
    var w = bs.sliceWriter(&buf, .Big, .LsbFirst);
    
    try w.writeBitsRaw(0b101, 3);
    try w.writeBitsRaw(0b11, 2);
    try w.writeBitsRaw(0b001, 3); // 001 11 101 = 0x3D
    
    try std.testing.expectEqual(@as(u8, 0x3D), buf[0]);
    try std.testing.expect(w.isAligned());
}

test "Slice BitReader: Roundtrip" {
    var buf = [_]u8{0xB9, 0x3D};
    var r = bs.sliceReader(&buf, .Big, .MsbFirst);
    
    try std.testing.expectEqual(@as(u64, 0b101), try r.readBitsRaw(3));
    try std.testing.expectEqual(@as(u64, 0b11), try r.readBitsRaw(2));
    try std.testing.expectEqual(@as(u64, 0b001), try r.readBitsRaw(3));
    try std.testing.expect(r.isAligned());
    
    // Peek check
    const pos = r.bitsRead();
    try std.testing.expectEqual(@as(u64, 0b0011), try r.peekBitsRaw(4));
    try std.testing.expectEqual(pos, r.bitsRead());
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic Stream Reader/Writer
// ─────────────────────────────────────────────────────────────────────────────

test "Generic BitWriter with ArrayList" {
    var list = std.ArrayList(u8).empty;
    defer list.deinit(std.testing.allocator);
    
    var w = bs.fromWriter(list.writer(std.testing.allocator), .Big, .MsbFirst);
    try w.writeBitsRaw(0xAA, 8);
    try w.writeBitsRaw(0x5, 4);
    try w.flush();
    
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(@as(u8, 0xAA), list.items[0]);
    try std.testing.expectEqual(@as(u8, 0x50), list.items[1]); // 0101 0000
}

test "Generic BitReader with FixedBufferStream" {
    const data = [_]u8{0xAA, 0x55};
    var fbs = std.io.fixedBufferStream(&data);
    var r = bs.fromReader(fbs.reader(), .Big, .MsbFirst);
    
    try std.testing.expectEqual(@as(u64, 0xAA), try r.readBitsRaw(8));
    try std.testing.expectEqual(@as(u64, 0x5), try r.readBitsRaw(4));
    try std.testing.expectEqual(@as(u64, 0x5), try r.readBitsRaw(4));
    
    try std.testing.expectError(error.EndOfStream, r.readBitsRaw(1));
}

// ─────────────────────────────────────────────────────────────────────────────
// Typed writes (Reflection)
// ─────────────────────────────────────────────────────────────────────────────

test "Typed writes: ints, bools, strings, enums" {
    var buf = [_]u8{0} ** 32;
    var w = bs.sliceWriter(&buf, .Big, .MsbFirst);
    
    try w.write(true);                  // 1 bit: 0b1
    try w.write(@as(u3, 0b010));        // 3 bits: 0b010 -> 0b1010
    try w.write(@as(u4, 0b1111));       // 4 bits: 0b1111 -> 0b10101111 (0xAF)
    
    const TestEnum = enum(u4) { A = 0, B = 0xF };
    try w.write(TestEnum.B);            // 4 bits: 0b1111
    
    try w.write("HI");                  // 16 bits: 'H' (0x48), 'I' (0x49)
    
    var val: u8 = 0xEE;
    try w.write(&val);                   // Pointer deref: 0xEE
    
    try w.flush();
    
    try std.testing.expectEqual(@as(u8, 0xAF), buf[0]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Endianness (Byte-level)
// ─────────────────────────────────────────────────────────────────────────────

test "Endianness: writeU32" {
    var buf = [_]u8{0} ** 8;
    
    // Big Endian
    {
        var w = bs.sliceWriter(&buf, .Big, .MsbFirst);
        try w.writeU32(0x12345678);
        try std.testing.expectEqualSlices(u8, &[_]u8{0x12, 0x34, 0x56, 0x78}, buf[0..4]);
    }
    
    // Little Endian
    {
        @memset(&buf, 0);
        var w = bs.sliceWriter(&buf, .Little, .MsbFirst);
        try w.writeU32(0x12345678);
        try std.testing.expectEqualSlices(u8, &[_]u8{0x78, 0x56, 0x34, 0x12}, buf[0..4]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error cases
// ─────────────────────────────────────────────────────────────────────────────

test "Error: InvalidBitCount" {
    var buf = [_]u8{0} ** 8;
    var w = bs.sliceWriter(&buf, .Big, .MsbFirst);
    try std.testing.expectError(error.InvalidBitCount, w.writeBitsRaw(0, 65));
    
    var r = bs.sliceReader(&buf, .Big, .MsbFirst);
    try std.testing.expectError(error.InvalidBitCount, r.readBitsRaw(65));
}

test "Error: EndOfStream (Slice)" {
    var buf = [_]u8{0} ** 1;
    var r = bs.sliceReader(&buf, .Big, .MsbFirst);
    _ = try r.readBitsRaw(4);
    _ = try r.readBitsRaw(4);
    try std.testing.expectError(error.EndOfStream, r.readBitsRaw(1));
}

// ─────────────────────────────────────────────────────────────────────────────
// BitstreamBuffer
// ─────────────────────────────────────────────────────────────────────────────

test "BitstreamBuffer integration" {
    var raw = [_]u8{0} ** 16;
    var bb = bs.BitstreamBuffer.init(&raw, .Big, .MsbFirst);
    
    var w = bb.writer();
    try w.write(@as(u16, 0xABCD));
    
    var r = bb.reader();
    try std.testing.expectEqual(@as(u16, 0xABCD), try r.read(u16));
}
