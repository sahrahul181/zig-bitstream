# zig-bitstream

A high-performance, and fully generic bit-level I/O library for Zig 0.15.2+.

## Features

- **🚀 Performance**: Ultra-fast, zero-allocation implementation for byte slices (`[]u8`) using compile-time dispatch.
- **🛠 Generic**: Works with any `std.io.Writer`, `std.io.Reader`, or custom stream-like objects.
- **✨ Reflection-Powered**: A unified `write(anytype)` method that automatically packs integers, booleans, strings, and enums as bits.
- **📐 Flexible Ordering**: Supports both **MsbFirst** and **LsbFirst** bit orders.
- **🌍 Endian Aware**: Full support for Big and Little endian byte-level serialization.
- **🔍 Lookahead**: Built-in support for `peekBitsRaw` and alignment checks.

---

## Installation

Add `zig-bitstream` to your `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .zig_bitstream = .{
            .url = "https://github.com/youruser/zig-bitstream/archive/main.tar.gz",
            .hash = "...", // Replace with actual hash
        },
    },
}
```

In your `build.zig`:

```zig
const bitstream_dep = b.dependency("zig_bitstream", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zig_bitstream", bitstream_dep.module("zig_bitstream"));
```

---

## 📖 API Documentation & Examples

### 1. Initialization (Writers & Readers)

The library provides multiple ways to initialize bitstreams depending on your data source.

#### Slice-Based (High Performance)
Use these when you have a pre-allocated byte buffer. They are zero-allocation and extremely fast.

```zig
const bs = @import("zig_bitstream");

var buf: [1024]u8 = undefined;

// Shorthand: Big Endian, MsbFirst
var w = bs.writer(&buf); 
var r = bs.reader(&buf);

// Explicit ordering and endianness
var w_ex = bs.writerEx(&buf, .Little, .LsbFirst);
var r_ex = bs.readerEx(&buf, .Little, .LsbFirst);

// Low-level slice constructor
var w_slice = bs.sliceWriter(&buf, .Big, .MsbFirst);
```

#### Generic Stream-Based
Use these when you want to write to/read from dynamic sources like network sockets, files, or `ArrayList`s.

```zig
// Writing to an ArrayList
var list = std.ArrayList(u8).empty;
var w = bs.fromWriter(list.writer(allocator), .Big, .MsbFirst);

// Reading from a file
var file = try std.fs.cwd().openFile("data.bin", .{});
var r = bs.fromReader(file.reader(), .Big, .MsbFirst);
```

### 2. The `write(anytype)` API (Reflection)

The `write` method uses compile-time reflection to automatically handle various types.

```zig
var w = bs.writer(&buf);

// Booleans: Written as 1 bit (true: 1, false: 0)
try w.write(true); 

// Integers: Written using their EXACT bit-width
try w.write(@as(u3, 5));     // 3 bits
try w.write(@as(i128, -1));  // 128 bits

// Enums: Written using the bit-width of their backing integer tag
const Status = enum(u2) { OK = 0, ERR = 1, PENDING = 2 };
try w.write(Status.PENDING); // 2 bits

// Strings: Written as raw byte clusters (8 bits per char)
try w.write("ZIG");          // 24 bits

// Arrays: Written element-by-element
try w.write([_]u4{1, 2, 3}); // 12 bits total

// Pointers: Automatically dereferenced and written as the child value
var x: u8 = 42;
try w.write(&x);             // 8 bits
```

### 3. Bit-Level Control

When you need manual control over how many bits to read or write.

```zig
// Raw bit writing (supports 0 to 64 bits)
try w.writeBitsRaw(0xDEADBEEF, 32);

// Raw bit reading
const val = try r.readBitsRaw(12);

// Peek (Lookahead): Read bits WITHOUT advancing the stream position
// (Note: Currently optimized for SliceBitReader)
const next_bits = try r.peekBitsRaw(8);
```

### 4. Byte Alignment & Flushing

Bitstreams buffer bits. To ensure they are physically written to the underlying storage/slice, you must align or flush.

```zig
// Check if we are at a byte boundary
if (!w.isAligned()) {
    // Force write the current partial byte (padding with zeros or whatever was there)
    try w.flush(); 
}

// bytesWritten / bitsWritten
const current_pos = w.bitsWritten();
```

### 5. BitstreamBuffer

A convenient wrapper for shared read/write access to the same buffer.

```zig
var raw = [_]u8{0} ** 64;
var bb = bs.BitstreamBuffer.init(&raw, .Big, .MsbFirst);

// Get a writer
var w = bb.writer();
try w.write(@as(u4, 0xF));

// Get a reader for the same buffer
var r = bb.reader();
const val = try r.read(u4); // Returns 0xF
```

### 6. Endianness Helpers (`bs.endian`)

Low-level utilities for manual byte-level manipulations.

```zig
const endian = bs.endian;

// Native swap
const swapped = endian.swap(@as(u32, 0x11223344)); // 0x44332211

// Byte-swap aware slice access
var bytes: [4]u8 = undefined;
endian.writeInt(u32, &bytes, 0x12345678, .Big);
const val = endian.readInt(u32, &bytes, .Big);
```

---

## Design Choices

### Compile-Time Dispatch
The library uses Zig's `comptime` features to detect the type of the source/sink at compile time. If you provide a slice, it generates code that uses direct pointer access. If you provide a stream, it generates code that handles buffering and calls `writeByte`/`readByte`. This ensures you never pay for generic abstractions when you don't need them.

### Bit Ordering
- **MsbFirst**: The first bit written is the most significant bit of the byte (Standard for networking, e.g., RTP, TCP).
- **LsbFirst**: The first bit written is the least significant bit of the byte (Common in some formats like Gzip/DEFLATE).

## License
MIT
