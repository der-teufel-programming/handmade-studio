// Copied & Edited from https://github.com/ziglibs/treez

const std = @import("std");
const b = @import("bindings.zig");

const Query = b.Query;
const PredicateStep = b.Query.PredicateStep;
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

//////////////////////////////////////////////////////////////////////////////////////////////

pub const PredicatesFilter = struct {
    external_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    a: std.mem.Allocator,
    patterns: [][]Predicate,

    pub fn init(external_allocator: Allocator, query: *const Query) !*@This() {
        var self = try external_allocator.create(@This());

        self.* = .{
            .external_allocator = external_allocator,
            .arena = std.heap.ArenaAllocator.init(external_allocator),
            .a = self.arena.allocator(),
            .patterns = undefined,
        };

        var patterns = std.ArrayList([]Predicate).init(self.a);
        errdefer patterns.deinit();
        for (0..query.getPatternCount()) |pattern_index| {
            const steps = query.getPredicatesForPattern(@as(u32, @intCast(pattern_index)));
            var predicates = std.ArrayList(Predicate).init(self.a);
            errdefer predicates.deinit();

            var start: usize = 0;
            for (steps, 0..) |step, i| {
                if (step.type == .done) {
                    const predicate = try Predicate.create(self.a, query, steps[start .. i + 1]);
                    try predicates.append(predicate);
                    start = i + 1;
                }
            }

            try patterns.append(try predicates.toOwnedSlice());
        }

        self.*.patterns = try patterns.toOwnedSlice();
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
        self.external_allocator.destroy(self);
    }

    fn isValid(self: *@This(), source: []const u8, match: Query.Match) bool {
        for (match.captures()) |cap| {
            const node = cap.node;
            const node_contents = source[node.getStartByte()..node.getEndByte()];
            const predicates = self.patterns[match.pattern_index];
            for (predicates) |predicate| if (!predicate.eval(node_contents)) return false;
        }
        return true;
    }

    pub fn nextMatch(self: *@This(), source: []const u8, cursor: *Query.Cursor) ?Query.Match {
        while (true) {
            const match = cursor.nextMatch() orelse return null;
            if (self.isValid(source, match)) return match;
        }
    }

    /////////////////////////////

    const EqPredicate = struct {
        capture: []const u8,
        target: []const u8,

        fn create(query: *const Query, steps: []const PredicateStep) PredicateError!Predicate {
            if (steps.len != 4) {
                std.log.err("Expected steps.len == 4, got {d}\n", .{steps.len});
                return PredicateError.InvalidAmountOfSteps;
            }
            if (steps[1].type != .capture) {
                std.log.err("First argument of #eq? predicate must be type .capture, got {any}", .{steps[1].type});
                return PredicateError.InvalidArgument;
            }
            if (steps[2].type != .string) {
                std.log.err("Second argument of #eq? predicate must be type .string, got {any}", .{steps[2].type});
                return PredicateError.InvalidArgument;
            }
            return Predicate{
                .eq = EqPredicate{
                    .capture = query.getCaptureNameForId(@as(u32, @intCast(steps[1].value_id))),
                    .target = query.getStringValueForId(@as(u32, @intCast(steps[2].value_id))),
                },
            };
        }

        fn eval(self: *const EqPredicate, source: []const u8) bool {
            return eql(u8, source, self.target);
        }
    };

    const AnyOfPredicate = struct {
        capture: []const u8,
        targets: [][]const u8,

        fn create(a: Allocator, query: *const Query, steps: []const PredicateStep) PredicateError!Predicate {
            if (steps.len < 4) {
                std.log.err("Expected steps.len to be < 4, got {d}\n", .{steps.len});
                return PredicateError.InvalidAmountOfSteps;
            }
            if (steps[1].type != .capture) {
                std.log.err("First argument of #eq? predicate must be type .capture, got {any}", .{steps[1].type});
                return PredicateError.InvalidArgument;
            }

            var targets = std.ArrayList([]const u8).init(a);
            errdefer targets.deinit();
            for (2..steps.len - 1) |i| {
                if (steps[i].type != .string) {
                    std.log.err("Arguments second and beyond of #any-of? predicate must be type .string, got {any}", .{steps[i].type});
                    return PredicateError.InvalidArgument;
                }
                try targets.append(query.getStringValueForId(steps[i].value_id));
            }

            return Predicate{
                .any_of = AnyOfPredicate{
                    .capture = query.getCaptureNameForId(@as(u32, @intCast(steps[1].value_id))),
                    .targets = try targets.toOwnedSlice(),
                },
            };
        }

        fn eval(self: *const AnyOfPredicate, source: []const u8) bool {
            for (self.targets) |target| if (eql(u8, source, target)) return true;
            return false;
        }
    };

    const PredicateError = error{ InvalidAmountOfSteps, InvalidArgument, OutOfMemory, Unknown };
    const Predicate = union(enum) {
        eq: EqPredicate,
        any_of: AnyOfPredicate,
        unsupported: enum { unsupported },

        fn create(a: Allocator, query: *const Query, steps: []const PredicateStep) PredicateError!Predicate {
            if (steps[0].type != .string) {
                std.log.err("First step of predicate isn't .string.", .{});
                return PredicateError.Unknown;
            }
            const name = query.getStringValueForId(@as(u32, @intCast(steps[0].value_id)));

            if (steps[steps.len - 1].type != .done) {
                std.log.err("Last step of predicate {s} isn't .done.", .{name});
                return PredicateError.InvalidArgument;
            }

            if (eql(u8, name, "eq?")) return EqPredicate.create(query, steps);
            if (eql(u8, name, "any-of?")) return AnyOfPredicate.create(a, query, steps);
            return Predicate{ .unsupported = .unsupported };
        }

        fn eval(self: *const Predicate, source: []const u8) bool {
            return switch (self.*) {
                .eq => self.eq.eval(source),
                .any_of => self.any_of.eval(source),
                .unsupported => true,
            };
        }
    };
};
