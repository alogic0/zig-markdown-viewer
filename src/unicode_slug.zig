const data = @import("unicode_slug_data.zig");

pub fn isLetter(codepoint: u21) bool {
    return inRanges(codepoint, &data.letter_ranges);
}

pub fn isNumber(codepoint: u21) bool {
    return inRanges(codepoint, &data.number_ranges);
}

pub fn isWhitespace(codepoint: u21) bool {
    // ECMAScript includes the byte-order mark in `\s` in addition to the
    // Unicode White_Space property used by the generated table.
    return codepoint == 0xFEFF or inRanges(codepoint, &data.whitespace_ranges);
}

pub fn fold(codepoint: u21) u21 {
    if (commonCompatibilityFold(codepoint)) |folded| return folded;

    var low: usize = 0;
    var high: usize = data.simple_case_fold_mappings.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const mapping = data.simple_case_fold_mappings[middle];
        if (codepoint < mapping.from) {
            high = middle;
        } else if (codepoint > mapping.from) {
            low = middle + 1;
        } else {
            return @intCast(mapping.to);
        }
    }
    return codepoint;
}

fn inRanges(codepoint: u21, ranges: []const data.Range) bool {
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const range = ranges[middle];
        if (codepoint < range.start) {
            high = middle;
        } else if (codepoint > range.end) {
            low = middle + 1;
        } else {
            return true;
        }
    }
    return false;
}

// These common compatibility/decomposition folds preserve the previous
// JavaScript NFKD behavior for Latin document titles without shipping a full
// normalization database in the viewer.
fn commonCompatibilityFold(codepoint: u21) ?u21 {
    return switch (codepoint) {
        0x00AA => 'a',
        0x00B2 => '2',
        0x00B3 => '3',
        0x00B5 => 0x03BC,
        0x00B9 => '1',
        0x00BA => 'o',
        'À', 'Á', 'Â', 'Ã', 'Ä', 'Å', 'à', 'á', 'â', 'ã', 'ä', 'å' => 'a',
        'Ç', 'ç' => 'c',
        'È', 'É', 'Ê', 'Ë', 'è', 'é', 'ê', 'ë' => 'e',
        'Ì', 'Í', 'Î', 'Ï', 'ì', 'í', 'î', 'ï' => 'i',
        'Ñ', 'ñ' => 'n',
        'Ò', 'Ó', 'Ô', 'Õ', 'Ö', 'ò', 'ó', 'ô', 'õ', 'ö' => 'o',
        'Ù', 'Ú', 'Û', 'Ü', 'ù', 'ú', 'û', 'ü' => 'u',
        'Ý', 'Ÿ', 'ý', 'ÿ' => 'y',
        'Ā', 'Ă', 'Ą', 'ā', 'ă', 'ą' => 'a',
        'Ć', 'Ĉ', 'Ċ', 'Č', 'ć', 'ĉ', 'ċ', 'č' => 'c',
        'Ď', 'ď' => 'd',
        'Ē', 'Ĕ', 'Ė', 'Ę', 'Ě', 'ē', 'ĕ', 'ė', 'ę', 'ě' => 'e',
        'Ĝ', 'Ğ', 'Ġ', 'Ģ', 'ĝ', 'ğ', 'ġ', 'ģ' => 'g',
        'Ĥ', 'ĥ' => 'h',
        'Ĩ', 'Ī', 'Ĭ', 'Į', 'İ', 'ĩ', 'ī', 'ĭ', 'į', 'ı' => 'i',
        'Ĵ', 'ĵ' => 'j',
        'Ķ', 'ķ' => 'k',
        'Ĺ', 'Ļ', 'Ľ', 'ĺ', 'ļ', 'ľ' => 'l',
        'Ń', 'Ņ', 'Ň', 'ń', 'ņ', 'ň' => 'n',
        'Ō', 'Ŏ', 'Ő', 'ō', 'ŏ', 'ő' => 'o',
        'Ŕ', 'Ŗ', 'Ř', 'ŕ', 'ŗ', 'ř' => 'r',
        'Ś', 'Ŝ', 'Ş', 'Š', 'ś', 'ŝ', 'ş', 'š' => 's',
        'Ţ', 'Ť', 'ţ', 'ť' => 't',
        'Ũ', 'Ū', 'Ŭ', 'Ů', 'Ű', 'Ų', 'ũ', 'ū', 'ŭ', 'ů', 'ű', 'ų' => 'u',
        'Ŵ', 'ŵ' => 'w',
        'Ŷ', 'ŷ' => 'y',
        'Ź', 'Ż', 'Ž', 'ź', 'ż', 'ž' => 'z',
        else => null,
    };
}

test "classifies and folds Unicode slug characters" {
    const std = @import("std");

    try std.testing.expect(isLetter('東'));
    try std.testing.expect(isLetter('Я'));
    try std.testing.expect(isNumber('٣'));
    try std.testing.expect(isWhitespace(0x2003));
    try std.testing.expect(isWhitespace(0xFEFF));
    try std.testing.expect(!isLetter('😀'));
    try std.testing.expectEqual(@as(u21, 'я'), fold('Я'));
    try std.testing.expectEqual(@as(u21, 'e'), fold('É'));
}
