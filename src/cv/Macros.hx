package cv;

import haxe.macro.Context;
import haxe.macro.Expr;

@:autoBuild(cv.CvConstsImpl.run())
@:remove extern interface CvConsts {}

//
// @:CvConst var X;
//
// replaced by
//
// public static var X(get,never):Int;
// static inline function get_X() return load("X", 0)();
//
class CvConstsImpl {
#if macro
    static function isConst(f:Metadata) {
        for (m in f) {
            if (m.name == ":CvConst") return true;
        }
        return false;
    }

    public static function run() {
        var fields = Context.getBuildFields();
        for (f in fields) {
            if (!isConst(f.meta)) {
                continue;
            }

            switch (f.kind) {
            case FVar(_, _):
                f.kind = FProp("get", "never", macro :Int, null);
                f.access.push(AStatic);
                f.access.push(APublic);

                var kind = FFun({
                    ret:    macro :Int,
                    params: [],
                    args:   [],
                    expr:   macro return load($v{f.name}, 0)()
                });
                fields.push({
                    pos:    f.pos,
                    name:   "get_"+f.name,
                    meta:   [],
                    kind:   kind,
                    doc:    null,
                    access: [AStatic, AInline]
                });
            default:
                Context.warning("@:CvConst used on non-field type", f.pos);
            }
        }

        return fields;
    }
#end
}


@:autoBuild(cv.CvProcsImpl.run())
@:remove extern interface CvProcs {}


//
// @:CvProc function x(...) {
//    ...
// }
//
// replaced by
//
// public static inline function x(...) {
//    #if debug
//        if ($param0 == null) throw "x :: $param0 cannot be null";
//    #end
//    ...
// }
//
// for any parameter marked non-optional, and of non-basic type.
//
// to override/add additional checks use:
// {
//    @:CvCheck(?paramName) if (cond) throw "message"
//    ...
// }
// with any default check on parameter disregarded
// and the message prepended by "x :: "
//
class CvProcsImpl {
#if macro
    static function isProc(f:Metadata) {
        for (m in f) {
            if (m.name == ":CvProc") return true;
        }
        return false;
    }

    static function skippedType(t:ComplexType):Bool {
        return switch(t) {
        case macro :Int: true;
        case macro :Float: true;
        case TPath({name:"Null"}): true;
        default: false;
        }
    }

    static function process(field:Field, f:Function) {
        var skipped = new Map<String,Bool>();

        // process manual checks
        f.expr.expr = switch (f.expr.expr) {
        case EBlock(xs):
            var ys = [];
            for (x in xs) {
                switch (x.expr) {
                case EMeta({name:":CvCheck", params:params, pos:p}, y):
                    if (params.length > 1) {
                        for (n in params) {
                            skipped.set(switch (n.expr) {
                                case EConst(CIdent(n)): n;
                                default:
                                    Context.warning("@:CvCheck param should be identifier name", p);
                                    null;
                            }, true);
                        }
                    }
                    switch (y) {
                    case (macro if ($cond) throw $err else $e) if (e == null):
                        var err2 = '${field.name} :: ';
                        ys.push(macro if ($cond) throw $v{err2}+$err);
                    default:
                        Context.warning("@:CvCheck expr was not if (..) throw ..", p);
                    }
                default: ys.push(x);
                }
            }
            EBlock(ys);
        default:
            f.expr.expr;
        }

        var checks = [];
        for (arg in f.args) {
            if (arg.type == null) Context.warning("@:CvProc should have arg types declared", field.pos);
            if (arg.opt || skippedType(arg.type)) continue;

            if (skipped.get(arg.name)) continue;

            var err = '${field.name} :: ${arg.name} cannot be null';
            checks.push(macro
                if ($i{arg.name} == null) throw $v{err}
            );
        }
        f.expr = macro { $b{checks}; $e{f.expr} };
        field.access.push(AStatic);
        field.access.push(APublic);
        field.access.push(AInline);
    }

    static function run() {
        var fields = Context.getBuildFields();
        if (!Context.defined("debug")) return fields;

        for (f in fields) {
            if (!isProc(f.meta)) continue;

            switch (f.kind) {
            case FFun(g):
                process(f, g);
            default:
                Context.warning("@:CvProc used on non-method type", f.pos);
            }
        }
        return fields;
    }
#end
}
