const std = @import("std");
const rl = @import("raylib");

const kbs = @import("keyboard/state.zig");
const exp = @import("keyboard/experimental_mappings.zig");

const eql = std.mem.eql;

//////////////////////////////////////////////////////////////////////////////////////////////

const screen_width = 1920;
const screen_height = 1080;

pub fn main() anyerror!void {
    ///////////////////////////// Window Initialization

    rl.setConfigFlags(.{ .window_transparent = true });

    rl.initWindow(screen_width, screen_height, "Ugly");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    rl.setExitKey(rl.KeyboardKey.key_null);

    ///////////////////////////// Controller

    var gpa__ = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa__.deinit();
    const gpa = gpa__.allocator();

    var kem = try kbs.KeyboardEventsManager.init(gpa);
    defer kem.deinit();

    // const font = rl.loadFontEx("Meslo LG L DZ Regular Nerd Font Complete Mono.ttf", 40, null);

    var trigger_map = try exp.createTriggerMap(gpa);
    defer trigger_map.deinit();

    var prefix_map = try exp.createPrefixMap(gpa);
    defer prefix_map.deinit();

    const TriggerCandidateComposer = kbs.GenericTriggerCandidateComposer(exp.TriggerMap, exp.PrefixMap);
    var composer = try TriggerCandidateComposer.init(gpa, &trigger_map, &prefix_map);
    defer composer.deinit();

    const TriggerPicker = kbs.GenericTriggerPicker(exp.TriggerMap);
    var picker = try TriggerPicker.init(gpa, &trigger_map);
    defer picker.deinit();

    ///////////////////////////// Model

    const Rectangle = struct {
        x: i32 = 0,
        y: i32 = 0,
        width: i32 = 100,
        height: i32 = 100,
        color: rl.Color = rl.Color.yellow,
    };
    var rectangles = std.ArrayList(Rectangle).init(gpa);
    defer rectangles.deinit();

    ///////////////////////////// Main Loop

    while (!rl.windowShouldClose()) {
        try kem.startHandlingInputs();
        {
            const input_steps = try kem.inputSteps();
            defer input_steps.deinit();

            for (input_steps.items) |step| {
                const insert_mode_active = true;
                var trigger: []const u8 = "";

                const candidate = try composer.getTriggerCandidate(step.old, step.new);
                if (!insert_mode_active) {
                    if (candidate) |c| trigger = c;
                }
                if (insert_mode_active) {
                    const may_final_trigger = try picker.getFinalTrigger(step.old, step.new, step.time, candidate);
                    if (may_final_trigger) |t| trigger = t;
                }

                if (!eql(u8, trigger, "")) {
                    defer picker.a.free(trigger);

                    if (eql(u8, trigger, "c")) try rectangles.append(Rectangle{ .x = rl.getMouseX(), .y = rl.getMouseY() });
                }
            }
        }
        try kem.finishHandlingInputs();

        // View
        rl.beginDrawing();
        defer rl.endDrawing();
        {
            rl.clearBackground(rl.Color.blank);

            { // draw rectangles

                for (rectangles.items) |rec| {
                    rl.drawRectangle(rec.x, rec.y, rec.width, rec.height, rec.color);
                }
            }
        }
    }
}
