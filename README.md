# line_editor

Just a simple line editor.
Here is the help text:
```
Welcome to the simple line editor.
    You are currently on line 1, out of 0 lines total.

  Internal Memory:
MODE                     COMMAND or EDIT (swap using .)
LINE                     the current line number
FILE                     the current output file name

  Basic Types:
NUMBER                   any sequence of base-10 digits
STRING                   any sequence of bytes
REGEX                    / deliminated regular expression
INDEX:
    NUMBER               line NUMBER
    $                    the last line
RANGE:
    INDEX                the range spanning [INDEX, INDEX]
    INDEX,               the range spanning [INDEX, the last line]
    ,INDEX               the range spanning [0, INDEX]
    A,B                  the range spanning [A (INDEX), B (INDEX)]

Commands (for EDIT MODE):
    .                    MODE <- COMMAND
    [STRING]             inserts STRING at LINE, LINE <- LINE + 1

Commands (for COMMAND MODE):
    d                    deletes 1 line at LINE
    [RANGE]d             deletes all lines in RANGE
    .                    MODE <- EDIT
    [INDEX].             LINE <- INDEX, MODE <- EDIT
    .[STRING]            inserts STRING at LINE
    [INDEX].[STRING]     LINE <- INDEX, inserts STRING at LINE
    [INDEX]              LINE <- INDEX
    p                    prints 16 lines at LINE
    [RANGE]p             prints all lines in RANGE
    s/[OLD]/[NEW]        replaces all OLD (REGEX) for NEW on LINE
    [RANGE]s/[OLD]/[NEW] replaces all OLD (REGEX) for NEW in RANGE
    w                    saves all lines to FILE
    [RANGE]w             saves all lines in RANGE to FILE
    w [NAME]             FILE <- NAME, saves all lines to FILE
    [RANGE]w [NAME]      FILE <- NAME, saves all lines in RANGE to FILE
    wq                   saves all lines to FILE, exits
    [RANGE]wq            saves all lines in RANGE to FILE, exits
    wq [NAME]            FILE <- NAME, saves all lines to FILE, exits
    [RANGE]wq [NAME]     FILE <- NAME, saves all lines in RANGE to FILE, exits
    q                    exits
    h                    displays this text
```
