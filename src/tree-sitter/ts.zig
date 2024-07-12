const std = @import("std");
pub const b = @import("bindings.zig");
const PredicatesFilter = @import("predicates.zig").PredicatesFilter;

const eq = std.testing.expectEqual;
const eqStr = std.testing.expectEqualStrings;

fn getTreeForTesting(source: []const u8, patterns: []const u8) !struct { *b.Tree, *b.Query, *b.Query.Cursor } {
    const ziglang = try b.Language.get("zig");

    var parser = try b.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(ziglang);

    const tree = try parser.parseString(null, source);
    const query = try b.Query.create(ziglang, patterns);
    const cursor = try b.Query.Cursor.create();
    cursor.execute(query, tree.getRootNode());

    return .{ tree, query, cursor };
}

test PredicatesFilter {
    const a = std.testing.allocator;
    const source =
        \\const std = @import("std");
        \\const raylib = @cImport({
        \\    @cInclude("raylib.h");
        \\});
        \\
        \\const StandardAllocator = standard.mem.Allocator;
    ;
    const patterns =
        \\((IDENTIFIER) @std_identifier
        \\  (#eq? @std_identifier "std"))
        \\
        \\((BUILTINIDENTIFIER) @include
        \\  (#any-of? @include "@import" "@cImport"))
        \\
        \\((IDENTIFIER) @contrived-example
        \\  (#eq? @contrived-example "@contrived")
        \\  (#contrived-predicate? @contrived-example "contrived-argument"))
        \\
        \\;; assume TitleCase is a type
        \\(
        \\  [
        \\    variable_type_function: (IDENTIFIER)
        \\    field_access: (IDENTIFIER)
        \\    parameter: (IDENTIFIER)
        \\  ] @type
        \\  (#match? @type "^[A-Z]([a-z]+[A-Za-z0-9]*)*$")
        \\)
    ;

    const tree, const query, const cursor = try getTreeForTesting(source, patterns);
    defer tree.destroy();
    defer query.destroy();
    defer cursor.destroy();

    var filter = try PredicatesFilter.init(a, query);
    defer filter.deinit();

    {
        try eq(4, filter.patterns.len);

        try eq(1, filter.patterns[0].len);
        try eqStr("std_identifier", filter.patterns[0][0].eq.capture);
        try eqStr("std", filter.patterns[0][0].eq.target);

        try eq(1, filter.patterns[1].len);
        try eqStr("include", filter.patterns[1][0].any_of.capture);
        try eq(2, filter.patterns[1][0].any_of.targets.len);
        try eqStr("@import", filter.patterns[1][0].any_of.targets[0]);
        try eqStr("@cImport", filter.patterns[1][0].any_of.targets[1]);

        try eq(2, filter.patterns[2].len);
        try eqStr("contrived-example", filter.patterns[2][0].eq.capture);
        try eqStr("@contrived", filter.patterns[2][0].eq.target);
        try eq(.unsupported, filter.patterns[2][1].unsupported);

        try eq(1, filter.patterns[3].len);
        try eqStr("type", filter.patterns[3][0].match.capture);
        try eqStr("^[A-Z]([a-z]+[A-Za-z0-9]*)*$", filter.patterns[3][0].match.regex_pattern);
    }

    {
        {
            const result = filter.nextMatch(source, cursor);
            const node = result.?.captures()[0].node;
            try eq(1, result.?.captures_len);
            try eqStr("std", source[node.getStartByte()..node.getEndByte()]);
        }

        {
            const result = filter.nextMatch(source, cursor);
            const node = result.?.captures()[0].node;
            try eq(1, result.?.captures_len);
            try eqStr("@import", source[node.getStartByte()..node.getEndByte()]);
        }

        {
            const result = filter.nextMatch(source, cursor);
            const node = result.?.captures()[0].node;
            try eq(1, result.?.captures_len);
            try eqStr("@cImport", source[node.getStartByte()..node.getEndByte()]);
        }

        {
            const result = filter.nextMatch(source, cursor);
            const node = result.?.captures()[0].node;
            try eq(1, result.?.captures_len);
            try eqStr("StandardAllocator", source[node.getStartByte()..node.getEndByte()]);
        }

        {
            const result = filter.nextMatch(source, cursor);
            const node = result.?.captures()[0].node;
            try eq(1, result.?.captures_len);
            try eqStr("Allocator", source[node.getStartByte()..node.getEndByte()]);
        }

        {
            try eq(null, filter.nextMatch(source, cursor));
        }
    }
}

test "InputEdit" {
    const a = std.testing.allocator;
    const source =
        \\const std = @import("std");
    ;
    const patterns =
        \\((IDENTIFIER) @identifier
        \\  (#any-of? @identifier "std" "hello"))
    ;

    const tree, const query, const cursor = try getTreeForTesting(source, patterns);
    defer tree.destroy();
    defer query.destroy();
    defer cursor.destroy();

    var filter = try PredicatesFilter.init(a, query);
    defer filter.deinit();

    {
        const result = filter.nextMatch(source, cursor);
        const node = result.?.captures()[0].node;
        try eqStr("std", source[node.getStartByte()..node.getEndByte()]);
    }

    const edit = b.InputEdit{
        .start_byte = 7,
        .old_end_byte = 9,
        .new_end_byte = 11,
        .start_point = b.Point{ .row = 0, .column = 7 },
        .old_end_point = b.Point{ .row = 0, .column = 9 },
        .new_end_point = b.Point{ .row = 0, .column = 11 },
    };
    tree.edit(&edit);
    try eq(true, tree.getRootNode().hasChanges());

    const new_cursor = try b.Query.Cursor.create();
    new_cursor.execute(query, tree.getRootNode());

    const new_source =
        \\const hello = @import("std");
    ;

    {
        const result = filter.nextMatch(new_source, new_cursor);
        const node = result.?.captures()[0].node;
        try eqStr("hello", new_source[node.getStartByte()..node.getEndByte()]);
    }
}
