# mutt_print_md

Prints to a Markdown file from Mutt.

(An alternative to muttprint.)

Needs for $1 a filename without an extension; the output consists of two files, being:

- $1.md
- $1.pdf

Add to your .muttrc something like:

```
set print_command='set -e; f=`mktemp --tmpdir="$HOME" mutt_XXXXX`; /home/evert/bin/mutt_print_md.sh "$f"'
```

An alternative is muttprint, which has way more options and looks more interesting.
However I wanted Markdown formatted output and Pandoc integration;
also I wanted the xelatex engine for better font handling.
The original muttprint source could be modified, but I'm no Perl programmer,
and muttprint makes lots of assumptions about old latex conventions.

Cheers, Evert
