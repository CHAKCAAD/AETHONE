const std = @import("std");
const addr = @import("../addr.zig");

pub const Action = enum(u32) {
    proxy = 0,
    direct = 1,
    drop = 2,
    reject = 3,
};

/// Stage 2 per-app routing: the C callback's u32 return packs BOTH the
/// legacy verdict and a route number:
///     ret = (route_number << 2) | action
/// `route` 0 is the default (the global `[handler]`); 1..N address the
/// `[routes]` entries in document order. Values 0..3 (every legacy caller)
/// therefore decode to their old action with route 0 — byte-compatible.
pub const Decision = struct {
    action: Action,
    route: u16,
};

pub const Flow = extern struct {
    protocol: u8,
    family: u8,
    source: [16]u8,
    destination: [16]u8,
    source_port: u16,
    destination_port: u16,
};

pub const Fn = *const fn (ctx: ?*anyopaque, flow: *const Flow) callconv(.c) u32;

pub const Judge = struct {
    call: ?Fn = null,
    ctx: ?*anyopaque = null,

    pub inline fn active(j: *const Judge) bool {
        return j.call != null;
    }

    pub fn ask(j: *const Judge, proto: u8, v6: bool, src: []const u8, src_port: u16, dst: []const u8, dst_port: u16) Decision {
        const f = j.call orelse return .{ .action = .proxy, .route = 0 };
        var flow: Flow = .{
            .protocol = proto,
            .family = if (v6) 6 else 4,
            .source = @splat(0),
            .destination = @splat(0),
            .source_port = src_port,
            .destination_port = dst_port,
        };
        const al = @min(src.len, flow.source.len);
        @memcpy(flow.source[0..al], src[0..al]);
        @memcpy(flow.destination[0..al], dst[0..al]);
        const v = f(j.ctx, &flow);
        const action: Action = switch (v & 3) {
            0 => .proxy,
            1 => .direct,
            2 => .drop,
            3 => .reject,
            else => unreachable,
        };
        // An out-of-range route number (including huge values that no longer
        // fit u16) resolves to nothing and the flow falls back to the default
        // route, counted by the caller — never to an arbitrary route.
        const route: u16 = std.math.cast(u16, v >> 2) orelse std.math.maxInt(u16);
        return .{ .action = action, .route = route };
    }
};

test "judge maps verdicts and passes the flow" {
    const Seen = struct {
        var last: Flow = undefined;
        fn answer(ctx: ?*anyopaque, flow: *const Flow) callconv(.c) u32 {
            last = flow.*;
            // ctx doubles as the raw return value the test wants to observe.
            return @intCast(@intFromPtr(ctx));
        }
    };
    var j: Judge = .{};
    try std.testing.expectEqual(Action.proxy, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1234, &[_]u8{ 1, 1, 1, 1 }, 443).action);
    j = .{ .call = Seen.answer, .ctx = @ptrFromInt(3) };
    try std.testing.expectEqual(Action.reject, j.ask(17, false, &[_]u8{ 10, 0, 0, 2 }, 1234, &[_]u8{ 1, 1, 1, 1 }, 53).action);
    try std.testing.expectEqual(@as(u8, 17), Seen.last.protocol);
    try std.testing.expectEqual(@as(u16, 53), Seen.last.destination_port);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 10, 0, 0, 2 }, Seen.last.source[0..4]);
}

test "judge legacy verdicts decode to the default route" {
    const Fixed = struct {
        var value: u32 = 0;
        fn answer(_: ?*anyopaque, _: *const Flow) callconv(.c) u32 {
            return value;
        }
    };
    var j: Judge = .{ .call = Fixed.answer, .ctx = null };
    Fixed.value = 0;
    try std.testing.expectEqual(Decision{ .action = .proxy, .route = 0 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
    Fixed.value = 1;
    try std.testing.expectEqual(Decision{ .action = .direct, .route = 0 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
    Fixed.value = 2;
    try std.testing.expectEqual(Decision{ .action = .drop, .route = 0 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
    Fixed.value = 3;
    try std.testing.expectEqual(Decision{ .action = .reject, .route = 0 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
}

test "judge packs route numbers with an action" {
    const Fixed = struct {
        var value: u32 = 0;
        fn answer(_: ?*anyopaque, _: *const Flow) callconv(.c) u32 {
            return value;
        }
    };
    var j: Judge = .{ .call = Fixed.answer, .ctx = null };
    // route 1, action proxy -> (1 << 2) | 0
    Fixed.value = 4;
    try std.testing.expectEqual(Decision{ .action = .proxy, .route = 1 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
    // route 3, action direct -> (3 << 2) | 1
    Fixed.value = 13;
    try std.testing.expectEqual(Decision{ .action = .direct, .route = 3 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
    // route 8, action reject -> (8 << 2) | 3
    Fixed.value = 35;
    try std.testing.expectEqual(Decision{ .action = .reject, .route = 8 }, j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2));
    // a route number that no longer fits u16 is an invalid route, never a wrap
    Fixed.value = 0x4000_0004;
    const d = j.ask(6, false, &[_]u8{ 10, 0, 0, 2 }, 1, &[_]u8{ 1, 1, 1, 1 }, 2);
    try std.testing.expectEqual(Action.proxy, d.action);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), d.route);
}

test "judge inactive defaults to proxy on the default route" {
    const j: Judge = .{};
    try std.testing.expectEqual(Decision{ .action = .proxy, .route = 0 }, j.ask(6, true, &[_]u8{0} ** 16, 1, &[_]u8{0} ** 16, 2));
}
