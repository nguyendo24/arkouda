
module MultiTypeSymbolTable
{
    use ServerConfig;
    use ServerErrorStrings;
    use Reflection;
    use Errors;
    
    use MultiTypeSymEntry;
    use Map;

    /* symbol table */
    class SymTab
    {
        /*
        Associative domain of strings
        */
        var registry: domain(string);

        /*
        Map indexed by strings
        */
        var tab: map(string, shared GenSymEntry);

        var nid = 0;
        /*
        Gives out symbol names.
        */
        proc nextName():string {
            nid += 1;
            return "id_"+ nid:string;
        }

        proc regName(name: string, userDefinedName: string) throws {

            // check to see if name is defined
            if (!tab.contains(name)) {
                if (v) {writeln("regName: undefined symbol ",name);try! stdout.flush();}
                throw getErrorWithContext(
                                   msg=unknownSymbolError("regName", name),
                                   lineNumber=getLineNumber(),
                                   routineName=getRoutineName(),
                                   moduleName=getModuleName(),
                                   errorClass="ErrorWithContext");
            }

            // check to see if userDefinedName is defined
            if (registry.contains(userDefinedName))
            {
                if (v) {writeln("regName: redefined symbol ",userDefinedName);try! stdout.flush();}
            }
            
            registry += userDefinedName; // add user defined name to registry
            tab.addOrSet(userDefinedName, tab.getValue(name)); // point at same shared table entry
        }

        proc unregName(name: string) throws {
            
            // check to see if name is defined
            if (!registry.contains(name) || !tab.contains(name))  {
                if (v) {writeln("unregName: undefined symbol ",name);try! stdout.flush();}
                throw getErrorWithContext(
                                   msg=unknownSymbolError("regName", name),
                                   lineNumber=getLineNumber(),
                                   routineName=getRoutineName(),
                                   moduleName=getModuleName(),
                                   errorClass="ErrorWithContext");
            }
            tab.remove(name); // clear out entry for name
            registry -= name; // take name out of registry
        }
        
        // is it an error to redefine an entry? ... probably not
        // this addEntry takes stuff to create a new SymEntry

        /*
        Takes args and creates a new SymEntry.

        :arg name: name of the array
        :type name: string

        :arg len: length of array
        :type len: int

        :arg t: type of array

        :returns: borrow of newly created `SymEntry(t)`
        */
        proc addEntry(name: string, len: int, type t): borrowed SymEntry(t) throws {
            // check and throw if memory limit would be exceeded
            if t == bool {overMemLimit(len);} else {overMemLimit(len*numBytes(t));}
            
            var entry = new shared SymEntry(len, t);
            if (tab.contains(name)) {
                if (v) {writeln("redefined symbol ",name);try! stdout.flush();}
            }

            tab.addOrSet(name, entry);
            return tab.getBorrowed(name).toSymEntry(t);
        }

        /*
        Takes an already created GenSymEntry and creates a new SymEntry.

        :arg name: name of the array
        :type name: string

        :arg entry: Generic Sym Entry to convert
        :type entry: GenSymEntry

        :returns: borrow of newly created GenSymEntry
        */
        proc addEntry(name: string, in entry: shared GenSymEntry): borrowed GenSymEntry throws {
            // check and throw if memory limit would be exceeded
            overMemLimit(entry.size*entry.itemsize);

            if (tab.contains(name)) {
                if (v) {writeln("redefined symbol ",name);try! stdout.flush();}
            }

            tab.addOrSet(name, entry);
            return tab.getBorrowed(name);
        }

        /*
        Creates a symEntry from array name, length, and DType

        :arg name: name of the array
        :type name: string

        :arg len: length of array
        :type len: int

        :arg dtype: type of array

        :returns: borrow of newly created GenSymEntry
        */
        proc addEntry(name: string, len: int, dtype: DType): borrowed GenSymEntry throws {
            select dtype {
                when DType.Int64 { return addEntry(name, len, int); }
                when DType.Float64 { return addEntry(name, len, real); }
                when DType.Bool { return addEntry(name, len, bool); }
                otherwise { 
                    var errorMsg = "addEntry not implemented for %t".format(dtype); 
                    throw getErrorWithContext(
                                   msg=errorMsg,
                                   lineNumber=getLineNumber(),
                                   routineName=getRoutineName(),
                                   moduleName=getModuleName(),
                                   errorClass="ErrorWithContext");
                }
            }
        }

        /*
        Removes an unregistered entry from the symTable

        :arg name: name of the array
        :type name: string
        */
        proc deleteEntry(name: string) {
            if (tab.contains(name) && !registry.contains(name)) {
                tab.remove(name);
            }
            else {
                if (v) {writeln("deleteEntry: unkown symbol ",name);try! stdout.flush();}
            }
        }

        /*
        Clears all unregistered entries from the symTable
        */
        proc clear() {
            for n in tab.keysToArray() { deleteEntry(n); }
        }

        
        /*
        Returns the sym entry associated with the provided name, if the sym entry exists

        :arg name: string to index/query in the sym table
        :type name: string

        :returns: sym entry or throws on error
        :throws: `unkownSymbolError(name)`
        */
        proc lookup(name: string): borrowed GenSymEntry throws {
            if (!tab.contains(name))
            {
                if (v) {writeln("undefined symbol ",name);try! stdout.flush();}
                throw getErrorWithContext(
                                   msg=unknownSymbolError("", name),
                                   lineNumber=getLineNumber(),
                                   routineName=getRoutineName(),
                                   moduleName=getModuleName(),
                                   errorClass="ErrorWithContext");
            } else {
                return tab.getBorrowed(name);
            }
        }

        /*
        Prints the SymTable in a pretty format (name,SymTable[name])
        */
        proc pretty() throws {
            for n in tab {
                writeln("%10s = ".format(n), tab.getValue(n));try! stdout.flush();
            }
        }

        /*
        returns total bytes in arrays in the symbol table
        */
        proc memUsed(): int {
            var total: int = + reduce [e in tab.values()] e.size * e.itemsize;
            return total;
        }
        
        /*
        Attempts to format and return sym entries mapped to the provided string into JSON format.
        Pass __AllSymbols__ to process the entire sym table.

        :arg name: name of entry to be processed
        :type name: string
        */
        proc dump(name:string): string throws {
            if name == "__AllSymbols__" {return try! "%jt".format(this);}
            else if (tab.contains(name)) {return try! "%jt %jt".format(name, tab.getReference(name));}
            else {
                var errorMsg = "Error: dump: undefined name: %s".format(name);
                writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="IncompatibleArgumentsError"));                 
                return errorMsg;
            }
        }
        
        /*
        Returns verbose attributes of the sym entry at the given string, if the string maps to an entry.
        Pass __AllSymbols__ to process all sym entries in the sym table.

        Returns: name, dtype, size, ndim, shape, and item size

        :arg name: name of entry to be processed
        :type name: string

        :returns: s (string) containing info
        */
        proc info(name:string): string {
            var s: string;
            if name == "__AllSymbols__" {
                for n in tab {
                    try! s += "name:%t dtype:%t size:%t ndim:%t shape:%t itemsize:%t\n".format(n, 
                              dtype2str(tab.getBorrowed(n).dtype), tab.getBorrowed(n).size, 
                              tab.getBorrowed(n).ndim, tab.getBorrowed(n).shape, 
                              tab.getBorrowed(n).itemsize);
                }
            }
            else
            {
                if (tab.contains(name)) {
                    try! s = "name:%t dtype:%t size:%t ndim:%t shape:%t itemsize:%t\n".format(name, 
                              dtype2str(tab.getBorrowed(name).dtype), tab.getBorrowed(name).size, 
                              tab.getBorrowed(name).ndim, tab.getBorrowed(name).shape, 
                              tab.getBorrowed(name).itemsize);
                }
                else {
                    s = unknownSymbolError("info",name);
                    writeln(generateErrorContext(
                                     msg=s, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="UnknownSymbolError"));                    
                }
            }
            return s;
        }

        /*
        Returns raw attributes of the sym entry at the given string, if the string maps to an entry.
        Returns: name, dtype, size, ndim, shape, and item size

        :arg name: name of entry to be processed
        :type name: string

        :returns: s (string) containing info
        */
        proc attrib(name:string):string {
            var s:string;
            if (tab.contains(name)) {
                try! s = "%s %s %t %t %t %t".format(name, dtype2str(tab.getBorrowed(name).dtype), 
                          tab.getBorrowed(name).size, tab.getBorrowed(name).ndim, 
                          tab.getBorrowed(name).shape, tab.getBorrowed(name).itemsize);
            }
            else {
                s = unknownSymbolError("attrib",name);
                writeln(generateErrorContext(
                                     msg=s, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="IncompatibleArgumentsError"));                 
            }
            return s;
        }

        /*
        Attempts to find a sym entry mapped to the provided string, then 
        returns the data in the entry up to the specified threshold.
        Arrays of size less than threshold will be printed in their entirety. 
        Arrays of size greater than or equal to threshold will print the first 3 and last 3 elements

        :arg name: name of entry to be processed
        :type name: string

        :arg thresh: threshold for data to return
        :type thresh: int

        :returns: s (string) containing the array data
        */
        proc datastr(name: string, thresh:int): string {
            var s:string;
            if (tab.contains(name)) {
                var u: borrowed GenSymEntry = tab.getBorrowed(name);
                select u.dtype
                {
                    when DType.Int64
                    {
                        var e = toSymEntry(u,int);
                        if e.size == 0 {s =  "[]";}
                        else if e.size < thresh || e.size <= 6 {
                            s =  "[";
                            for i in 0..(e.size-2) {s += try! "%t ".format(e.a[i]);}
                            s += try! "%t]".format(e.a[e.size-1]);
                        }
                        else {
                            s = try! "[%t %t %t ... %t %t %t]".format(e.a[0],e.a[1],e.a[2],
                                                                      e.a[e.size-3],
                                                                      e.a[e.size-2],
                                                                      e.a[e.size-1]);
                        }
                    }
                    when DType.Float64
                    {
                        var e = toSymEntry(u,real);
                        if e.size == 0 {s =  "[]";}
                        else if e.size < thresh || e.size <= 6 {
                            s =  "[";
                            for i in 0..(e.size-2) {s += try! "%t ".format(e.a[i]);}
                            s += try! "%t]".format(e.a[e.size-1]);
                        }
                        else {
                            s = try! "[%t %t %t ... %t %t %t]".format(e.a[0],e.a[1],e.a[2],
                                                                      e.a[e.size-3],
                                                                      e.a[e.size-2],
                                                                      e.a[e.size-1]);
                        }
                    }
                    when DType.Bool
                    {
                        var e = toSymEntry(u,bool);
                        if e.size == 0 {s =  "[]";}
                        else if e.size < thresh || e.size <= 6 {
                            s =  "[";
                            for i in 0..(e.size-2) {s += try! "%t ".format(e.a[i]);}
                            s += try! "%t]".format(e.a[e.size-1]);
                        }
                        else {
                            s = try! "[%t %t %t ... %t %t %t]".format(e.a[0],e.a[1],e.a[2],
                                                                      e.a[e.size-3],
                                                                      e.a[e.size-2],
                                                                      e.a[e.size-1]);
                        }
                        s = s.replace("true","True");
                        s = s.replace("false","False");
                    }
                    otherwise {
                        s = unrecognizedTypeError("datastr",dtype2str(u.dtype));
                        writeln(generateErrorContext(
                                     msg=s, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="IncompatibleArgumentsError"));                         
                        }
                }
            }
            else {
                s = unknownSymbolError("datastr",name);
                writeln(generateErrorContext(
                                     msg=s, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="IncompatibleArgumentsError"));                 
            }
            return s;
        }
        /*
        Attempts to find a sym entry mapped to the provided string, then 
        returns the data in the entry up to the specified threshold. 
        This method returns the data in form "array([<DATA>])".
        Arrays of size less than threshold will be printed in their entirety. 
        Arrays of size greater than or equal to threshold will print the first 3 and last 3 elements

        :arg name: name of entry to be processed
        :type name: string

        :arg thresh: threshold for data to return
        :type thresh: int

        :returns: s (string) containing the array data
        */
        proc datarepr(name: string, thresh:int): string {
            var s:string;
            if (tab.contains(name)) {
                var u: borrowed GenSymEntry = tab.getBorrowed(name);
                select u.dtype
                {
                    when DType.Int64
                    {
                        var e = toSymEntry(u,int);
                        if e.size == 0 {s =  "array([])";}
                        else if e.size < thresh || e.size <= 6 {
                            s =  "array([";
                            for i in 0..(e.size-2) {s += try! "%t, ".format(e.a[i]);}
                            s += try! "%t])".format(e.a[e.size-1]);
                        }
                        else {
                            s = try! "array([%t, %t, %t, ..., %t, %t, %t])".format(e.a[0],e.a[1],e.a[2],
                                                                                    e.a[e.size-3],
                                                                                    e.a[e.size-2],
                                                                                    e.a[e.size-1]);
                        }
                    }
                    when DType.Float64
                    {
                        var e = toSymEntry(u,real);
                        if e.size == 0 {s =  "array([])";}
                        else if e.size < thresh || e.size <= 6 {
                            s =  "array([";
                            for i in 0..(e.size-2) {s += try! "%.17r, ".format(e.a[i]);}
                            s += try! "%.17r])".format(e.a[e.size-1]);
                        }
                        else {
                            s = try! "array([%.17r, %.17r, %.17r, ..., %.17r, %.17r, %.17r])".format(e.a[0],e.a[1],e.a[2],
                                                                                    e.a[e.size-3],
                                                                                    e.a[e.size-2],
                                                                                    e.a[e.size-1]);
                        }
                    }
                    when DType.Bool
                    {
                        var e = toSymEntry(u,bool);
                        if e.size == 0 {s =  "array([])";}
                        else if e.size < thresh || e.size <= 6 {
                            s =  "array([";
                            for i in 0..(e.size-2) {s += try! "%t, ".format(e.a[i]);}
                            s += try! "%t])".format(e.a[e.size-1]);
                        }
                        else {
                            s = try! "array([%t, %t, %t, ..., %t, %t, %t])".format(e.a[0],e.a[1],e.a[2],
                                                                                    e.a[e.size-3],
                                                                                    e.a[e.size-2],
                                                                                    e.a[e.size-1]);
                        }
                        s = s.replace("true","True");
                        s = s.replace("false","False");
                    }
                    otherwise {
                        s = unrecognizedTypeError("datarepr",dtype2str(u.dtype));
                        writeln(generateErrorContext(
                                     msg=s, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="UnrecognizedTypeError"));                         
                    }
                }
            }
            else {
                s = unknownSymbolError("datarepr",name);
                writeln(generateErrorContext(
                                     msg=s, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="UnknownSymbolError"));                 
            }
            return s;
        }
    }      
}

