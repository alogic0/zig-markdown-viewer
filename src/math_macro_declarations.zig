//! Parses the restricted declaration language used by `math-macros` fences.

const std = @import("std");
const math = @import("math_typesetter");

const Allocator = std.mem.Allocator;

pub const ParseError = Allocator.Error || error{
    InvalidDeclaration,
    TooManyDefinitions,
};

/// Owns one copy of the declaration source. Definition names and replacements
/// borrow from that copy and remain valid until `deinit`.
pub const Parsed = struct {
    allocator: Allocator,
    source: []u8,
    definitions: []math.MacroDefinition,

    pub fn deinit(parsed: *Parsed) void {
        parsed.allocator.free(parsed.definitions);
        parsed.allocator.free(parsed.source);
        parsed.* = undefined;
    }
};

pub fn parseAlloc(
    allocator: Allocator,
    input: []const u8,
    maximum_definitions: usize,
) ParseError!Parsed {
    const source = try allocator.dupe(u8, input);
    errdefer allocator.free(source);

    var definitions: std.ArrayList(math.MacroDefinition) = .empty;
    defer definitions.deinit(allocator);

    var parser: Parser = .{ .source = source };
    parser.skipTrivia();
    while (!parser.atEnd()) {
        try parser.expectControlWord("newcommand");
        parser.skipTrivia();
        const name = try parser.parseName();
        parser.skipTrivia();

        const argument_count = if (parser.peek() == '[')
            try parser.parseArgumentCount()
        else
            0;
        parser.skipTrivia();
        const replacement = try parser.parseReplacement();

        if (definitions.items.len >= maximum_definitions) {
            return error.TooManyDefinitions;
        }
        try definitions.append(allocator, .{
            .name = name,
            .replacement = replacement,
            .argument_count = argument_count,
        });
        parser.skipTrivia();
    }

    return .{
        .allocator = allocator,
        .source = source,
        .definitions = try definitions.toOwnedSlice(allocator),
    };
}

const Parser = struct {
    source: []const u8,
    cursor: usize = 0,

    fn atEnd(parser: Parser) bool {
        return parser.cursor == parser.source.len;
    }

    fn peek(parser: Parser) ?u8 {
        return if (parser.atEnd()) null else parser.source[parser.cursor];
    }

    fn skipTrivia(parser: *Parser) void {
        while (!parser.atEnd()) {
            if (std.ascii.isWhitespace(parser.source[parser.cursor])) {
                parser.cursor += 1;
                continue;
            }
            if (parser.source[parser.cursor] != '%') return;
            while (!parser.atEnd() and parser.source[parser.cursor] != '\n') {
                parser.cursor += 1;
            }
        }
    }

    fn expectControlWord(parser: *Parser, expected: []const u8) error{InvalidDeclaration}!void {
        if (parser.peek() != '\\') return error.InvalidDeclaration;
        parser.cursor += 1;
        const start = parser.cursor;
        while (!parser.atEnd() and std.ascii.isAlphabetic(parser.source[parser.cursor])) {
            parser.cursor += 1;
        }
        if (!std.mem.eql(u8, parser.source[start..parser.cursor], expected)) {
            return error.InvalidDeclaration;
        }
    }

    fn parseName(parser: *Parser) error{InvalidDeclaration}![]const u8 {
        if (parser.peek() != '{') return error.InvalidDeclaration;
        parser.cursor += 1;
        parser.skipTrivia();
        if (parser.peek() != '\\') return error.InvalidDeclaration;
        parser.cursor += 1;
        const start = parser.cursor;
        while (!parser.atEnd() and std.ascii.isAlphabetic(parser.source[parser.cursor])) {
            parser.cursor += 1;
        }
        if (parser.cursor == start) return error.InvalidDeclaration;
        const name = parser.source[start..parser.cursor];
        parser.skipTrivia();
        if (parser.peek() != '}') return error.InvalidDeclaration;
        parser.cursor += 1;
        return name;
    }

    fn parseArgumentCount(parser: *Parser) error{InvalidDeclaration}!u8 {
        parser.cursor += 1;
        if (parser.atEnd() or parser.source[parser.cursor] < '0' or
            parser.source[parser.cursor] > '9')
        {
            return error.InvalidDeclaration;
        }
        const count = parser.source[parser.cursor] - '0';
        parser.cursor += 1;
        if (parser.peek() != ']') return error.InvalidDeclaration;
        parser.cursor += 1;
        return count;
    }

    fn parseReplacement(parser: *Parser) error{InvalidDeclaration}![]const u8 {
        if (parser.peek() != '{') return error.InvalidDeclaration;
        parser.cursor += 1;
        const start = parser.cursor;
        var depth: usize = 1;

        while (!parser.atEnd()) {
            switch (parser.source[parser.cursor]) {
                '\\' => parser.skipControlSequence(),
                '%' => parser.skipComment(),
                '{' => {
                    depth += 1;
                    parser.cursor += 1;
                },
                '}' => {
                    depth -= 1;
                    if (depth == 0) {
                        const replacement = parser.source[start..parser.cursor];
                        parser.cursor += 1;
                        return replacement;
                    }
                    parser.cursor += 1;
                },
                else => parser.cursor += 1,
            }
        }
        return error.InvalidDeclaration;
    }

    fn skipControlSequence(parser: *Parser) void {
        parser.cursor += 1;
        if (parser.atEnd()) return;
        if (!std.ascii.isAlphabetic(parser.source[parser.cursor])) {
            parser.cursor += 1;
            return;
        }
        while (!parser.atEnd() and std.ascii.isAlphabetic(parser.source[parser.cursor])) {
            parser.cursor += 1;
        }
    }

    fn skipComment(parser: *Parser) void {
        while (!parser.atEnd() and parser.source[parser.cursor] != '\n') {
            parser.cursor += 1;
        }
    }
};

test "parses restricted newcommand declarations" {
    var parsed = try parseAlloc(
        std.testing.allocator,
        \\% Shared document macros
        \\\newcommand{\R}{\mathbb{R}}
        \\\newcommand { \f } [2] {#1f({#2})}
    ,
        256,
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.definitions.len);
    try std.testing.expectEqualStrings("R", parsed.definitions[0].name);
    try std.testing.expectEqualStrings("\\mathbb{R}", parsed.definitions[0].replacement);
    try std.testing.expectEqual(@as(u8, 0), parsed.definitions[0].argument_count);
    try std.testing.expectEqualStrings("f", parsed.definitions[1].name);
    try std.testing.expectEqualStrings("#1f({#2})", parsed.definitions[1].replacement);
    try std.testing.expectEqual(@as(u8, 2), parsed.definitions[1].argument_count);
}

test "replacement scanning handles nested groups escaped braces and comments" {
    var parsed = try parseAlloc(
        std.testing.allocator,
        \\\newcommand{\wrapped}[1]{{\{#1\}}% a } in a comment
        \\+x}
    ,
        1,
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.definitions.len);
    try std.testing.expectEqualStrings(
        "{\\{#1\\}}% a } in a comment\n+x",
        parsed.definitions[0].replacement,
    );
}

test "rejects commands and malformed declaration structure" {
    const invalid = [_][]const u8{
        "\\def\\x{x}",
        "\\newcommand{x}{x}",
        "\\newcommand{\\x}[10]{x}",
        "\\newcommand{\\x}[1]{x",
        "\\newcommand{\\x}{x} trailing",
    };
    for (invalid) |source| {
        try std.testing.expectError(
            error.InvalidDeclaration,
            parseAlloc(std.testing.allocator, source, 256),
        );
    }
    try std.testing.expectError(
        error.TooManyDefinitions,
        parseAlloc(std.testing.allocator, "\\newcommand{\\x}{x}", 0),
    );
}

fn exerciseAllocationFailures(allocator: Allocator) !void {
    var parsed = try parseAlloc(
        allocator,
        "\\newcommand{\\f}[2]{#1f(#2)}",
        256,
    );
    defer parsed.deinit();
}

test "declaration parsing cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseAllocationFailures,
        .{},
    );
}
