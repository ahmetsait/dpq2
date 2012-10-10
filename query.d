module dpq2.query;
@trusted:

import dpq2.libpq;
import dpq2.answer;
public import dpq2.connection;
public import dpq2.libpq: valueFormat;

/// Query parameters
struct queryParams
{
    string sqlCommand; /// SQL command
    queryArg[] args; /// SQL command arguments
    valueFormat resultFormat = valueFormat.TEXT; /// Result value format
}

/// Query argument
struct queryArg
{
    Oid type = 0;
    valueFormat queryFormat = valueFormat.TEXT; /// Value format

    /// Argument value
    union
    {
        ubyte[] valueBin; /// Binary variant
        string valueStr; /// Text variant
    };
}

/// Connection
final class Connection: BaseConnection
{
    /// Perform SQL query to DB
    immutable (answer) exec( string SQLcmd )
    {
        return new answer(
            PQexec(conn, toStringz( SQLcmd ))
        );
    }

    /// Perform SQL query to DB
    immutable (answer) exec(ref const queryParams p)
    {
        auto a = prepareArgs( p );
        return new answer
        (
            PQexecParams (
                conn,
                toStringz( p.sqlCommand ),
                p.args.length,
                a.types.ptr,
                a.values.ptr,
                a.lengths.ptr,
                a.formats.ptr,
                p.resultFormat
            )
        );
    }
    
    void sendQuery( string SQLcmd )
    {
        size_t r = PQsendQuery(conn, toStringz( SQLcmd ));
        if( r ) throw new exception();
    }
    
    void sendQuery( ref const queryParams p )
    {
        auto a = prepareArgs( p );
        size_t r = PQsendQueryParams (
                        conn,
                        toStringz( p.sqlCommand ),
                        p.args.length,
                        a.types.ptr,
                        a.values.ptr,
                        a.lengths.ptr,
                        a.formats.ptr,
                        p.resultFormat                        
                    );
        
        if( r ) throw new exception();
    }
    
    immutable (answer) getResult()
    {
        return new answer( PQgetResult( conn ) );
    }
    
    /// Returns null if no notifies was received
    immutable (notify) getNextNotify()
    {
        consumeInput();
        auto n = PQnotifies(conn);
        return n is null ? null : new notify( n );
    }
    
    private struct preparedArgs
    {
        Oid[] types;
        size_t[] formats;
        size_t[] lengths;
        const(ubyte)*[] values;
    }
    
    // For PQxxxParams need especially prepared arguments
    private preparedArgs* prepareArgs(ref const queryParams p)
    {
        preparedArgs* a = new preparedArgs;
        a.types = new Oid[p.args.length];
        a.formats = new size_t[p.args.length];
        a.lengths = new size_t[p.args.length];
        a.values = new const(ubyte)*[p.args.length];
        
        for( int i = 0; i < p.args.length; ++i )
        {
            a.types[i] = p.args[i].type;
            a.formats[i] = p.args[i].queryFormat;  
            a.values[i] = p.args[i].valueBin.ptr;
            
            final switch( p.args[i].queryFormat )
            {
                case valueFormat.TEXT:
                    a.lengths[i] = p.args[i].valueStr.length;
                    break;
                case valueFormat.BINARY:
                    a.lengths[i] = p.args[i].valueBin.length;
                    break;
            }
        }
        return a;
    }
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    string sql_query =
    "select now() as time, 'abc'::text as string, 123, 456.78\n"
    "union all\n"
    "select now(), 'def'::text, 456, 910.11\n"
    "union all\n"
    "select NULL, 'ijk'::text, 789, 12345.115345";

    auto r = conn.exec( sql_query );
    
    string sql_query2 =
    "select * from (\n"
    ~ sql_query ~
    ") t\n"
    "where string = $1";
    
    static queryArg arg = { valueStr: "def" };
    queryArg[1] args;
    args[0] = arg;
    queryParams p;
    p.sqlCommand = sql_query2;
    p.args = args;

    auto r2 = conn.exec( p );
}
