#!/bin/bash

# Prints to a Markdown file from Mutt.
# (An alternative to muttprint.)

# Needs for $1 a filename without
# an extension; the output consists
# of two files, being:
# - $1.md
# - $1.pdf

# Add to your .muttrc something like:
# set print_command='set -e; f=`mktemp --tmpdir="$HOME" muttprint_XXXXXX`; /home/evert/bin/mutt_print_md.sh "$f"; clear; echo -e "\n\n\n\t📨 printed to files:\n\n\n\t- $f.md\n\n\t- $f.pdf\n\n"'

# An alternative is muttprint, which has way more options and looks more interesting.
# However I wanted Markdown formatted output and Pandoc integration;
# also I wanted the xelatex engine for better font handling.
# The original muttprint source could be modified, but I'm no Perl programmer,
# and muttprint makes lots of assumptions about old latex conventions.

# Evert Mouw <post@evert.net>
# 2019-01-17 first version

# ------
# settings you can modify
FONT="DejaVu Sans"
FONTSIZE=12

# ------
# don't mess below here

OUTFILE="$1"

if [[ $OUTFILE == "" ]]
then
	echo "I need one argument, a filename (without extension)."
	echo "This script is used to print emails from whithin Mutt."
	exit 1
fi

function printline {
	LINE="$@"
	# insert an empty line if we are going into quote mode ( > blah )
	# and the current line is not empty and not a quote line
	# furthermore i want to preserve line breaks in quoted tekst
	if [[ $PREVIOUSLINE != "" ]]
	then
		if echo "$LINE" | egrep -q "^>.*"
		then
			if ! echo "$PREVIOUSLINE" | egrep -q "^>.*"
			then
				echo "" >> "$OUTFILE"
			fi
			echo "$LINE \\" >> "$OUTFILE"
			return
		fi
	fi
	# be nice for "signatures" marked with a double dash --
	if [[ "$LINE" == "--" ]]
	then
		echo "" >> "$OUTFILE"
		echo "$LINE" >> "$OUTFILE"
		echo "" >> "$OUTFILE"
		return
	fi
	# the pandox/latex processor removes vertical space
	# and i want it back
	if [[ $PREVIOUSLINE == "" && $LINE == "" ]]
	then
		echo '` `' >> "$OUTFILE"
		echo "" >> "$OUTFILE"
		return
	fi
	# and for all other cases, plainly
	echo "$LINE" >> "$OUTFILE"
}

function mailaddressmarkup {
	# markdown mangles the name <mail> syntax:
	#   Horse <horse@earth.net> -->  Horse horse@earth.net
	# but I don't like to write in source: <<horse@earth.net>>
	IN="$@"
	IN="${IN/</<<}"
	IN="${IN/>/>>}"
	echo "$IN"
}

function headerline {
	line="$@"
	# remove all double quotes (especially for the names)
	line=${line//\"/}
	if echo "$line" | grep -q "^Date";    then    DATE=${line#'Date: '};    LAST='d'; fi
	if echo "$line" | grep -q "^From";    then    FROM=${line#'From: '};    LAST='f'; fi
	if echo "$line" | grep -q "^To";      then      TO=${line#'To: '};      LAST='t'; fi
	if echo "$line" | grep -q "^Cc";      then      CC=${line#'Cc: '};      LAST='c'; fi
	if echo "$line" | grep -q "^Subject"; then SUBJECT=${line#'Subject: '}; LAST='s'; fi
	## detecting a continuation
	if ! echo "$line" | egrep -q "^.+:"
	then
		case $LAST in
			d)    DATE="$DATE$line"    ;;
			f)    FROM="$FROM$line"    ;;
			t)      TO="$TO$line"      ;;
			c)      CC="$CC$line"      ;;
			s) SUBJECT="$SUBJECT$line" ;;
			*)
				echo "Unknown value for LAST; ERROR"
				exit 1
				;;
		esac
	fi
}

function explodenames {
	# if there are multiple receipients,
	# split the names on the comma and
	# kudo's to Peter Mortensen
	# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash
	IFS=',' read -ra names <<< "$@"
	for name in "${names[@]}"
	do
		# replace Name<mail> by Name <mail> (add space in between)
		# results in double spaces, but is hard in bash to do correctly...
		name=${name//</\ <}
		# reduces double space to single space
		name=${name//\ \ /\ }
		# remove leading spaces
		# kudo's to Chris F.A. Johnson
		name="${name#"${name%%[![:space:]]*}"}"
		namefull=$(mailaddressmarkup "$name")
		echo "- $namefull"
	done
}

function printheaders {
	printline "# ✉ $SUBJECT"
	printline ""

	printline "*From*: $FROM \\"
	printline "*Date*: $DATE \\"

	if echo "$TO" | grep -q ','
	then
		printline "*To* multiple receipients:"
		printline ""
		printline "$(explodenames "$TO")"
		printline ""
	else
		namefull=$(mailaddressmarkup "$TO")
		printline "*To*: $namefull \\"
	fi

	if echo "$CC" | grep -q ','
	then
		printline "*Carbon copied*:"
		printline ""
		printline "$(explodenames "$CC")"
		printline ""
	else
		if [[ $CC != "" ]]
		then
			namefull=$(mailaddressmarkup "$CC")
			printline "*Cc*: $namefull \\"
		fi
	fi

	printline ""
	printline "---"
	printline ""
}

# create YAML header
function yamlheader {
	printline "---"
	printline "mainfont: $FONT"
	printline "fontsize: $FONTSIZE"
	printline 'geometry: "a4paper,margin=1in"'
	printline "---"
	printline ""
}

# create PDF metadata
function pdfmeta {
	printline "
\hypersetup{
  pdfinfo={
   Title={Email},
   Author={$FROM},
   Subject={$SUBJECT},
  }
}
"
}

i=0
HEADERS=1
while read line
do
	# as long as we are in the header section,
	# we will be selective...

	# the very first line emitted by mutt is sometimes empty
	if [[ i -eq 0 && $line == "" ]]
	then
		break
	fi

	# the first empty line ends the headings
	if [[ $line == "" && $HEADERS == 1 ]]
	then
		yamlheader
		pdfmeta
		printheaders
		HEADERS=0
	fi

	if [[ $HEADERS == 0 ]]
	then
		printline "$line"
	else
		headerline "$line"
	fi
	PREVIOUSLINE="$line"
	((i++))
done

# copy the file to a markdown file
MDFILE="$OUTFILE.md"
cp "$OUTFILE" "$MDFILE"

# use pandoc for pdf creation
PDFFILE="$OUTFILE.pdf"
PANDOCOPTIONS="--pdf-engine xelatex"
pandoc -f markdown -t latex ${PANDOCOPTIONS} "$MDFILE" -o "$PDFFILE"

# clean up
rm "$OUTFILE"

