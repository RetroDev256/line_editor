// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser) !Command {
    if (parser.starting_index != null) return error.MalformedCommand;
    if (parser.has_range_seperator) return error.MalformedCommand;
    if (parser.ending_index != null) return error.MalformedCommand;
    return .help;
}

// Runner impl

const Runner = @import("../Runner.zig");

pub fn run(self: *Runner) !void {
    try self.printToCmdOut(
        \\- - - Definitions - - -
        \\  MODE                  COMMAND or INSERT (swap using .)
        \\  LINE                  the current line number
        \\  FILE                  the current output file name
        \\  INDEX                 can be line number, or $ (last line)
        \\  RANGE:                (can be either of the following formats -)
        \\  [X]                   line number X (INDEX)
        \\  [A?],[B?]             lines [INDEX A (oror 0), INDEX B (oror $)]
        \\- - - INSERT Mode - - -
        \\  .                     MODE<-COMMAND
        \\  .[STRING]             inserts STRING at LINE, LINE<-LINE + 1
        \\- - - COMMAND Mode - - -
        \\  [INDEX?]              LINE<-INDEX (or LINE)
        \\  [INDEX?].             LINE<-INDEX (or LINE), MODE<-INSERT
        \\  [INDEX?].[NEW]        LINE<-INDEX (or LINE), inserts NEW at LINE
        \\  [RANGE?]p             prints RANGE (or LINE)
        \\  [RANGE?]d             deletes RANGE (or LINE)
        \\  [RANGE?]s/[OLD]/[NEW] replaces all OLD to NEW in RANGE (or LINE)
        \\  [RANGE?]m[INDEX]      moves RANGE (or LINE) to INDEX
        \\  [RANGE?]w[NAME?]      FILE<-NAME (or FILE), saves RANGE (or all) to FILE
        \\  [RANGE?]wq[NAME?]     same as w varient, but also quits the program
        \\  q                     exits
        \\  h                     displays this text
        \\
    , .{});
}
