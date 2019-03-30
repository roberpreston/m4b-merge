#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.
## REQUIRES: mid3v2 pv https://github.com/sandreas/m4b-tool
VER=1.0

#LOCAL FOLDERS
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/hdd/audiobooks"

M4BPATH="m4b-tool"
AUDCOOKIES="/tmp/aud-cookies.txt" # Path to cookies file for audible

# Common config, shared between multiple scripts
COMMONCONF="/home/$USER/.config/scripts/common.cfg"


# -h help text to print
usage="	$(basename "$0") $VER [-a] [-f] [-h] [-n] [-v] [-y]

	'-a' Be prompted for Audible ASINs instead of manually entering metadata (BETA)
	'-f' File or folder to run from. Enter multiple files if you need, as: -f file1 -f file2 -f file3
	'-h' This help text.
	'-n' Enable Pushover notifications.
	'-v' Verbose mode.
	'-y' Answer 'yes' to all prompts.
	"

# Flags for this script
	while getopts ":af:hnvy" option; do
 case "${option}" in
	a) AUDIBLEMETA=true
		;;
	f) FILEIN+=("$(realpath "$OPTARG")")
		;;
	h) echo "$usage"
 		exit
		;;
	n) PUSHOVER=true
		;;
	v) VRBOSE=1
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
	EXT1="$(grep -i -r --include \*.m4a '*' "$SELDIR" | wc -l)"
	EXT2="$(grep -i -r --include \*.mp3 '*' "$SELDIR" | wc -l)"
	EXT3="$(grep -i -r --include \*.m4b '*' "$SELDIR" | wc -l)"

	if [[ $EXT1 -ge 1 ]]; then
		EXT="m4a"
	elif [[ $EXT2 -ge 1 ]]; then
		EXT="mp3"
	elif [[ $EXT3 -ge 1 ]]; then
		EXT="m4b"
	elif [[ -z $EXT1 && -z $EXT2 && -z $EXT3 ]]; then
		EXT=""
	fi

	if [[ -d $SELDIR && -n $EXT ]] || [[ -f $SELDIR && $EXT == "m4b" ]]; then
		# After we verify the input needs to be merged, lets run the merge command.
		php "$M4BPATH" merge "$SELDIR" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b "${M4BSEL[@]//$'\n'/}" --force --ffmpeg-threads="$(grep -c ^processor /proc/cpuinfo)" | pv -l -p -t > /dev/null
		echo "Merge completed for $namevar."
	elif [[ -f $SELDIR && $EXT == "mp3" ]]; then
		sfile="true"
		singlefile
	elif [[ -z $EXT ]]; then
		echo "ERROR: No recognized filetypes found for $namevar."
		echo "WARNING: Skipping..."
	fi
}

function audibleparser() {
	AUDMETAFILE="/tmp/.audmeta.$BASESELDIR.txt"

	if [[ $YPROMPT == "true" ]]; then
		useoldmeta="y"
	elif [[ -s $AUDMETAFILE ]]; then # Check if we can use existing audible data
		echo "Cached Audible metadata for $BASESELDIR exists"
		read -e -p 'Use existing metadata? y/n: ' useoldmeta
	elif [[ ! -f $AUDMETAFILE ]]; then # Check if we can use an existing metadata entry
		useoldmeta="n"
	fi

	if [[ $useoldmeta == "n" ]]; then
		RET=1
		until [[ $RET -eq 0 ]]; do
			echo ""
			echo "Enter Audible ASIN for $BASESELDIR"
			read -e -p 'ASIN: ' ASIN

			CHECKASIN="$(curl -o /dev/null -L --silent --head --write-out '%{http_code}\n' https://www.audible.com/pd/$ASIN)"
			RET=$?

			if [[ -z $ASIN ]]; then
				echo "ERROR: No ASIN was entered. Try again."
				RET=1
			elif [[ $CHECKASIN != "200" ]]; then
				echo "ERROR: Could not access ASIN for $BASESELDIR (Was it entered correctly?)"
				RET=1
			elif [[ $CHECKASIN == "200" ]]; then
				RET=0
			fi
		done
	fi
	if [[ ! -s $AUDMETAFILE ]] || [[ -s $AUDMETAFILE && $useoldmeta == "n" ]]; then
		if [[ ! -s $AUDCOOKIES ]]; then
			echo "WARN: Cookie file missing. This may lead to certain elements not working (like series and book numbering)"
		fi
		echo "Fetching metadata from Audible..."
		curl -L -H "User-Agent: Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.2; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0)" --cookie $AUDCOOKIES https://www.audible.com/pd/$ASIN -s -o "$AUDMETAFILE"
	fi

	unset useoldmeta

	# Check for multiple narrators
	NARRCMD="$(grep "searchNarrator=" "$AUDMETAFILE" | grep c1_narrator | grep -o -P '(?<=>).*(?=<)' | sort -u | iconv -f utf8 -t ascii//TRANSLIT)"
	if [[ $(echo "$NARRCMD" | wc -l) -gt 1 ]]; then
		log "NOTICE: Correcting formatting for multiple narrators..."
		NUM="$(echo "$NARRCMD" | wc -l)"
		NARRCMD="$(cat "$AUDMETAFILE" | grep "searchNarrator=" | grep c1_narrator | grep -o -P '(?<=>).*(?=<)' | sort -u | sed -e "2,${NUM}{s#^#, #}" | tr -d '\n' | iconv -f utf8 -t ascii//TRANSLIT)"
	fi
	AUTHORCMD="$(grep "/author/" "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=<)' | head -n1 | iconv -f utf8 -t ascii//TRANSLIT)"
	# Prefer being strict about authors, unless we can't find them.
	if [[ -z $AUTHORCMD ]]; then
		log "NOTICE: Could not find author using default method. Trying backup method..."
		AUTHORCMD="$(cat "$AUDMETAFILE" | grep "author" | grep -o -P '(?<=>).*(?=<)' | head -n1 | iconv -f utf8 -t ascii//TRANSLIT)"
	fi
	TICTLECMD="$(grep "title"  "$AUDMETAFILE" | grep "content=" -m 1 | head -n1 | grep -o -P '(?<=content=").*(?=")' | sed -e 's/[[:space:]]*$//' | iconv -f utf8 -t ascii//TRANSLIT)"
	SERIESCMD="$(grep "/series?" "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=<)' | iconv -f utf8 -t ascii//TRANSLIT)"
	if [[ $(echo "$SERIESCMD" | grep "chronological" | wc -l) -ge 1 ]]; then
		log "NOTICE: Detected 2 book orders. Using Chronological order."
		SERIESCMD="$(grep "chronological" -m 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=,)' | sed -e 's#</a>##' | iconv -f utf8 -t ascii//TRANSLIT)"
		if [[ $(echo "$SERIESCMD" | grep "Book" | wc -l) -lt 1 ]]; then
			log "NOTICE: Detected possible issue with Book number missing. Being less strict to retrieve it."
			SERIESCMD="$(grep "chronological" -m 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=)' | sed -e 's#</a>##' | iconv -f utf8 -t ascii//TRANSLIT)"
		fi
	fi
	BOOKNUM="$(grep "/series?" -A 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=)' | cut -d ',' -f 2 | sed -e 's/^[[:space:]]*//' | iconv -f utf8 -t ascii//TRANSLIT)"
	# Don't include book number, if it doesn't actually say which book it is
	if [[ $(echo "$BOOKNUM" | grep "Book" | wc -l ) -lt 1 ]] || [[ $(echo "$BOOKNUM" | grep "Book" | wc -l ) -gt 1 ]]; then
		log "NOTICE: Detected either no book number, or more than 1 book number."
		BOOKNUM=""
	fi
	SUBTITLE="$(grep "subtitle" -m 1 -A 5 "$AUDMETAFILE" | tail -n1 | sed -e 's/^[[:space:]]*//' | iconv -f utf8 -t ascii//TRANSLIT | tr -dc '[:print:]')"
	if [[ $(echo "$SUBTITLE" | grep "$(echo "$SERIESCMD" | cut -d ' ' -f 1-2)" | wc -l) -ge 1 ]]; then
		log "NOTICE: Subtitle appears to be the same or similar to series name. Excluding the subtitle."
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

	echo "Metadata parsed as ( Title | Album | Narrator | Author ):"
	echo "$m4bvar1 | $m4bvar2 | $m4bvar3 | $m4bvar4"
	echo ""
	unset m4bvar1 m4bvar2 m4bvar3 m4bvar4
}

function tageditor() {
	if [[ $VRBOSE == "1" ]]; then
		OPT="--verbose"
	fi
	log "Editing file metadata tags..."
	mid3v2 --track="1/1" --song="$namevar" --album="$albumvar" --TPE2="$albumartistvar" --artist="$artistvar" --date="$BKDATE" $OPT "$(dirname "$SELDIR")"/"$BASESELDIR"
}

function singlefile() {
	if [[ $VRBOSE == "1" ]]; then
		OPT="--verbose"
	fi
	if [[ $sfile == "true" && -n $EXT ]]; then
		if [[ -f $SELDIR ]]; then
			EXT="${SELDIR: -4}"
			tageditor
			mv "$(dirname "$SELDIR")"/"$BASESELDIR" "$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar""$EXT" $OPT
		elif [[ -d $SELDIR ]]; then
			mv "$(dirname "$SELDIR")"/"$BASESELDIR"/*.$EXT "$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar"."$EXT" $OPT
		fi
	fi
	echo "Processed single input file for $namevar."
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
	#New shits
	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"

		if [[ $AUDIBLEMETA == "true" ]]; then
			audibleparser
		else
			if [[ $YPROMPT == "true" ]]; then
				useoldmeta="y"
			elif [[ -s $M4BSELFILE ]]; then # Check if we can use an existing metadata entry
				echo "Metadata for $BASESELDIR exists"
				read -e -p 'Use existing metadata? y/n: ' useoldmeta
			elif [[ ! -f $M4BSELFILE ]]; then # Check if we can use an existing metadata entry
				useoldmeta="n"
			fi

			if [[ $useoldmeta == "n" ]]; then
				echo -e "\e[92mEnter metadata for $BASESELDIR\e[0m"
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
				echo "Using this metadata then:"
				echo "$(cat "$M4BSELFILE" | tr '_' ' ')"
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
	INPUTNUM="${#FILEIN[@]}"
	((COUNTER++))
	# Output number of folders to process
	echo "Let's begin processing input folders"
	echo "Number of folders to process: $INPUTNUM"

	for SELDIR in "${FILEIN[@]}"; do
		# Basename of array values
		BASESELDIR="$(basename "$SELDIR")"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"
		METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"

		# Import metadata into an array, so we can use it.
		importmetadata

		# Make sure output file exists as expected
		if [[ -s $M4BSELFILE ]]; then
			#echo "Starting conversion of "$namevar""
			mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
			echo  "($COUNTER of $INPUTNUM): Processing $albumvar..."

			echo "old='Old size: $(du -hk "$SELDIR" | cut -f 1)'" > "$METADATA"
			# Process input, and determine if we need to run merge, or just cleanup the metadata a bit.
			preprocess
			unset sfile
			((COUNTER++))

			echo "new='New size: $(du -hk "$TOMOVE"/"$albumartistvar"/"$albumvar" | cut -f 1)'" >> "$METADATA"
			echo "processed='true'" >> "$METADATA"
			unset namevar albumvar artistvar albumartistvar
			if [[ $sfile == "false" && -d $SELDIR ]]; then
				rm -rf "$TOMOVE"/"$albumartistvar"/"$albumvar"/*-tmpfiles
			fi
		else
			echo "ERROR: metadata file for $BASESELDIR does not exist"
			exit 1
		fi
	done
}

function batchprocess2() {
	echo "Let's go over the folders that have been processed:"
	for SELDIR in "${FILEIN[@]}"; do
		BASESELDIR="$(basename "$SELDIR")"
		METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"
		M4BSELFILE="/tmp/.m4bmerge.$BASESELDIR.txt"
		AUDMETAFILE="/tmp/.audmeta.$BASESELDIR.txt"

		# Make sure metadata file exists before trying to process it.
		if [[ -s $METADATA ]]; then
			source $METADATA
		else
			echo "ERROR: metadata file for $BASESELDIR not found. Skipping..."
		fi

		# Check that this metadata is ready to process, and then display info to user.
		if [[ "$processed" == "true" ]]; then
			echo "Checking $BASESELDIR ..."
			echo "Previous folder size: $old"
			echo "New folder size: $new"
			read -e -p 'Should this source be deleted? y/n: ' delvar
			if [[ $delvar == "y" ]]; then
				echo "rm -rf "$SELDIR"" >> "$DELTRUE"
				echo "Pruning old metadata files..."
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

	echo "Ok, now deleting the folders you confirmed..."

	# Process removal commands on source folders.
	for line in $DELTRUE; do
		echo "Executing $line"
		"$line"
	done
}

function pushovr() {
	# Check if user wanted notifications
	if [ "$PUSHOVER" = "true" ]; then
		log "Sending Pushover notification..."
		if [[ $VRBOSE == "1" ]]; then
			OPT="--verbose"
		else
			OPT="--silent > /dev/null"
		fi
		MESSAGE="m4b-merge script has finished processing all specified audiobooks. Waiting on user to tell me what to delete."
		TITLE="m4b-merge finished"
		source "$COMMONCONF"
		curl \
	    -F "token=$APP_TOKEN" \
	    -F "user=$USER_TOKEN" \
	    -F "title=$TITLE" \
	    -F "message=$MESSAGE" \
	    https://api.pushover.net/1/messages.json "$OPT"
	fi
}

function log () {
    if [[ $VRBOSE -eq 1 ]]; then
        echo "$@"
    fi
}

### End functions ###

log "NOTICE: Verbose mode is ON"

# Small one time check for 'pv'
if [[ ! -f "$(dirname "$M4BPATH")"/.pv.lock ]]; then
	if [[ $(which pv) == "" ]]; then
		echo "The program for progress bar is missing."
		read -e -p 'Install it now? y/n: ' pvvar
		if [[ $pvvar == "y" ]]; then
			sudo apt-get install pv
		fi
		touch "$(dirname "$M4BPATH")"/.pv.lock
	fi
fi

# Make sure user gave usable INPUT
if [[ -z ${FILEIN[@]} ]]; then
	echo "ERROR: No file inputs given."
	echo "$usage"
	exit 1
fi

# Gather metadata from user
collectmeta
# Process metadata batch
batchprocess
# Send notification
pushovr

log "Starting rclone background move"
tmux new-session -d -s "rclonem4b" rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 15s; find "$TOMOVE" -type d -empty -delete

# NOTE: Batchprocess2 is still buggy and needs to be re-written, so it's disabled for now.
#batchprocess2

echo "Script complete."
