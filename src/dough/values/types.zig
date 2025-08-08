pub const TypeError = error{NoSimpleType};

pub const FunctionMeta = struct {
    parameter_types: []Type,
    return_type: Type,
};

pub const Type = union(enum) {
    Void,
    Null,
    Bool,
    Number,
    String,
    Function: *FunctionMeta,
    Module,

    pub fn makeVoid() Type {
        return Type{ .Void = {} };
    }

    pub fn fromToken(token: Token) !Type {
        return switch (token.lexeme.?[0]) {
            'V' => matchIdentifier(token, "oid", 1, 3, .Void),
            'N' => |_| N_case: {
                if (token.lexeme.?.len > 1) {
                    break :N_case switch (token.lexeme.?[1]) {
                        'u' => |_| Nu_case: {
                            if (token.lexeme.?.len > 2) {
                                break :Nu_case switch (token.lexeme.?[2]) {
                                    'l' => matchIdentifier(token, "l", 3, 1, .Null),
                                    'm' => matchIdentifier(token, "ber", 3, 3, .Number),
                                    else => TypeError.NoSimpleType,
                                };
                            }
                            break :Nu_case TypeError.NoSimpleType;
                        },
                        else => TypeError.NoSimpleType,
                    };
                }
                break :N_case TypeError.NoSimpleType;
            },
            'B' => matchIdentifier(token, "ool", 1, 3, .Bool),
            'S' => matchIdentifier(token, "tring", 1, 5, .String),
            else => TypeError.NoSimpleType,
        };
    }
};

fn matchIdentifier(token: Token, rest: []const u8, start: u8, length: u8, t: Type) !Type {
    if (token.lexeme.?.len == start + length and std.mem.eql(u8, token.lexeme.?[start..(start + length)], rest)) {
        return t;
    }
    return TypeError.NoSimpleType;
}

const std = @import("std");
const dough = @import("dough");
const Token = dough.frontend.Token;
