//! examples.zig — Practical demonstration of all bitstream variants
const std = @import("std");
const bs = @import("zig_bitstream");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    try stdout.writeAll("Zig Bitstream Comprehensive Examples\n");
    try stdout.writeAll("====================================\n\n");

    // ─────────────────────────────────────────────────────────────────────────
    // 1. SliceBitWriter (The High-Performance Choice)
    // ─────────────────────────────────────────────────────────────────────────
    {
        try stdout.writeAll("[1] SliceBitWriter (BigEndian / MsbFirst)\n");
        var buf: [8]u8 = [_]u8{0} ** 8;
        var w = bs.writer(&buf);
        
        try w.write(@as(u3, 0b101));       // 3 bits
        try w.write(true);                  // 1 bit
        try w.write(@as(u4, 0b1111));       // 4 bits -> 1011 1111 (0xBF)
        try w.write(@as(u8, 0xEE));         // 8 bits
        try w.flush();
        
        try stdout.print("   Result: {X:0>2} {X:0>2} (Position: {d} bits)\n\n", .{ buf[0], buf[1], w.bitsWritten() });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. SliceBitWriterEx (Custom Variations)
    // ─────────────────────────────────────────────────────────────────────────
    {
        try stdout.writeAll("[2] SliceBitWriterEx (LittleEndian / LsbFirst)\n");
        var buf: [8]u8 = [_]u8{0} ** 8;
        var w = bs.writerEx(&buf, .Little, .LsbFirst);
        
        try w.write(@as(u3, 0b101));       // 3 bits (at LSB: xxxxxx101)
        try w.write(@as(u5, 0b11111));     // 5 bits (at MSB: 11111xxx) -> 1111 1101 (0xFD)
        try w.flush();
        
        try stdout.print("   Result: {X:0>2} (Bit order: LSB is first-written)\n\n", .{buf[0]});
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. GenericBitWriter (Streaming to an ArrayList)
    // ─────────────────────────────────────────────────────────────────────────
    {
        try stdout.writeAll("[3] GenericBitWriter (Streaming to ArrayList)\n");
        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        
        var w = bs.fromWriter(list.writer(allocator), .Big, .MsbFirst);
        try w.write("ZIG");                // 24 bits
        try w.write(@as(u4, 0xA));          // 4 bits
        try w.write(@as(u4, 0xB));          // 4 bits -> completes 4th byte: 0xAB
        try w.flush();
        
        try stdout.print("   ArrayList content: {s} {X:0>2}\n\n", .{ list.items[0..3], list.items[3] });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. BitstreamBuffer (Combined Searchable Access)
    // ─────────────────────────────────────────────────────────────────────────
    {
        try stdout.writeAll("[4] BitstreamBuffer (Read + Write on same memory)\n");
        var raw: [16]u8 = [_]u8{0} ** 16;
        var bb = bs.BitstreamBuffer.init(&raw, .Big, .MsbFirst);
        
        var w = bb.writer();
        try w.write(@as(u12, 0xFFF));
        
        var r = bb.reader();
        const val = try r.read(u12);
        try stdout.print("   Roundtrip value: 0x{X} (isAligned: {})\n\n", .{ val, r.isAligned() });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Advanced write(anytype) Showcase
    // ─────────────────────────────────────────────────────────────────────────
    {
        try stdout.writeAll("[5] Advanced Reflection-Based Writing\n");
        var buf: [32]u8 = [_]u8{0} ** 32;
        var w = bs.writer(&buf);
        
        const Quality = enum(u3) { Low = 1, Med = 2, High = 4 };
        const metadata = .{
            .flag = true,
            .version = @as(u7, 127),
            .q = Quality.High,
        };

        try w.write(metadata.flag);
        try w.write(metadata.version);
        try w.write(metadata.q);   // Enums written according to their tag bit-width (3 bits)
        try w.flush();
        
        try stdout.print("   Packed bits written: {d} bits\n", .{w.bitsWritten()});
    }
}
