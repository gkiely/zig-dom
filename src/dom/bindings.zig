const quickjs = @import("quickjs");
const c = quickjs.c;

pub const DomClassesError = error{
    OutOfMemory,
    RegistrationFailed,
    PropertyAccessFailed,
};

pub fn installConstructor(ctx: *quickjs.Context, global: quickjs.Value, name: [:0]const u8, comptime func: quickjs.cfunc.Func) DomClassesError!quickjs.Value {
    const proto = quickjs.Value.initObject(ctx);
    if (proto.isException()) return error.OutOfMemory;
    const ctor = quickjs.Value.initCFunction2(ctx, func, name, 1, .constructor_or_func, 0);
    if (ctor.isException()) {
        proto.deinit(ctx);
        return error.OutOfMemory;
    }
    ctor.setConstructor(ctx, proto);
    global.setPropertyStr(ctx, name.ptr, ctor.dup(ctx)) catch {
        proto.deinit(ctx);
        ctor.deinit(ctx);
        return error.PropertyAccessFailed;
    };
    ctor.deinit(ctx);
    return proto;
}

pub fn installMethod(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime func: quickjs.cfunc.Func,
    arg_count: i32,
) DomClassesError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) {
        return error.OutOfMemory;
    }

    target.setPropertyStr(ctx, name.ptr, value) catch {
        return error.PropertyAccessFailed;
    };
}

pub fn installGetter(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime getter: quickjs.cfunc.Getter,
) DomClassesError!void {
    const atom = quickjs.Atom.init(ctx, name);
    defer atom.deinit(ctx);

    const getter_value = quickjs.Value.fromCVal(c.JS_NewCFunction2(
        ctx.cval(),
        @ptrCast(quickjs.cfunc.wrapGetter(getter)),
        name.ptr,
        0,
        c.JS_CFUNC_getter,
        0,
    ));
    if (getter_value.isException()) {
        return error.OutOfMemory;
    }

    _ = target.definePropertyGetSet(ctx, atom, getter_value, quickjs.Value.undefined, .{
        .configurable = true,
        .enumerable = true,
    }) catch return error.PropertyAccessFailed;
}

pub fn installAccessor(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime getter: quickjs.cfunc.Getter,
    comptime setter: quickjs.cfunc.Setter,
) DomClassesError!void {
    const atom = quickjs.Atom.init(ctx, name);
    defer atom.deinit(ctx);

    const getter_value = quickjs.Value.fromCVal(c.JS_NewCFunction2(
        ctx.cval(),
        @ptrCast(quickjs.cfunc.wrapGetter(getter)),
        name.ptr,
        0,
        c.JS_CFUNC_getter,
        0,
    ));
    if (getter_value.isException()) {
        return error.OutOfMemory;
    }

    const setter_value = quickjs.Value.fromCVal(c.JS_NewCFunction2(
        ctx.cval(),
        @ptrCast(quickjs.cfunc.wrapSetter(setter)),
        name.ptr,
        1,
        c.JS_CFUNC_setter,
        0,
    ));
    if (setter_value.isException()) {
        getter_value.deinit(ctx);
        return error.OutOfMemory;
    }

    _ = target.definePropertyGetSet(ctx, atom, getter_value, setter_value, .{
        .configurable = true,
        .enumerable = true,
    }) catch return error.PropertyAccessFailed;
}
