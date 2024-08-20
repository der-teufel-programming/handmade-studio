const std = @import("std");
const rl = @import("raylib");

//////////////////////////////////////////////////////////////////////////////////////////////

const screen_width = 1920;
const screen_height = 1080;

pub fn main() !void {

    ///////////////////////////// Window Initialization

    rl.setConfigFlags(.{ .window_transparent = true, .vsync_hint = true });

    rl.initWindow(screen_width, screen_height, "DragCameraExample");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    rl.setExitKey(rl.KeyboardKey.key_null);

    ///////////////////////////// Model

    var camera = rl.Camera2D{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1,
    };

    const font_size = 30;
    const font = rl.loadFontEx("Meslo LG L DZ Regular Nerd Font Complete Mono.ttf", font_size, null);

    ///////////////////////////// Texture

    var did_draw_to_render_texture = false;
    const render_texture = rl.loadRenderTexture(1920, 1080);

    ////////////////////////////////////////////////////////////////////////////////////////////// Main Loop

    while (!rl.windowShouldClose()) {

        ///////////////////////////// Update

        if (rl.isMouseButtonDown(.mouse_button_right)) {
            var delta = rl.getMouseDelta();
            delta = delta.scale(-1 / camera.zoom);
            camera.target = delta.add(camera.target);
        }

        {
            const wheel = rl.getMouseWheelMove();
            if (wheel != 0) {
                const mouse_pos = rl.getMousePosition();
                const mouse_world_pos = rl.getScreenToWorld2D(mouse_pos, camera);
                camera.offset = mouse_pos;
                camera.target = mouse_world_pos;

                var scale_factor = 1 + (0.25 * @abs(wheel));
                if (wheel < 0) scale_factor = 1 / scale_factor;
                camera.zoom = rl.math.clamp(camera.zoom * scale_factor, 0.125, 64);
            }
        }

        ///////////////////////////// Draw

        rl.beginDrawing();
        defer rl.endDrawing();
        {
            rl.clearBackground(rl.Color.blank);
            rl.drawFPS(10, 10);

            if (!did_draw_to_render_texture) {
                render_texture.begin();
                defer render_texture.end();
                defer did_draw_to_render_texture = true;

                rl.drawText("super idol", 100, 100, 30, rl.Color.ray_white);
                rl.drawText("de xiao rong", 100, 400, 30, rl.Color.ray_white);
            }

            {
                {
                    rl.beginMode2D(camera);
                    defer rl.endMode2D();

                    rl.drawText("okayge", 100, 100, 30, rl.Color.ray_white);
                    rl.drawCircle(200, 500, 100, rl.Color.yellow);

                    const measure = rl.measureTextEx(font, "a", 20, 0);

                    var buf: [1024]u8 = undefined;
                    const txt = try std.fmt.bufPrintZ(&buf, "measure width {d} | height {d}", .{ measure.x, measure.y });
                    rl.drawText(txt, 300, 300, 40, rl.Color.ray_white);

                    rl.drawTextureRec(
                        render_texture.texture,
                        rl.Rectangle{
                            .x = 0,
                            .y = 0,
                            .width = @floatFromInt(render_texture.texture.width),
                            .height = @floatFromInt(-render_texture.texture.height),
                        },
                        .{ .x = 100, .y = 600 },
                        rl.Color.white,
                    );

                    {
                        rl.drawRectangleLines(0, 0, screen_width, screen_height, rl.Color.sky_blue);
                    }
                }

                {
                    try drawTextAtBottomRight(
                        "x: {d} | y: {d} <- camera.offset",
                        .{ camera.offset.x, camera.offset.y },
                        30,
                        .{ .x = 40, .y = 40 },
                    );

                    try drawTextAtBottomRight(
                        "x: {d} | y: {d} <- camera.target",
                        .{ camera.target.x, camera.target.y },
                        30,
                        .{ .x = 40, .y = 100 },
                    );

                    try drawTextAtBottomRight(
                        "{d} <- camera.zoom",
                        .{camera.zoom},
                        30,
                        .{ .x = 40, .y = 160 },
                    );

                    const acksual_x = (camera.target.x - camera.offset.x / camera.zoom);
                    const acksual_y = (camera.target.y - camera.offset.y / camera.zoom);
                    try drawTextAtBottomRight(
                        "x: {d} | y: {d} <- acksual coordinates",
                        .{ acksual_x, acksual_y },
                        30,
                        .{ .x = 40, .y = 220 },
                    );

                    const acksual_width = (screen_width / camera.zoom);
                    const acksual_height = (screen_height / camera.zoom);
                    try drawTextAtBottomRight(
                        "acksual_w: {d} | acksual_h: {d}",
                        .{ acksual_width, acksual_height },
                        30,
                        .{ .x = 40, .y = 280 },
                    );

                    const view_start = rl.getScreenToWorld2D(.{ .x = 0, .y = 0 }, camera);
                    const view_end = rl.getScreenToWorld2D(.{ .x = screen_width, .y = screen_height }, camera);
                    const view_width = view_end.x - view_start.x;
                    const view_height = view_end.y - view_start.y;

                    try drawTextAtBottomRight(
                        "view_width: {d} | view_height: {d}",
                        .{ view_width, view_height },
                        30,
                        .{ .x = 40, .y = 360 },
                    );

                    try drawTextAtBottomRight(
                        "start_x: {d} | start_y: {d}",
                        .{ view_start.x, view_start.y },
                        30,
                        .{ .x = 40, .y = 420 },
                    );
                }
            }
        }
    }
}

fn drawTextAtBottomRight(comptime fmt: []const u8, args: anytype, font_size: i32, offset: rl.Vector2) !void {
    var buf: [1024]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buf, fmt, args);
    const measure = rl.measureText(text, font_size);
    const x = screen_width - measure - @as(i32, @intFromFloat(offset.x));
    const y = screen_height - font_size - @as(i32, @intFromFloat(offset.y));
    rl.drawText(text, x, y, font_size, rl.Color.ray_white);
}
