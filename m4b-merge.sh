#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.
## REQUIRES: mutagen, pv, https://github.com/sandreas/m4b-tool
VER=1.3.0

#LOCAL FOLDERS
OUTPUT=""

# Command for m4b-tool, can be full path or just alias/command.
M4BPATH=""

# Path to cookies file for audible
AUDCOOKIES="/tmp/aud-cookies.txt"

# Override job count. Default uses number of CPU threads,
JOBCOUNT="$(grep -c ^processor /proc/cpuinfo)"

# If anything isn't set, assume defaults
if [[ -z $M4BPATH ]]; then
	M4BPATH="$(which m4b-tool)"
fi
# Check if there's no /output folder from docker
if [[ ! -d /output ]]; then
	# Check if output env var is empty
	if [[ -z $OUTPUT ]]; then
		error "Output is not set. Exiting."
		exit 1
	fi
else
	OUTPUT="/output"
fi

# -h help text to print
usage="	$(basename "$0") $VER [-a] [-b] [-f] [-h] [-v] [-y]

	'-a' Be prompted for Audible ASINs instead of manually entering metadata (BETA)
	'-b' Batch mode. File input is used for 1 folder only.
	'-f' File or folder to run from. Enter multiple files if you need, as: -f file1 -f file2 -f file3
	'-h' This help text.
	'-v' Verbose mode.
	'-y' Answer 'yes' to all prompts.
	"

# Flags for this script
	while getopts ":abf:hvy" option; do
 case "${option}" in
	a) AUDIBLEMETA=true
		;;
	b) BATCHMODE=true
		;;
	f) FILEIN+=("$(realpath "$OPTARG")")
		;;
	h) echo "$usage"
 		exit
		;;
	v) VERBOSE=true
		;;
	y) YPROMPT=true
		;;
 \?) echo -e "\e[91mInvalid flag: -"$OPTARG". Use '-h' for help.\e[0m" >&2
 	;;
 :) echo -e "\e[91mOption -$OPTARG requires a value.\e[0m" >&2
      exit 1
	;;

 esac
done

### Functions ###

function preprocess() {
	# Let's first check that the input folder, actually should be merged.
	# Import metadata into an array, so we can use it.
	importmetadata
	# Common extensions for audiobooks.
	# Check input for each of the above file types, ensuring we are not dealing with a pre-merged input.
	EXT1="m4a"
	EXT2="mp3"
	EXT3="m4b"
	EXT4="flac"
	EXTARRAY=($EXT1 $EXT2 $EXT3 $EXT4)
	for EXTENSION in ${EXTARRAY[@]}; do
		if [[ $(grep -i -r --include \*.$EXTENSION '*' "$SELDIR" | wc -l) -ge 1 ]]; then
			EXT="$EXTENSION"
		fi
	done

	if [[ -d $SELDIR && -n $EXT ]] || [[ -f $SELDIR && $EXT == "m4b" ]]; then
		# After we verify the input needs to be merged, lets run the merge command.
		pipe "$M4BPATH" merge "$SELDIR" --output-file="$OUTPUT"/"$albumartistvar"/"$albumvar"/"$namevar".m4b "${M4BSEL[@]//$'\n'/}" --force --jobs="$JOBCOUNT"
		color_highlight "Merge completed for $namevar."
	elif [[ -f $SELDIR && $EXT == "mp3" ]]; then
		sfile="true"
		singlefile
	elif [[ -z $EXT ]]; then
		error "No recognized filetypes found for $namevar."
		warn "Skipping..."
	fi
}

function audibleparser() {
	AUDMETAFILE="/tmp/.audmeta.$BASESELDIR.txt"

	if [[ $YPROMPT == "true" && -f $AUDMETAFILE ]]; then
		useoldmeta="y"
	elif [[ -s $AUDMETAFILE ]]; then # Check if we can use existing audible data
		color_highlight "Cached Audible metadata for $BASESELDIR exists"
		read -e -p 'Use existing metadata? y/n: ' useoldmeta
	elif [[ ! -f $AUDMETAFILE ]]; then # Check if we can use an existing metadata entry
		useoldmeta="n"
	fi

	if [[ $useoldmeta == "n" ]]; then
		RET=1
		until [[ $RET -eq 0 ]]; do
			echo ""
			color_action "Enter Audible ASIN for $BASESELDIR"
			read -e -p 'ASIN: ' ASIN

			CHECKASIN="$(curl -o /dev/null -L --silent --head --write-out '%{http_code}\n' https://www.audible.com/pd/$ASIN)"
			RET=$?

			if [[ -z $ASIN ]]; then
				error "No ASIN was entered. Try again."
				RET=1
			elif [[ $CHECKASIN != "200" ]]; then
				error "Could not access ASIN for $BASESELDIR (Was it entered correctly?)"
				RET=1
			elif [[ $CHECKASIN == "200" ]]; then
				RET=0
			fi
		done
	fi
	if [[ ! -s $AUDMETAFILE ]] || [[ -s $AUDMETAFILE && $useoldmeta == "n" ]]; then
		if [[ ! -s $AUDCOOKIES ]]; then
			error "Cookie file missing. This may lead to certain elements not working (like series and book numbering)"
		fi
		color_action "Fetching metadata from Audible..."
		curl -L -H "User-Agent: Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.2; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0)" --cookie $AUDCOOKIES https://www.audible.com/pd/$ASIN -s -o "$AUDMETAFILE"
	fi

	unset useoldmeta

	# Check for multiple narrators
	NARRCMD="$(grep "searchNarrator=" "$AUDMETAFILE" | grep c1_narrator | grep -o -P '(?<=>).*(?=<)' | sort -u | iconv -f utf8 -t ascii//TRANSLIT)"
	if [[ $(echo "$NARRCMD" | wc -l) -gt 1 ]]; then
		notice "Correcting formatting for multiple narrators..."
		NUM="$(echo "$NARRCMD" | wc -l)"
		NARRCMD="$(cat "$AUDMETAFILE" | grep "searchNarrator=" | grep c1_narrator | grep -o -P '(?<=>).*(?=<)' | sort -u | sed -e "2,${NUM}{s#^#, #}" | tr -d '\n' | iconv -f utf8 -t ascii//TRANSLIT)"
	fi
	AUTHORCMD="$(grep "/author/" "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=<)' | head -n1 | iconv -f utf8 -t ascii//TRANSLIT)"
	# Prefer being strict about authors, unless we can't find them.
	if [[ -z $AUTHORCMD ]]; then
		notice "Could not find author using default method. Trying backup method..."
		AUTHORCMD="$(cat "$AUDMETAFILE" | grep "author" | grep -o -P '(?<=>).*(?=<)' | head -n1 | iconv -f utf8 -t ascii//TRANSLIT)"
	fi
	TICTLECMD="$(grep "title"  "$AUDMETAFILE" | grep "content=" -m 1 | head -n1 | grep -o -P '(?<=content=").*(?=")' | sed -e 's/[[:space:]]*$//' | iconv -f utf8 -t ascii//TRANSLIT)"
	SERIESCMD="$(grep "/series" "$AUDMETAFILE" -m 1 | grep -o -P '(?<=>).*(?=<)' | iconv -f utf8 -t ascii//TRANSLIT)"
	if [[ $(echo "$SERIESCMD" | grep "chronological" | wc -l) -ge 1 ]]; then
		notice "Detected 2 book orders. Using Chronological order."
		SERIESCMD="$(grep "chronological" -m 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=,)' | sed -e 's#</a>##' | iconv -f utf8 -t ascii//TRANSLIT)"
		if [[ $(echo "$SERIESCMD" | grep "Book" | wc -l) -lt 1 ]]; then
			notice "Detected possible issue with Book number missing. Being less strict to retrieve it."
			SERIESCMD="$(grep "chronological" -m 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=)' | sed -e 's#</a>##' | iconv -f utf8 -t ascii//TRANSLIT)"
		fi
	fi
	BOOKNUM="$(grep "/series" -A 1 -m 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=)' | cut -d ',' -f 2 | sed -e 's/^[[:space:]]*//' | iconv -f utf8 -t ascii//TRANSLIT)"
	# Don't include book number, if it doesn't actually say which book it is
	if [[ $(echo "$BOOKNUM" | grep "Book" | wc -l ) -lt 1 ]] || [[ $(echo "$BOOKNUM" | grep "Book" | wc -l ) -gt 1 ]]; then
		notice "Detected either no book number, or more than 1 book number."
		BOOKNUM=""
	fi
	SUBTITLE="$(grep "subtitle" -m 1 -A 5 "$AUDMETAFILE" | tail -n1 | sed -e 's/^[[:space:]]*//' | iconv -f utf8 -t ascii//TRANSLIT | tr -dc '[:print:]')"
	if [[ ! -z "$SERIESCMD" && $(echo "$SUBTITLE" | grep "$(echo "$SERIESCMD" | cut -d ' ' -f 1-2)" | wc -l) -ge 1 ]]; then
		notice "Subtitle appears to be the same or similar to series name. Excluding the subtitle."
		SUBTITLE=""
	fi
	BKDATE1="$(grep "releaseDateLabel" -A 3 "$AUDMETAFILE" | tail -n1 | sed -e 's/^[[:space:]]*//' | tr '-' '/' | iconv -f utf8 -t ascii//TRANSLIT)"
	BKDATE="$(date -d "$BKDATE1" +%Y-%m-%d)"

	# Check what metadata we can actually use for the title/name
	m4bvar1="$TICTLECMD" # Default
	if [[ -n $SERIESCMD && -n $BOOKNUM && -z "$SUBTITLE" ]]; then
		m4bvar1="$TICTLECMD ($SERIESCMD, $BOOKNUM)"
	elif [[ -z $SERIESCMD && -z $BOOKNUM && -n "$SUBTITLE" ]]; then
		m4bvar1="$TICTLECMD - $SUBTITLE"
	elif [[ -n $SERIESCMD && -z $BOOKNUM && -z "$SUBTITLE" ]]; then
		m4bvar1="$TICTLECMD ($SERIESCMD)"
	elif [[ -n $SERIESCMD && -z $BOOKNUM && -n "$SUBTITLE" ]]; then
		m4bvar1="$TICTLECMD - $SUBTITLE ($SERIESCMD)"
	elif [[ -n $SERIESCMD && -n $BOOKNUM && -n $SUBTITLE ]]; then
		# Don't include subtitle text if it is just saying what book in the series it is.
		if [[ "$(echo "$SUBTITLE" | grep "$BOOKNUM" | wc -l)" -eq 0 ]]; then
			m4bvar1="$TICTLECMD - $SUBTITLE ($SERIESCMD, $BOOKNUM)"
		else
			m4bvar1="$TICTLECMD ($SERIESCMD, $BOOKNUM)"
		fi
	fi

	m4bvar2="$TICTLECMD"
	m4bvar3="$NARRCMD"
	m4bvar4="$AUTHORCMD"

	makearray

	color_highlight "Metadata parsed as ( Title | Album | Narrator | Author ):"
	color_highlight "$m4bvar1 | $m4bvar2 | $m4bvar3 | $m4bvar4"
	echo ""
	unset m4bvar1 m4bvar2 m4bvar3 m4bvar4
}

function tageditor() {
	if [[ $VERBOSE == "true" ]]; then
		OPT="--verbose"
	fi
	notice "Editing file metadata tags..."
	mid3v2 --track="1/1" --song="$namevar" --album="$albumvar" --TPE2="$albumartistvar" --artist="$artistvar" --date="$BKDATE" $OPT "$(dirname "$SELDIR")"/"$BASESELDIR"
}

function singlefile() {
	if [[ $VERBOSE == "true" ]]; then
		OPT="--verbose"
	fi
	if [[ $sfile == "true" && -n $EXT ]]; then
		if [[ -f $SELDIR ]]; then
			EXT="${SELDIR: -4}"
			tageditor
			mv "$(dirname "$SELDIR")"/"$BASESELDIR" "$OUTPUT"/"$albumartistvar"/"$albumvar"/"$namevar""$EXT" $OPT
		elif [[ -d $SELDIR ]]; then
			mv "$(dirname "$SELDIR")"/"$BASESELDIR"/*.$EXT "$OUTPUT"/"$albumartistvar"/"$albumvar"/"$namevar"."$EXT" $OPT
		fi
	fi
	color_highlight "Processed single input file for $namevar."
}

function makearray() {
	# Put all values into an array
	M4BARR=(
	"--name"
	"${m4bvar1// /_}"
	"--album"
	"${m4bvar2// /_}"
	"--artist"
	"${m4bvar3// /_}"
	"--albumartist"
	"${m4bvar4// /_}"
	"$bitrate"
	"$mbid"
	)

	# Make array into file
	echo "${M4BARR[*]}" > "$M4BSELFILE"
}

function collectmeta() {
	if [[ $BATCHMODE == "true" && $(echo "${FILEIN[@]}" | wc -l) -eq 1 ]]; then
		# This will recursively go through the input folder
		MULTIORNAH="/*"
	fi
	for SELDIR in "${FILEIN[@]}"$MULTIORNAH; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		if [[ $AUDIBLEMETA == "true" ]]; then
			audibleparser
		else
			if [[ $YPROMPT == "true" ]]; then
				useoldmeta="y"
			elif [[ -s $M4BSELFILE ]]; then # Check if we can use an existing metadata entry
				color_highlight "Metadata for $BASESELDIR exists"
				read -e -p 'Use existing metadata? y/n: ' useoldmeta
			elif [[ ! -f $M4BSELFILE ]]; then # Check if we can use an existing metadata entry
				useoldmeta="n"
			fi

			if [[ $useoldmeta == "n" ]]; then
				color_highlight "Enter metadata for $BASESELDIR"
				# Each line has a line after input, adding that value to an array.
				read -e -p 'Enter name: ' m4bvar1
				read -e -p 'Enter Albumname: ' m4bvar2
				read -e -p 'Enter artist (Narrator): ' m4bvar3
				read -e -p 'Enter albumartist (Author): ' m4bvar4
				read -e -p 'Enter bitrate, if any (leave blank for none): ' m4bvar5
				read -e -p 'Enter Musicbrainz ID, if any (leave blank for none): ' m4bvar6

				# Check if we need to include optional arguments in the array
				if [[ -z $m4bvar5 ]]; then
					bitrate=""
				else
					bitrate="--musicbrainz-id='$m4bvar5'"
				fi
				if [[ -z $m4bvar6 ]]; then
					mbid=""
				else
					mbid="--musicbrainz-id='$m4bvar6'"
				fi

				# Call array function
				makearray
			elif [[ -s $M4BSELFILE && $useoldmeta == "y" ]]; then
				color_highlight "Using this metadata then:"
				color_highlight "$(cat "$M4BSELFILE" | tr '_' ' ')"
				echo ""
			fi
		fi
	done
}

function importmetadata() {
	# Basename of array values
	BASESELDIR="$(basename "$SELDIR")"
	M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

	# Import values from file into array.
	readarray M4BSEL <<<"$(cat "$M4BSELFILE" | tr ' ' '\n' | tr '_' ' ')"
	namevar="$(echo "${M4BSEL[1]}" | sed s/\'//g)"
	albumvar="$(echo "${M4BSEL[3]}" | sed s/\'//g)"
	artistvar="$(echo "${M4BSEL[5]}" | sed s/\'//g)"
	albumartistvar="$(echo "${M4BSEL[7]}" | sed s/\'//g)"
}

function batchprocess() {
	if [[ $BATCHMODE == "true" && $(echo "${FILEIN[@]}" | wc -l) -eq 1 ]]; then
		# This will recursively go through the input folder
		INPUTNUM="$(ls "${FILEIN[@]}" | wc -l)"
	else
		INPUTNUM="${#FILEIN[@]}"
	fi
	((COUNTER++))
	# Output number of folders to process
	color_action "Let's begin processing input folders"
	color_highlight "Number of folders to process: $INPUTNUM"

	for SELDIR in "${FILEIN[@]}"$MULTIORNAH; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"
		METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"

		# Import metadata into an array, so we can use it.
		importmetadata

		# Make sure output file exists as expected
		if [[ -s $M4BSELFILE ]]; then
			#echo "Starting conversion of "$namevar""
			mkdir -p "$OUTPUT"/"$albumartistvar"/"$albumvar"
			color_action  "($COUNTER of $INPUTNUM): Processing $albumvar..."

			echo "old='Old size: $(du -hk "$SELDIR" | cut -f 1)'" > "$METADATA"
			# Process input, and determine if we need to run merge, or just cleanup the metadata a bit.
			preprocess
			unset sfile
			((COUNTER++))

			echo "new='New size: $(du -hk "$OUTPUT"/"$albumartistvar"/"$albumvar" | cut -f 1)'" >> "$METADATA"
			echo "processed='true'" >> "$METADATA"
			unset namevar albumvar artistvar albumartistvar
			if [[ $sfile == "false" && -d $SELDIR ]]; then
				rm -rf "$OUTPUT"/"$albumartistvar"/"$albumvar"/*-tmpfiles
			fi
		else
			error "metadata file for $BASESELDIR does not exist"
			exit 1
		fi
	done
}

function batchprocess2() {
	color_highlight "Let's go over the folders that have been processed:"
	for SELDIR in "${FILEIN[@]}"$MULTIORNAH; do
		BASESELDIR="$(basename "$SELDIR")"
		METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"
		AUDMETAFILE="/tmp/.audmeta.$BASESELDIR.txt"

		# Make sure metadata file exists before trying to process it.
		if [[ -s $METADATA ]]; then
			source $METADATA
		else
			error "metadata file for $BASESELDIR not found. Skipping..."
		fi

		# Check that this metadata is ready to process, and then display info to user.
		if [[ "$processed" == "true" ]]; then
			color_highlight "Checking $BASESELDIR ..."
			color_highlight "Previous folder size: $old"
			color_highlight "New folder size: $new"
			read -e -p 'Should this source be deleted? y/n: ' delvar
			if [[ $delvar == "y" ]]; then
				echo "rm -rf "$SELDIR"" >> "$DELTRUE"
				color_action "Pruning old metadata files..."
				if [[ -s $METADATA ]]; then
					rm "$METADATA"
				fi
				if [[ -s $M4BSELFILE ]]; then
					rm "$M4BSELFILE"
				fi
				if [[ -s $AUDMETAFILE ]]; then
					rm "$AUDMETAFILE"
				fi
			fi
		fi
	done

	color_action "Ok, now deleting the folders you confirmed..."

	# Process removal commands on source folders.
	for line in $DELTRUE; do
		color_action "Executing $line"
		"$line"
	done
}

### Style functions ###
function notice () {
    if [[ $VERBOSE == "true" ]]; then
        echo -e "\e[34mNOTICE: $@\e[0m"
    fi
}

function warn () {
    if [[ $VERBOSE == "true" ]]; then
        echo -e "\e[33mWARN: $@\e[0m"
    fi
}

function error () {
	# Color and text for error echoes
    echo -e "\e[91mERROR: $@\e[0m"
}

function color_highlight () {
	# Color and text for error echoes
    echo -e "\e[96m$@\e[0m"
}

function color_action () {
	# Color and text for error echoes
    echo -e "\e[95m$@\e[0m"
}

function pipe() {
	# Function to replace output text with pv.
	if [[ $VERBOSE == "true" ]]; then
		"$@"
	else
		SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
		if [[ ! -f "$SCRIPTDIR"/.pv.lock ]]; then
			"$@"
		else
			"$@" 2> /dev/null | pv -l -p -t -N "Processing" > /dev/null
		fi
	fi
}

function silenterror() {
	if [[ $VERBOSE == "true" ]]; then
		"$@"
	else
		"$@" 2> /dev/null
	fi
}
#### End functions ####

notice "NOTICE: Verbose mode is ON"

#### Checks ####
# Small one time check for 'pv'
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
if [[ ! -f "$SCRIPTDIR"/.pv.lock ]]; then
	if [[ -z $(which pv) ]]; then
		error "The program for progress bar is missing."
		read -e -p 'Install it now? y/n: ' pvvar
		if [[ $pvvar == "y" ]]; then
			color_action "Installing pv..."
			sudo apt-get -y install pv
			if [ $? -eq 0 ]; then
				color_highlight "Done installing."
				touch "$SCRIPTDIR"/.pv.lock
			else
				error "Something went wrong during pv install."
			fi
		fi
	else
		notice "pv installation detected, making lock file"
		touch "$SCRIPTDIR"/.pv.lock
	fi
fi

# Make sure user gave usable INPUT
if [[ -z "${FILEIN[@]}" ]]; then
	error "No file inputs given."
	echo "$usage"
	exit 1
fi

# verify m4b command works properly
if [[ -z $M4BPATH ]]; then
	error "No m4b-tool installation detected. Exiting"
	exit 1
elif [[ -n $($M4BPATH -h) ]]; then
	if [[ $? -ne 0 ]]; then
		error "Could not successfully run m4b-tool, exiting."
		exit 1
	fi
fi
#### End checks ####

# Gather metadata from user
collectmeta
# Process metadata batch
batchprocess

# NOTE: Batchprocess2 is still buggy and needs to be re-written, so it's disabled for now.
#batchprocess2

color_highlight "Script complete."
