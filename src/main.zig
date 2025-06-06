const std = @import("std");
pub fn main() !void {
    const config = @import("./config.zig");
    config.debug_print_code = true;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    config.allocator = gpa.allocator();
    config.dough_allocator = @import("core/memory.zig").GarbageColletingAllocator.init(config.allocator);

    const allocator = config.allocator;

    var file = try std.fs.cwd().openFile("test.dough", .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, config.MAX_FILE_SIZE);
    {
        defer allocator.free(source);

        //    var vm = @import("core/vm.zig").VirtualMachine.init(allocator);
        var compiler = @import("core/compiler.zig").ModuleCompiler.init(source);
        _ = try compiler.compile();
    }
    // run vm

    std.debug.print("\n\n===== CompileProperties =====\n\n", .{});

    std.debug.print(" + {d} (depth)\n", .{@sizeOf(u24)});
    std.debug.print(" + {d} (identifier)\n", .{@sizeOf([]const u8)});
    std.debug.print(" + {d} (shadowsAddress)\n", .{@sizeOf(?@import("types.zig").SlotAddress)});
    std.debug.print(" + {d} (intent)\n", .{@sizeOf(?Intent)});
    std.debug.print(" = \n", .{});

    std.debug.print("{d}\n\n", .{@sizeOf(SlotProperties)});

    std.debug.print("\n\n===== RuntimeProperties =====\n\n", .{});

    std.debug.print(" + {d} (value)\n", .{@sizeOf(@import("values/values.zig").Value)});
    std.debug.print(" + {d} (identifier)\n", .{@sizeOf([]const u8)});
    std.debug.print(" = \n", .{});

    std.debug.print("{d}\n\n", .{@sizeOf(RuntimeProperties)});

    std.debug.print("\n\n===== DoughString =====\n\n", .{});
    std.debug.print("{d}\n\n", .{@sizeOf(@import("values/objects.zig").DoughString)});
}

pub const Intent = enum {
    Define,
    Read,
    Write,
};

pub const SlotProperties = struct {
    depth: u24 = 0,
    identifier: []const u8,
    shadowsAddress: ?@import("./types.zig").SlotAddress = null,

    intent: ?Intent = null,

    fn applyIntent(properties: *SlotProperties, intent: Intent) void {
        if (intent == .Define) {
            properties.intent = null;
        } else if (properties.intent == null or @intFromEnum(intent) > @intFromEnum(properties.intent.?)) {
            properties.intent = intent;
        }
    }
};

pub const RuntimeProperties = struct {
    value: @import("values/values.zig").Value,
    //    identifier: []const u8,
};
