const std = @import("std");
const glfw = @import("zglfw");

pub const Key = glfw.Key;
pub const MouseButton = glfw.MouseButton;
pub const Modifiers = glfw.Mods;
pub const Action = glfw.Action;
pub const Joystick = glfw.Joystick;
pub const Gamepad = glfw.Gamepad;
pub const ScrollDirection = enum {
    vertical,
    horizontal,
};
pub const Modifier = enum {
    shift,
    control,
    alt,
    super,
    caps_lock,
    num_lock,
};


pub const JoystickState = struct {
    joystick: Joystick,

    pub inline fn getGuid(self: *const @This()) ?[:0]const u8 {
        return self.joystick.getGuid() catch return "";
    }

    pub fn isGamepad(self: *const @This()) bool {
        return self.joystick.isGamepad();
    }


    pub fn asGamepad(self: *const @This()) ?GamepadState {
        return .{
            .gamepad = self.joystick.asGamepad() orelse return null
        };
    }

    pub fn getAxis(self: *const @This(), idx: u32) ?f32 {
        const axes = self.joystick.getAxes() catch return null;
        if (idx >= axes.len) return null;
        return axes[idx];
    }

    pub fn getButton(self: *const @This(), idx: u32) ?Joystick.ButtonAction {
        const buttons = self.joystick.getButtons() catch return null;
        if (idx >= buttons.len) return null;
        return buttons[idx];
    }
};

pub const GamepadState = struct {
    gamepad: Gamepad,

    fn getName(self: *const @This()) [:0]const u8 {
        return self.gamepad.getName();
    }

    fn getAxis(self: *const @This(), axis: Gamepad.Axis) !f32 {
        const state = try self.gamepad.getState();
        return state.axes[axis];
    }

    fn getButton(self: *const @This(), button: Gamepad.Button) !Joystick.ButtonAction {
        const state = try self.gamepad.getState();
        return state.buttons[button];
    }
};

const KeyCount: usize = @intFromEnum(glfw.Key.menu);
const MouseButtonCount: usize = @intFromEnum(glfw.MouseButton.eight);

var joysticks: [Joystick.maximum_supported]?Joystick = .{ null } ** Joystick.maximum_supported;

var keys: [KeyCount]glfw.Action = .{.release} ** KeyCount;

var mouse_buttons: [MouseButtonCount]Action = .{.release} ** MouseButtonCount;
var mouse_pos: [2]f64 = .{ 0.0, 0.0 };
var scroll: [2]f64 = .{ 0.0, 0.0 };


var mods: glfw.Mods = .{};

var focusedWindow: ?*glfw.Window = null;

pub fn poll() void { 
    glfw.pollEvents();
}

pub fn getKey(key: Key) Action {
    return keys[@intCast(@intFromEnum(key))];
}

pub fn getKeyDown(key: Key) bool {
    const action = keys[@intCast(@intFromEnum(key))];
    return action == .press or action == .repeat;
}

pub fn getKeyUp(key: Key) bool {
    return keys[@intCast(@intFromEnum(key))] == .release;
}

pub fn getKeyRepeat(key: Key) bool {
    return keys[@intCast(@intFromEnum(key))] == .repeat;
}

pub fn getMouseButton(button: MouseButton) Action {
    return mouse_buttons[@intCast(@intFromEnum(button))];
}

pub fn getMouseButtonDown(key: Key) bool {
    const action = mouse_buttons[@intCast(@intFromEnum(key))];
    return action == .press or action == .repeat;
}

pub fn getMouseButtonUp(key: Key) bool {
    return mouse_buttons[@intCast(@intFromEnum(key))] == .release;
}

pub fn getMouseButtonRepeat(key: Key) bool {
    return mouse_buttons[@intCast(@intFromEnum(key))] == .repeat;
}

pub fn getMousePos() [2]f64 {
    return mouse_pos;
}

pub fn getScroll(direction: ScrollDirection) [2]f64 {
    return scroll[@intCast(@intFromEnum(direction))];
}

pub fn hasModifier(mod: Modifier) bool {
    return switch (mod) {
        .shift => mods.shift,
        .control => mods.control,
        .alt => mods.alt,
        .super => mods.super,
        .caps_lock => mods.caps_lock,
        .num_lock => mods.num_lock,
    };
}

pub fn focused() bool {
    return focusedWindow != null;
}

pub fn getFocusedWindow() ?*glfw.Window {
    return focusedWindow;
}

const GLFWJoystickFun = *const fn(jid: i32, event: glfw.Monitor.Event) callconv(.c) void;
extern fn glfwSetJoystickCallback(callback: ?GLFWJoystickFun) ?GLFWJoystickFun;

pub fn setJoystickCallback(callback: ?GLFWJoystickFun) ?GLFWJoystickFun {
    return glfwSetJoystickCallback(callback);
}

pub fn _onJoystick(jid: i32, event: glfw.Monitor.Event) callconv(.c) void {
    joysticks[@intCast(jid)] = switch (event) {
        .connected => @enumFromInt(jid),
        .disconnected => null,
    };
}

pub fn hasJoystick(jid: u4) bool {
    return joysticks[jid] != null;
}

pub fn joystick(jid: u4) ?JoystickState {
    return .{ .joystick = joysticks[jid] };
}

pub fn hasGamepad(jid: u4) bool {
    return joysticks[jid] != null and joysticks[jid].?.isGamepad();
}

pub fn gamepad(jid: u4) ?GamepadState {
    if (joysticks[jid]) |j| {
        return .{ .gamepad = j.asGamepad() orelse return null };
    }
    return null;
}

pub fn _onWindowFocusCallback(window: *glfw.Window, state: glfw.Bool) callconv(.c) void {
    if (@as(bool, @bitCast(@as(u1, @intCast(@intFromEnum(state)))))) {
        focusedWindow = window;
    } else {
        focusedWindow = null;
    }
}

pub fn _onScrollCallback(_: *glfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    scroll = .{ xoffset, yoffset };
}

pub fn _onCursorPosCallback(_: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    mouse_pos = .{ x, y };
}

pub fn _onMouseButton(_: *glfw.Window, button: MouseButton, action: glfw.Action, _: Modifiers) callconv(.c) void {
    mouse_buttons[@intCast(@intFromEnum(button))] = action;
}

pub fn _onKey(_: *glfw.Window, key: Key, scancode: i32, action: glfw.Action, _: Modifiers) callconv(.c) void {
    _ = scancode;
    keys[@intCast(@intFromEnum(key))] = action;

    const pressed = switch (action) {
        .press, .repeat => true,
        .release => false,
    };

    switch (key) {
        .left_alt, .right_alt => mods.alt = pressed,
        .left_shift, .right_shift => mods.shift = pressed,
        .left_control, .right_control => mods.control = pressed,
        .left_super, .right_super => mods.super = pressed,
        .caps_lock => mods.caps_lock = pressed,
        .num_lock => mods.num_lock = pressed,
        else => {}
    }
}
