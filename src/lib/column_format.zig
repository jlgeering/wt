const std = @import("std");

const ansi_escape: u8 = 0x1b;
const ansi_csi_start: u8 = '[';
const tab_width: usize = 4;

pub fn visibleWidth(text: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        if (text[i] == ansi_escape and i + 1 < text.len and text[i + 1] == ansi_csi_start) {
            i += 2;
            while (i < text.len and !isAnsiTerminator(text[i])) : (i += 1) {}
            if (i < text.len) i += 1;
            continue;
        }

        const char_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            width += 1;
            i += 1;
            continue;
        };

        if (i + char_len > text.len) {
            width += 1;
            break;
        }

        const cp = std.unicode.utf8Decode(text[i .. i + char_len]) catch {
            width += 1;
            i += 1;
            continue;
        };

        width += if (cp == '\t') tab_width else 1;
        i += char_len;
    }

    return width;
}

fn isAnsiTerminator(byte: u8) bool {
    return byte >= 0x40 and byte <= 0x7e;
}

pub fn writePadded(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    const actual = visibleWidth(text);
    if (actual >= width) return;
    try writer.writeByteNTimes(' ', width - actual);
}

test "visibleWidth counts UTF-8 arrows by display cell" {
    try std.testing.expectEqual(@as(usize, 2), visibleWidth("↑2"));
    try std.testing.expectEqual(@as(usize, 5), visibleWidth("↑1 ↓8"));
}

test "visibleWidth ignores ANSI escape sequences" {
    const colored = "\x1b[33mM:1 U:2, ↑3\x1b[0m";
    try std.testing.expectEqual(@as(usize, 11), visibleWidth(colored));
}
