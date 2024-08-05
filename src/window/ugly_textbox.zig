const std = @import("std");
const rope = @import("rope");

const _cell = @import("cell.zig");
const Cell = _cell.Cell;
const Line = _cell.Line;
const WordBoundaryType = _cell.WordBoundaryType;
const Cursor = @import("cursor.zig").Cursor;

const Allocator = std.mem.Allocator;
const List = std.ArrayList;
const eql = std.mem.eql;
const eq = std.testing.expectEqual;
const eqStr = std.testing.expectEqualStrings;

//////////////////////////////////////////////////////////////////////////////////////////////

pub const UglyTextBox = struct {
    external_allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    a: Allocator,

    root: *const rope.Node,
    document: List(u8),
    cells: List(Cell),
    lines: List(Line),

    cursor: Cursor,

    x: i32,
    y: i32,

    pub fn fromFile(external_allocator: Allocator, path: []const u8, x: i32, y: i32) !*@This() {
        var self = try external_allocator.create(@This());
        self.external_allocator = external_allocator;
        self.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        self.a = self.arena.allocator();

        self.root = try rope.Node.fromFile(self.a, path);
        self.document = try self.root.getContent(self.a);
        self.cells, self.lines = try _cell.createCellListAndLineList(self.a, self.document.items);

        self.cursor = Cursor{};

        self.x = x;
        self.y = y;

        return self;
    }

    pub fn fromString(external_allocator: Allocator, content: []const u8, x: i32, y: i32) !*@This() {
        var self = try external_allocator.create(@This());
        self.external_allocator = external_allocator;
        self.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        self.a = self.arena.allocator();

        self.root = try rope.Node.fromString(self.a, content, true);
        self.document = try self.root.getContent(self.a);
        self.cells, self.lines = try _cell.createCellListAndLineList(self.a, self.document.items);

        self.cursor = Cursor{};

        self.x = x;
        self.y = y;

        return self;
    }
    pub fn destroy(self: *UglyTextBox) void {
        self.arena.deinit();
        self.external_allocator.destroy(self);
    }

    ///////////////////////////// Basic Cursor Movement

    pub fn moveCursorLeft(self: *UglyTextBox, count: usize) void {
        self.cursor.left(count);
    }
    pub fn moveCursorRight(self: *UglyTextBox, count: usize) void {
        const current_line = self.lines.items[self.cursor.line];
        self.cursor.right(count, current_line.numOfCells());
    }
    pub fn moveCursorUp(self: *UglyTextBox, count: usize) void {
        self.cursor.up(count);
    }
    pub fn moveCursorDown(self: *UglyTextBox, count: usize) void {
        self.cursor.down(count, self.lines.items.len);
    }

    ///////////////////////////// Move by word

    pub fn moveCursorBackwardsByWord(self: *UglyTextBox, destination: WordBoundaryType) void {
        const new_line, const new_col = _cell.backwardsByWord(destination, self.document.items, self.cells.items, self.lines.items, self.cursor.line, self.cursor.col);
        self.cursor.set(new_line, new_col);
    }
    pub fn moveCursorForwardByWord(self: *UglyTextBox, destination: WordBoundaryType) void {
        const new_line, const new_col = _cell.forwardByWord(destination, self.document.items, self.cells.items, self.lines.items, self.cursor.line, self.cursor.col);
        self.cursor.set(new_line, new_col);
    }
    test "move cursor forward / backward by word" {
        const a = std.testing.allocator;
        {
            var box = try UglyTextBox.fromString(a, "Hello World!", 0, 0);
            defer box.destroy();

            box.moveCursorForwardByWord(.start);
            _, _ = try box.insertChars("my ");
            try eqStr("Hello my World!", box.lines.items[0].getText(box.cells.items, box.document.items));

            box.moveCursorForwardByWord(.end);
            box.moveCursorRight(1);
            _, _ = try box.insertChars("ne");
            try eqStr("Hello myne World!", box.lines.items[0].getText(box.cells.items, box.document.items));

            box.moveCursorBackwardsByWord(.start);
            _, _ = try box.insertChars("_");
            try eqStr("Hello _myne World!", box.lines.items[0].getText(box.cells.items, box.document.items));

            box.moveCursorBackwardsByWord(.end);
            box.moveCursorRight(1);
            _, _ = try box.insertChars("!");
            try eqStr("Hello! _myne World!", box.lines.items[0].getText(box.cells.items, box.document.items));

            box.moveCursorBackwardsByWord(.start);
            _, _ = try box.insertChars("~");
            try eqStr("~Hello! _myne World!", box.lines.items[0].getText(box.cells.items, box.document.items));
        }
    }

    ///////////////////////////// Insert

    pub fn insertChars(self: *UglyTextBox, chars: []const u8) !struct { usize, usize } {
        const current_line = self.lines.items[self.cursor.line];
        const cell_at_cursor = current_line.cell(self.cells.items, self.cursor.col);
        const insert_index = if (cell_at_cursor) |cell| cell.start_byte else self.document.items.len;

        const new_root, const num_new_lines, const new_col = try self.root.insertChars(self.a, insert_index, chars);
        self.root = new_root;

        self.document.deinit();
        self.document = try self.root.getContent(self.a);

        self.cells.deinit();
        self.lines.deinit();
        self.cells, self.lines = try _cell.createCellListAndLineList(self.a, self.document.items);

        return .{ num_new_lines, new_col };
    }
    test insertChars {
        const a = std.testing.allocator;
        {
            var box = try UglyTextBox.fromString(a, "Hello World!", 0, 0);
            defer box.destroy();
            _, _ = try box.insertChars("OK! ");
            try eqStr("OK! Hello World!", box.lines.items[0].getText(box.cells.items, box.document.items));

            box.moveCursorRight(100);
            _, _ = try box.insertChars(" Here I go!");
            try eqStr("OK! Hello World! Here I go!", box.lines.items[0].getText(box.cells.items, box.document.items));

            box.moveCursorRight(100);
            _, _ = try box.insertChars("\n");
            try eqStr("", box.lines.items[1].getText(box.cells.items, box.document.items));

            box.cursor.set(1, 0);
            _, _ = try box.insertChars("...");
            try eqStr("OK! Hello World! Here I go!", box.lines.items[0].getText(box.cells.items, box.document.items));
            try eqStr("...", box.lines.items[1].getText(box.cells.items, box.document.items));
        }
        { // insertChars and move cursor
            var box = try UglyTextBox.fromString(a, "", 0, 0);
            defer box.destroy();
            {
                const num_new_lines, const new_col = try box.insertChars("H");
                try eqStr("H", box.lines.items[0].getText(box.cells.items, box.document.items));
                box.cursor.set(box.cursor.line + num_new_lines, new_col);
            }
            {
                const num_new_lines, const new_col = try box.insertChars("e");
                try eqStr("He", box.lines.items[0].getText(box.cells.items, box.document.items));
                box.cursor.set(box.cursor.line + num_new_lines, new_col);
            }
        }
    }

    pub fn insertCharsAndMoveCursor(self: *UglyTextBox, chars: []const u8) !void {
        const num_new_lines, const col_offset = try self.insertChars(chars);
        self.cursor.set(self.cursor.line + num_new_lines, self.cursor.col + col_offset);
    }
    test insertCharsAndMoveCursor {
        const a = std.testing.allocator;
        {
            var box = try UglyTextBox.fromString(a, "", 0, 0);
            defer box.destroy();
            try box.insertCharsAndMoveCursor("H");
            try eqStr("H", box.lines.items[0].getText(box.cells.items, box.document.items));
            try box.insertCharsAndMoveCursor("e");
            try eqStr("He", box.lines.items[0].getText(box.cells.items, box.document.items));
            try box.insertCharsAndMoveCursor("l");
            try eqStr("Hel", box.lines.items[0].getText(box.cells.items, box.document.items));
            try box.insertCharsAndMoveCursor("l");
            try eqStr("Hell", box.lines.items[0].getText(box.cells.items, box.document.items));
            try box.insertCharsAndMoveCursor("o");
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));
        }
        {
            var box = try UglyTextBox.fromString(a, "", 0, 0);
            defer box.destroy();
            try box.insertCharsAndMoveCursor("H");
            try eqStr("H", box.lines.items[0].getText(box.cells.items, box.document.items));
            try box.insertCharsAndMoveCursor("e");
            try eqStr("He", box.lines.items[0].getText(box.cells.items, box.document.items));
            try box.insertCharsAndMoveCursor("llo");
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));

            try box.insertCharsAndMoveCursor("\n");
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));
            try eqStr("", box.lines.items[1].getText(box.cells.items, box.document.items));

            try box.insertCharsAndMoveCursor("w");
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));
            try eqStr("w", box.lines.items[1].getText(box.cells.items, box.document.items));

            try box.insertCharsAndMoveCursor("o");
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));
            try eqStr("wo", box.lines.items[1].getText(box.cells.items, box.document.items));

            try box.insertCharsAndMoveCursor("rld");
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));
            try eqStr("world", box.lines.items[1].getText(box.cells.items, box.document.items));
        }
    }

    ///////////////////////////// Delete

    pub fn backspace(self: *UglyTextBox) !void {
        if (self.cursor.line == 0 and self.cursor.col == 0) return;

        var start_byte: usize = 0;
        var byte_count: usize = 0;

        if (self.cursor.col == 0) {
            const prev_line = self.lines.items[self.cursor.line - 1];
            const prev_line_last_cell = prev_line.cell(self.cells.items, prev_line.numOfCells()).?;
            start_byte = prev_line_last_cell.end_byte - 1;
            byte_count = 1;
        } else {
            const line = self.lines.items[self.cursor.line];
            const cell = line.cell(self.cells.items, self.cursor.col - 1).?;
            start_byte = cell.start_byte;
            byte_count = cell.len();
        }

        const new_root = try self.root.deleteBytes(self.a, start_byte, byte_count);
        self.root = new_root;

        self.document.deinit();
        self.document = try self.root.getContent(self.a);

        self.cells.deinit();
        self.lines.deinit();
        self.cells, self.lines = try _cell.createCellListAndLineList(self.a, self.document.items);
    }
    test backspace {
        const a = std.testing.allocator;
        { // backspace at end of line
            var box = try UglyTextBox.fromString(a, "Hello World!", 0, 0);
            defer box.destroy();
            box.moveCursorRight(100);
            try box.backspace();
            try eqStr("Hello World", box.lines.items[0].getText(box.cells.items, box.document.items));
        }
        { // backspace in middle of line
            var box = try UglyTextBox.fromString(a, "Hello World!", 0, 0);
            defer box.destroy();
            box.moveCursorRight(100);
            box.moveCursorLeft(1);
            try box.backspace();
            try eqStr("Hello Worl!", box.lines.items[0].getText(box.cells.items, box.document.items));
        }
        { // backspace at start of document, should do nothing
            var box = try UglyTextBox.fromString(a, "Hello World!", 0, 0);
            defer box.destroy();
            try box.backspace();
            try eqStr("Hello World!", box.lines.items[0].getText(box.cells.items, box.document.items));
        }
        { // backspace at start of line that's not the first line of document
            var box = try UglyTextBox.fromString(a, "Hello\nWorld!", 0, 0);
            defer box.destroy();
            try eqStr("Hello", box.lines.items[0].getText(box.cells.items, box.document.items));
            try eqStr("World!", box.lines.items[1].getText(box.cells.items, box.document.items));

            box.cursor.set(1, 0);
            try box.backspace();
            try eq(1, box.lines.items.len);
        }
    }
};

test {
    std.testing.refAllDecls(UglyTextBox);
}
