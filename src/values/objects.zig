pub const ObjType = enum {
    MODULE,
};

pub const Obj = struct {
    type: ObjType,
    isMarked: bool,
};

pub const ObjModule = struct {
    obj: Obj,
};
