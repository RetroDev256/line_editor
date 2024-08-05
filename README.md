# line_editor

Just a simple line editor.
Here is the help text:
```
You are on line 1 of 0.
- - - Meanings - - -
  MODE                  COMMAND or EDIT (swap using .)
  LINE                  the current line number
  FILE                  the current output file name
  INDEX                 can be line number, $ (last line)
  RANGE:                (can be either of the following formats -)
  [X]                   line number X (INDEX)
  [A?],[B?]             lines [INDEX A (orelse 0), INDEX B (orelse $)]
- - - EDIT Mode - - -
  .                     MODE <- COMMAND
  [STRING]              inserts STRING at LINE, LINE <- LINE + 1
- - - COMMAND Mode - - -
  [INDEX]               LINE <- INDEX
  [RANGE]p              LINE <- RANGE.END, prints RANGE
  [INDEX].              LINE <- INDEX, MODE <- EDIT
  [INDEX].[NEW]         LINE <- INDEX, inserts NEW at LINE
  [RANGE]d              LINE <- RANGE.START, deletes RANGE
  [RANGE]s/[OLD]/[NEW]  LINE <- RANGE.START, OLD -> NEW in RANGE
  [RANGE]m[INDEX]       LINE <- INDEX, moves RANGE to INDEX
  [RANGE]w [NAME?]      FILE <- NAME (else FILE), saves RANGE to FILE
  [RANGE]wq [NAME?]     same as w varient, but also quits the program
  q                     exits
  h                     displays this text
```
