/// zig-bitstream — public API surface
///
/// Import this module in your code as:
///
///   const bs = @import("zig_bitstream");
///
/// Then use:
///   bs.BitReader, bs.BitWriter, bs.BitstreamBuffer, bs.Endian, bs.BitOrder …

const bitstream = @import("bitstream.zig");
const endian_mod = @import("endian.zig");
const error_mod = @import("error.zig");

// ── Re-exports ────────────────────────────────────────────────────────────────

/// Bit-level buffered reader type constructor. Use as `BitReader(T)`.
pub const BitReader = bitstream.BitReader;

/// Bit-level buffered writer type constructor. Use as `BitWriter(T)`.
pub const BitWriter = bitstream.BitWriter;

/// Convenience specialization for writing directly to a slice.
pub const SliceBitWriter = bitstream.SliceBitWriter;

/// Convenience specialization for reading directly from a slice.
pub const SliceBitReader = bitstream.SliceBitReader;

pub const sliceWriter = bitstream.sliceWriter;
pub const sliceReader = bitstream.sliceReader;

/// Combined writer and reader over a fixed buffer.
pub const BitstreamBuffer = bitstream.BitstreamBuffer;

/// Byte-level endianness.
pub const Endian = bitstream.Endian;

/// Bit order within each byte (MSB-first or LSB-first).
pub const BitOrder = bitstream.BitOrder;

/// Unified error set.
pub const BitstreamError = error_mod.BitstreamError;

/// Endianness helpers (byte-swap, conversion, slice read/write).
pub const endian = endian_mod;

// ── Inline convenience constructors ──────────────────────────────────────────

/// Create a bitwriter from any `std.io.Writer`.
pub fn fromWriter(inner: anytype, be: Endian, bo: BitOrder) BitWriter(@TypeOf(inner)) {
    return bitstream.bitWriter(inner, be, bo);
}

/// Create a bitreader from any `std.io.Reader`.
pub fn fromReader(inner: anytype, be: Endian, bo: BitOrder) BitReader(@TypeOf(inner)) {
    return bitstream.bitReader(inner, be, bo);
}

/// Create a bit-writer for a byte slice (uses FixedBufferStream internally).
pub fn writer(buf: []u8) SliceBitWriter {
    return bitstream.sliceWriter(buf, .Big, .MsbFirst);
}

/// Specialization with explicit configs.
pub fn writerEx(buf: []u8, be: Endian, bo: BitOrder) SliceBitWriter {
    return bitstream.sliceWriter(buf, be, bo);
}

/// Create a bit-reader for a byte slice (uses FixedBufferStream internally).
pub fn reader(buf: []const u8) SliceBitReader {
    return bitstream.sliceReader(buf, .Big, .MsbFirst);
}

/// Specialization with explicit configs.
pub fn readerEx(buf: []const u8, be: Endian, bo: BitOrder) SliceBitReader {
    return bitstream.sliceReader(buf, be, bo);
}

// ── Comptime tests to verify all sub-modules compile ─────────────────────────

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
    _ = @import("bitstream.zig");
    _ = @import("endian.zig");
}
