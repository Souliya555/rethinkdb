// Autogenerated by metajava.py.
// Do not edit this file directly.
// The template for this file is located at:
// ../../../../../../../../templates/AstSubclass.java
package com.rethinkdb.ast.gen;

import java.util.Optional;
import com.rethinkdb.ast.ReqlAst;
import com.rethinkdb.ast.helper.Arguments;
import com.rethinkdb.ast.helper.OptArgs;
import com.rethinkdb.proto.TermType;



public class PolygonSub extends ReqlQuery {


    public PolygonSub(java.lang.Object arg) {
        this(new Arguments(arg), null);
    }
    public PolygonSub(Arguments args, OptArgs optargs) {
        this(null, args, optargs);
    }
    public PolygonSub(ReqlAst prev, Arguments args, OptArgs optargs) {
        this(prev, TermType.POLYGON_SUB, args, optargs);
    }
    protected PolygonSub(ReqlAst previous, TermType termType, Arguments args, OptArgs optargs){
        super(previous, termType, args, optargs);
    }


    /* Static factories */
    public static PolygonSub fromArgs(Object... args){
        return new PolygonSub(new Arguments(args), null);
    }


}