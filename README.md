# line_editor
I created a simple line editor in Zig to practice programming. It features two modes: command mode and edit mode.

In command mode, the following commands are available:

    q (quit)
    d (delete)
    p (print)
    w (write)
    wq (write and quit)
    . (insert)
    s (substitution)
    [any number] (set current line)

Commands like delete, print, write, write and quit, and substitution can all be prefixed by a range. Write and 'write and quit' commands can also include a filename after them.

The insert command (.) has two modes:

    [line number]. drops you into edit mode on that line number
    [line number].sometext inserts text into the current line without entering edit mode.

The line number can be omitted.

Usage: PROGRAM FILE_IN -o FILE_OUT -s SCRIPT_IN

You can even create scripts to operate on files with this editor.

A range consists of one or two numbers defining where an action will occur. The format is NUMBER,NUMBER, where each number can be replaced by $ to signify the end of the file.

For substitution, the format is similar to ED:
`[range]s/regex_pattern/replacement_text/count`. The count is optional. It can be replaced by $ or omitted to mean all matches on each line in the range.
