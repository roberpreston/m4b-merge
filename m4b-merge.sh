#!/bin/bash
# Script to use m4b-tool to merge audiobooks, easily.
VER=1.0

#LOCAL FOLDERS
TOMOVE="/home/$USER/Downloads/audiobooks/SORTING"
OUTPUT="/mnt/hdd/audiobooks"

M4BPATH="/home/$USER/m4b-tool/m4b-tool.phar"

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
	while getopts ":af:hny" option; do
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

	if [[ -d $SELDIR ]]; then
		# Common extensions for audiobooks.
		# Check input for each of the above file types, ensuring we are not dealing with a pre-merged input.
		EXT1="$(ls "$SELDIR"/*.m4a 2>/dev/null | wc -l)"
		EXT2="$(ls "$SELDIR"/*.mp3 2>/dev/null | wc -l)"
		EXT3="$(ls "$SELDIR"/*.m4b 2>/dev/null | wc -l)"

		if [[ $EXT1 -gt 1 ]]; then
			EXT="m4a"
		elif [[ $EXT2 -gt 1 ]]; then
			EXT="mp3"
		elif [[ $EXT3 -gt 1 ]]; then
			EXT="m4b"
		fi
		FINDCMD="$(ls "$SELDIR"/*.$EXT 2>/dev/null | wc -l)"
		if [[ $FINDCMD -gt 0 && $FINDCMD -le 2 ]]; then
			log "NOTICE: only found $FINDCMD $EXT files in $BASESELDIR. Cleaning up file/folder names, but not running merge."
			sfile="true"
			singlefile
		else
			sfile="false"
			# After we verify the input needs to be merged, lets run the merge command.
			php "$M4BPATH" merge "$SELDIR" --output-file="$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar".m4b "${M4BSEL[@]//$'\n'/}" --force --ffmpeg-threads="$(grep -c ^processor /proc/cpuinfo)" | pv -l -p -t > /dev/null
			echo "Merge completed for $namevar."
		fi
	elif [[ -f $SELDIR ]]; then
		sfile="true"
		singlefile
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
		echo "Fetching metadata from Audible..."
		curl -L -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.89 Safari/537.36" https://www.audible.com/pd/$ASIN -s -o "$AUDMETAFILE"
	fi

	unset useoldmeta

	# Check for multiple narrators
	NARRCMD="$(grep "searchNarrator=" "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=<)' | recode html..ascii)"
	if [[ $(echo "$NARRCMD" | wc -l) -gt 1 ]]; then
		log "NOTICE: Correcting formatting for multiple narrators..."
		NUM="$(echo "$NARRCMD" | wc -l)"
		NARRCMD="$(cat "$AUDMETAFILE" | grep "searchNarrator=" | grep -o -P '(?<=>).*(?=<)' | sed -e "2,${NUM}{s#^#, #}" | tr -d '\n' | recode html..ascii)"
	fi
	AUTHORCMD="$(grep "/author/" "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=<)' | head -n1 | recode html..ascii)"
	# Prefer being strict about authors, unless we can't find them.
	if [[ -z $AUTHORCMD ]]; then
		log "NOTICE: Could not find author using default method. Trying backup method..."
		AUTHORCMD="$(cat "$AUDMETAFILE" | grep "author" | grep -o -P '(?<=>).*(?=<)' | head -n1 | recode html..ascii)"
	fi
	TICTLECMD="$(grep "title" "$AUDMETAFILE" | head -n1 | grep -o -P '(?<=>).*(?=<)' | cut -d '-' -f 1 | sed -e 's/[[:space:]]*$//' | recode html..ascii)"
	SERIESCMD="$(grep "/series?" "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=<)' | recode html..ascii)"
	BOOKNUM="$(grep "/series?" -A 1 "$AUDMETAFILE" | grep -o -P '(?<=>).*(?=)' | cut -d ',' -f 2 | sed -e 's/^[[:space:]]*//' | recode html..ascii)"
	# Don't include book number, if it doesn't actually say which book it is
	if [[ $(echo "$BOOKNUM" | grep "Book" | wc -l ) -lt 1 ]]; then
		BOOKNUM=""
	fi
	SUBTITLE="$(grep "subtitle" -A 5 "$AUDMETAFILE" | tail -n1 | sed -e 's/^[[:space:]]*//' | recode html..ascii | tr -dc '[:print:]')"
	BKDATE1="$(grep "releaseDateLabel" -A 3 "$AUDMETAFILE" | tail -n1 | sed -e 's/^[[:space:]]*//' | tr '-' '/' | recode html..ascii)"
	BKDATE="$(date -d "$BKDATE1" +%Y-%m-%d)"

	# Check what metadata we can actually use for the title/name
	m4bvar1="$TICTLECMD" # Default
	if [[ -n $SERIESCMD && -n $BOOKNUM && -z "$SUBTITLE" ]]; then
		m4bvar1="$TICTLECMD ($SERIESCMD, $BOOKNUM)"
	elif [[ -z $SERIESCMD && -z $BOOKNUM && -n "$SUBTITLE" ]]; then
		m4bvar1="$TICTLECMD - $SUBTITLE"
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

function mp3metaeditor() {
	if [[ $EXT == "mp3" ]]; then
		echo "Editing mp3 tags..."
		mid3v2 "$(dirname "$SELDIR")"/"$BASESELDIR" --song="$m4bvar1" --album="$m4bvar2" --artist="$m4bvar3" --TXXX="ALBUMARTIST:$m4bvar4" --date="$BKDATE"
	fi
}

function singlefile() {
	if [[ $sfile == "true" ]]; then
		if [[ -f $SELDIR ]]; then
			EXT="${SELDIR: -4}"
			mp3metaeditor
			mv "$(dirname "$SELDIR")"/"$BASESELDIR" "$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar""$EXT" --verbose
		elif [[ -d $SELDIR ]]; then
			mv "$(dirname "$SELDIR")"/"$BASESELDIR"/*.$EXT "$TOMOVE"/"$albumartistvar"/"$albumvar"/"$namevar"."$EXT" --verbose
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

		# Import metadata into an array, so we can use it.
		importmetadata

		# Make sure output file exists as expected
		if [[ -s $M4BSELFILE ]]; then
			#echo "Starting conversion of "$namevar""
			mkdir -p "$TOMOVE"/"$albumartistvar"/"$albumvar"
			echo  "($COUNTER of $INPUTNUM): Processing $albumvar..."
			# Process input, and determine if we need to run merge, or just cleanup the metadata a bit.
			preprocess
			unset sfile
			((COUNTER++))

			METADATA="/tmp/.m4bmeta.$BASESELDIR.txt"
			echo "old='Old size: $(du -hk "$SELDIR" | cut -f 1)'" > "$METADATA"
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
		MESSAGE="m4b-merge script has finished processing all specified audiobooks. Waiting on user to tell me what to delete."
		TITLE="m4b-merge finished"
		source "$COMMONCONF"
		curl -s \
	    -F "token=$APP_TOKEN" \
	    -F "user=$USER_TOKEN" \
	    -F "title=$TITLE" \
	    -F "message=$MESSAGE" \
	    https://api.pushover.net/1/messages.json
	fi
}

function log () {
    if [[ $VRBOSE -eq 1 ]]; then
        echo "$@"
    fi
}

### End functions ###

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
tmux new-session -d -s "rclonem4b" rclone move "$TOMOVE" "$OUTPUT" --transfers=1 --verbose --stats 15s

#batchprocess2

echo "Script complete."
