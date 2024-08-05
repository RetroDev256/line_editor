# line_editor

Just a simple line editor.
Here is the help text:

```
- - - Definitions - - -
  MODE                  COMMAND or INSERT (swap using .)
  LINE                  the current line number
  FILE                  the current output file name
  INDEX                 can be line number, or $ (last line)
  RANGE:                (can be either of the following formats -)
  [X]                   line number X (INDEX)
  [A?],[B?]             lines [INDEX A (orelse 0), INDEX B (orelse $)]
- - - INSERT Mode - - -
  .                     MODE <- COMMAND
  .[STRING]             inserts STRING at LINE, LINE <- LINE + 1
- - - COMMAND Mode - - -
  [INDEX?]              LINE <- INDEX (else LINE)
  [INDEX?].             LINE <- INDEX (else LINE), MODE <- INSERT
  [INDEX?].[NEW]        LINE <- INDEX (else LINE), inserts NEW at LINE
  [RANGE?]p             prints RANGE (else LINE)
  [RANGE?]d             deletes RANGE (else LINE)
  [RANGE?]s/[OLD]/[NEW] replaces all OLD to NEW in RANGE (else LINE)
  [RANGE?]m[INDEX]      moves RANGE (else LINE) to INDEX
  [RANGE?]w[NAME?]      FILE <- NAME (else FILE), saves RANGE (else all lines) to FILE
  [RANGE?]wq[NAME?]     same as w varient, but also quits the program
  q                     exits
  h                     displays this text
```
