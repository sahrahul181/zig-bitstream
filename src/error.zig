/// Unified error set for the bitstream library.
pub const BitstreamError = error{
    /// Writer has no more space in the underlying buffer.
    BufferFull,
    /// Reader has no more bits to consume.
    EndOfStream,
    /// A bit-count argument was out of the legal range (0–64).
    InvalidBitCount,
    /// The requested operation would overflow an integer type.
    Overflow,
    /// Underlying I/O failure.
    IoError,
};
