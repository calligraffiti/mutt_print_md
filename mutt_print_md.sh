#!/bin/bash

# Prints to a Markdown file from Mutt.
# (An alternative to muttprint.)

# Needs for $1 a filename without
# an extension; the output consists
# of two files, being:
# - $1.md
# - $1.pdf

# Add to your .muttrc something like:
# set print_command='set -e; f=`mktemp --tmpdir="$HOME" mutt_XXXXX`; /home/evert/bin/mutt_print_md.sh "$f"'

# An alternative is muttprint, which has way more options and looks more interesting.
# However I wanted Markdown formatted output and Pandoc integration;
# also I wanted the xelatex engine for better font handling.
# The original muttprint source could be modified, but I'm no Perl programmer,
# and muttprint makes lots of assumptions about old latex conventions.

# Evert Mouw <post@evert.net>
# 2019-01-17 first version
# 2019-01-18 various improvements

# This file is utf-8 encoded and contains unicode color emoji.

# TODO: enhance printing of html mails and attachments
#
# Possible improvement: also html-mail printing, maybe attachment printing
# In muttrc, enable:
#   set print_decode = 'no';
# And pipe the mutt output (print_command) to a smarter application.
# Possible candidates are:
# 
# cedilla
# good unicode support, but can it print email?
# https://www.irif.fr/~jch/software/cedilla/
# http://www.linuxcertif.com/man/1/cedilla/
#
# case for cedilla, against enscript
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=229595
#
# enscript
# lacks utf-8 support, bad!
# https://www.gnu.org/software/enscript/
# example:
# enscript --font=Courier8 $INPUT -2r --word-wrap --fancy-header=mutt -p - 2>/dev/null 
# https://unix.stackexchange.com/questions/324630/how-do-i-process-text-before-i-hand-it-over-to-enscript-or-how-do-i-print-utf8/324640
# another example:
# set print_command="enscript --word-wrap --margins=::: -f 'Times-Roman11' -F 'TimesRoman14' --fancy-header='enscript' -i3"
# https://mutt-users.mutt.narkive.com/ipm6bmoW/printing-messages-setting-fontsize
#
# mhonarc
# https://www.mhonarc.org/
# http://www.mhonarc.org/MHonArc/doc/rcfileexs/utf-8-encode.mrc.html
# example:
# https://linuxgazette.net/182/brownss.html
# Output Geometry -- Changed from "a4paper,margin=1in" to letterpaper

# ------
# settings you can modify
# refer to pandoc website
FONT="DejaVu Sans"
FONTSIZE=9
GEOMETRY="letterpaper,margin=1in"

# ------
# don't mess below here

# clear screen so while in mutt and printing,
# you don't see old status info or garbage
clear
echo ""
echo "$0 active..."
echo "Exporting ('printing') to markdown and pdf!"
echo ""
echo "Creating the pdf from markdown takes awhile ⏳"
echo ""
echo ""

OUTFILE="$1"

if [[ $OUTFILE == "" ]]
then
	# show error
	clear
	echo ""
	echo "ERROR ⚠️"
	echo ""
	echo "I need one argument, a filename (without extension)."
	echo "This script is used to print emails from whithin Mutt."
	echo ""
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
	printline "geometry: \"$GEOMETRY\""
	printline "---"
	printline ""
}

# create PDF metadata
function pdfmeta {
	PDFDATE=$(date --utc --date="$DATE" "+%Y%m%d%H%M%S")
	PDFDATE="${PDFDATE}+00'00'"
	MODDATE=$(date --utc "+%Y%m%d%H%M%S")
	MODDATE="${MODDATE}+00'00'"
	printline "
\hypersetup{
  pdfinfo={
   Title={Email pdf export},
   Author={$FROM},
   Subject={$SUBJECT},
   Keywords={mutt, mutt_print_md, email, markdown, pandoc},
   CreationDate={D:${PDFDATE}},
   ModDate={D:${MODDATE}}
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

# better filenames, including Date / Subject / From
# note: this uses GNU date and localhost timezone
ISODATE=$(date --date="$DATE" "+%Y-%m-%dT%H%M")
SUBWRD1=$(echo "$SUBJECT" | egrep -o '[a-zA-Z0-9]+' | head -n1)
SUBWRD2=$(echo "$SUBJECT" | egrep -o '[a-zA-Z0-9]+' | head -n2)
USERID1=$(echo "$FROM"    | egrep -o '[a-zA-Z0-9]+' | head -n1)
DESCRIP="${ISODATE} ${SUBWRD1}_${SUBWRD2} ${USERID1}"
DESCRIP=${DESCRIP//[$'\n']} # remove newlines
DIR=$(dirname "$OUTFILE")
BASE=$(basename "$OUTFILE")
FILEPATH1="${DIR}/${DESCRIP} ${BASE}"
MD_FILE="${FILEPATH1}.md"
PDFFILE="${FILEPATH1}.pdf"

# copy the file to a markdown file
cp "$OUTFILE" "$MD_FILE"

# use pandoc for pdf creation
PANDOCOPTIONS="-f markdown -t latex --pdf-engine xelatex"
pandoc ${PANDOCOPTIONS} "$MD_FILE" -o "$PDFFILE"
if [[ $? -gt 0 ]]
then
	echo "ERROR: pandoc failed...⚠️ "
	echo ""
	echo "(waiting 6 sec)"
	sleep 6
	exit 1
fi

# clean up
rm "$OUTFILE"

# show results
echo "

Mail exported to files 📨


- $MD_FILE

- $PDFFILE


"
# at this point, mutt asks to press a key to return to mutt...
# end of script
