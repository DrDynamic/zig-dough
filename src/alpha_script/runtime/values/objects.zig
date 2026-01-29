pub const ObjectType = enum(u8) {
    string,
};

pub const ObjectHeader = struct {
    tag: ObjectType,
    is_marked: bool,
    next: ?*ObjectHeader,
};

pub const ObjString = struct {
    header: ObjectHeader,
    data: []const u8,
};
