﻿dpq2
====
[![Build Status](https://travis-ci.org/denizzzka/dpq2.svg?branch=master)](https://travis-ci.org/denizzzka/dpq2)
[![Coverage Status](https://coveralls.io/repos/denizzzka/dpq2/badge.svg?branch=master)](https://coveralls.io/r/denizzzka/dpq2)
[![codecov.io](https://codecov.io/github/denizzzka/dpq2/coverage.svg?branch=master)](https://codecov.io/github/denizzzka/dpq2)

This is yet another attempt to create a good interface to PostgreSQL for the 
D programming language.

It adds only tiny overhead to the original low level library libpq but
make convenient use PostgreSQL from D.

[API documentation](https://denizzzka.github.io/dpq2/docs)

_Please help us to make documentation better!_

Features
--------

* Text string arguments support
* Binary arguments support (including multi-dimensional arrays)
* Both text and binary formats of query result support
* Immutable query result for simplify multithreading
* Async queries support
* Reading of the text query results to native D text types
* Representation of binary arguments and binary query results as native D types
 * Text types
 * Integer and decimal types
 * Money type (into money.currency, https://github.com/dlang-community/d-money)
 * Some data and time types
 * JSON type (stored into vibe.data.json.Json)
 * JSONB type (ditto)
 * Geometric types
* Conversion of values to BSON (into vibe.data.bson.Bson)
* Access to PostgreSQL's multidimensional arrays
* LISTEN/NOTIFY support
* Bulk data upload to table from string data ([SQL COPY](https://www.postgresql.org/docs/current/sql-copy.html))
* Simple SQL query builder

Building
--------

Bindings for libpq can be static or dynamic.
The static bindings are generated by default.

Example
-------
```D
#!/usr/bin/env rdmd

import dpq2;
import std.getopt;
import std.stdio: writeln;
import std.typecons: Nullable;
import vibe.data.bson;

void main(string[] args)
{
    string connInfo;
    getopt(args, "conninfo", &connInfo);

    Connection conn = new Connection(connInfo);

    // Only text query result can be obtained by this call:
    auto answer = conn.exec(
        "SELECT now()::timestamp as current_time, 'abc'::text as field_name, "~
        "123 as field_3, 456.78 as field_4, '{\"JSON field name\": 123.456}'::json"
        );

    writeln( "Text query result by name: ", answer[0]["current_time"].as!PGtext );
    writeln( "Text query result by index: ", answer[0][3].as!PGtext );

    // It is possible to read values of unknown type using BSON:
    auto firstRow = answer[0];
    foreach(cell; rangify(firstRow))
    {
        writeln("bson: ", cell.as!Bson);
    }

    // Binary arguments query with binary result:
    QueryParams p;
    p.sqlCommand = "SELECT "~
        "$1::double precision as double_field, "~
        "$2::text, "~
        "$3::text as null_field, "~
        "array['first', 'second', NULL]::text[] as array_field, "~
        "$4::integer[] as multi_array, "~
        "'{\"float_value\": 123.456,\"text_str\": \"text string\"}'::json as json_value";

    p.argsVariadic(
        -1234.56789012345,
        "first line\nsecond line",
        Nullable!string.init,
        [[1, 2, 3], [4, 5, 6]]
    );

    auto r = conn.execParams(p);
    scope(exit) destroy(r);

    writeln( "0: ", r[0]["double_field"].as!PGdouble_precision );
    writeln( "1: ", r[0][1].as!PGtext );
    writeln( "2.1 isNull: ", r[0][2].isNull );
    writeln( "2.2 isNULL: ", r[0].isNULL(2) );
    writeln( "3.1: ", r[0][3].asArray[0].as!PGtext );
    writeln( "3.2: ", r[0][3].asArray[1].as!PGtext );
    writeln( "3.3: ", r[0]["array_field"].asArray[2].isNull );
    writeln( "3.4: ", r[0]["array_field"].asArray.isNULL(2) );
    writeln( "4.1: ", r[0]["multi_array"].asArray.getValue(1, 2).as!PGinteger );
    writeln( "4.2: ", r[0]["multi_array"].as!(int[][]) );
    writeln( "5.1 Json: ", r[0]["json_value"].as!Json);
    writeln( "5.2 Bson: ", r[0]["json_value"].as!Bson);

    // It is possible to read values of unknown type using BSON:
    for(auto column = 0; column < r.columnCount; column++)
    {
        writeln("column name: '"~r.columnName(column)~"', bson: ", r[0][column].as!Bson);
    }

    // It is possible to upload CSV data ultra-fast:
    conn.exec("CREATE TEMP TABLE test_dpq2_copy (v1 TEXT, v2 INT)");

    // Init the COPY command. This sets the connection in a COPY receive
    // mode until putCopyEnd() is called. Copy CSV data, because it's standard,
    // ultra fast, and readable:
    conn.exec("COPY test_dpq2_copy FROM STDIN WITH (FORMAT csv)");

    // Write 2 lines of CSV, including text that contains the delimiter.
    // Postgresql handles it well:
    string data = "\"This, right here, is a test\",8\nWow! it works,13\n";
    conn.putCopyData(data);

    // Write 2 more lines
    data = "Horray!,3456\nSuper fast!,325\n";
    conn.putCopyData(data);

    // Signal that the COPY is finished. Let Postgresql finalize the command
    // and return any errors with the data.
    conn.putCopyEnd();
}
```

Compile and run:
```
Running ./dpq2_example --conninfo=user=postgres
2018-12-09T10:08:07.862:package.d:__lambda1:19 DerelictPQ loading...
2018-12-09T10:08:07.863:package.d:__lambda1:26 ...DerelictPQ loading finished
Text query result by name: 2018-12-09 10:08:07.868141
Text query result by index: 456.78
bson: "2018-12-09 10:08:07.868141"
bson: "abc"
bson: "123"
bson: "456.78"
bson: {"JSON field name":123.456}
0: -1234.57
1: first line
second line
2.1 isNull: true
2.2 isNULL: true
3.1: first
3.2: second
3.3: true
3.4: true
4.1: 6
4.2: [[1, 2, 3], [4, 5, 6]]
5.1 Json: {"text_str":"text string","float_value":123.456}
5.2 Bson: {"text_str":"text string","float_value":123.456}
column name: 'double_field', bson: -1234.56789012345
column name: 'text', bson: "first line\nsecond line"
column name: 'null_field', bson: null
column name: 'array_field', bson: ["first","second",null]
column name: 'multi_array', bson: [[1,2,3],[4,5,6]]
column name: 'json_value', bson: {"text_str":"text string","float_value":123.456}
```

Using dynamic version of libpq
--------
Is provided two ways to load `libpq` dynamically:

* Automatic load and unload (`dynamic` build config option)
* Manual load (and unload, if need) (`dynamic-unmanaged`)

To load automatically it is necessary to allocate `ConnectionFactory`.
This class is only available then `dynamic` config is used.
Only one instance of `ConnectionFactory` is allowed.
It is possible to specify filepath to a library/libraries what you want to use, otherwise default will be used:
```D
// Argument is a string containing one or more comma-separated
// shared library names
auto connFactory = new immutable ConnectionFactory("path/to/libpq.dll");
```

Then you can create connection by calling `createConnection` method:
```D
Connection conn = connFactory.createConnection(params);
```
And then this connection can be used as usual.

When all objects related to `libpq` (including `ConnectionFactory`) is destroyed library will be unloaded automatically.

To load manually it is necessary to use build config `dynamic-unmanaged`.
Manual dynamic `libpq` loading example:
```D
import derelict.pq.pq: DerelictPQ;
import core.memory: GC;

DerelictPQ.load();

auto conn = new Connection(connInfo);
/* Skipped rest of useful SQL processing */
conn.destroy(); // Ensure that all related to libpq objects are destroyed

GC.collect(); // Forced removal of references to libpq before library unload
DerelictPQ.unload();
```
In this case is not need to use `ConnectionFactory` - just create `Connection` by the same way as for `static` config.
